import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:virtstab/blue.dart';
import 'package:virtstab/pulse.dart';
import 'package:virtstab/utils.dart';
import 'package:virtstab/widgets/gauge.dart';
import 'package:virtstab/widgets/spline.dart';

void main() {
  runApp(const MyApp());
}

// config
const keys = ['ax', 'ay', 'az', 'gx', 'gy', 'gz'];
const minThreshold = 10.0;
const maxThreshold = 60.0;
const defaultThreshold = 15.0;
const calibLerpFactor = 0.33;
const setRefCount = 3;
const defaultAlertDelay = 4; // seconds avg

// styles
const px = 48.0;
const textStyleBold = TextStyle(fontWeight: FontWeight.bold);
const statSize = 128.0;
const scrollDuration = Duration(milliseconds: 500);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VirtStab',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.dark(
          primary: Colors.limeAccent.shade200,
          secondary: Colors.blueAccent.shade100,
        ).copyWith(surface: Colors.black),
      ),
      themeMode: ThemeMode.dark,
      home: const MyHomePage(title: 'VirtStab'),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final ScrollController _scrollController = ScrollController();
  int alertsCount = 0;
  DateTime? connectedAt;
  // config
  double threshold = defaultThreshold;
  int alertDelay = defaultAlertDelay;
  String _message = '';
  // device
  final List<BluetoothDevice> _devices = [];
  BluetoothDevice? _device;
  BluetoothConnection? connection;
  bool scanning = false;
  // data
  String _buffer = '';
  final List<Pulse> _pulses = [];
  // calibrate
  final _calib = Pulse.zero();
  int _calibCountDown = 0;
  // audio
  final player = AudioPlayer();
  bool muted = false;

  // getters
  bool get connected => _device != null && (connection?.isConnected ?? false);

  String get activeTime {
    if (connectedAt == null) return '0\' 0"';
    final diff = DateTime.now().difference(connectedAt!);
    return '${diff.inHours}\' ${diff.inMinutes - diff.inHours * 60}"';
  }

  bool scrolled = false;

  List<ChartData> get pulsesData {
    final window = 5; // window window
    final points = 10;
    // final maxWindow = points * window;
    final len = _pulses.length;
    final data = List.generate(points, (i) {
      final currWindow = (points - i) * window;
      if (len > currWindow) {
        final slice = _pulses.sublist(
          len - currWindow,
          len - currWindow + window,
        );
        final total = slice.map((p) => p.angle).reduce((a, b) => a + b);
        final avg = total / slice.length.toDouble();
        return ChartData(i, avg);
      }
      return ChartData(i, 5);
    });
    return data;
  }

  @override
  void initState() {
    scanAndConnect();
    _scrollController.addListener(scrollListener);
    _scrollController.dispose();
    super.initState();
  }

  @override
  void dispose() async {
    await disconnectDevice();
    _scrollController.removeListener(scrollListener);
    super.dispose();
  }

  // Scroll

  void scrollListener() {
    final max = _scrollController.position.maxScrollExtent;
    if (_scrollController.offset == max && !scrolled) {
      scrolled = true;
      setState(() {});
    } else if (_scrollController.offset == 0 && scrolled) {
      scrolled = false;
      setState(() {});
    }
  }

  Future<void> _scrollToggle() async {
    if (scrolled) {
      await _scrollToTop();
    } else {
      await _scrollToBottom();
    }
    setState(() {}); // update button
  }

  Future<void> _scrollToTop() async {
    await _scrollController.animateTo(
      _scrollController.position.minScrollExtent,
      duration: scrollDuration,
      curve: Curves.easeInOut,
    );
  }

  Future<void> _scrollToBottom() async {
    await _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: scrollDuration,
      curve: Curves.easeInOut,
    );
  }

  //  Calibration

  void beginCalibrate() {
    if (!connected) return;
    _calibCountDown = setRefCount;
  }

  void calibLerp() {
    final pulse = _pulses.lastOrNull;
    if (pulse == null) return;
    if (_calibCountDown == 0) return;
    if (_calibCountDown == setRefCount) {
      _calib.a = pulse.a;
      _calib.g = pulse.g;
    } else {
      final a = calibLerpFactor;
      _calib.a = _calib.a.lerp(pulse.a, a);
      _calib.g = _calib.g.lerp(pulse.g, a);
    }
    _calibCountDown -= 1;
    setState(() {});
  }

  // Audio Alert

  void checkAngleAlert() async {
    if (muted) return;
    if (_pulses.length < alertDelay) return;
    final start = _pulses.length - alertDelay;
    final total = _pulses
        .sublist(start)
        .map((p) => p.angle)
        .reduce((a1, a2) => a1 + a2);
    final avgAngle = total / alertDelay;
    if (avgAngle < threshold) return;
    if (player.state == PlayerState.completed) {
      alertsCount++;
      setState(() {});
    }
    await player.play(AssetSource('alert.mp3'));
  }

  // Device

  Future<void> scanAndConnect() async {
    scanning = true;
    setState(() {});
    // look for bluetooth devices
    await scanDevices();
    if (_devices.isNotEmpty) {
      await connectToDevice(_devices[0]);
    }
    scanning = false;
    setState(() {});
  }

  Future<void> scanDevices() async {
    try {
      // Skip permission request on Linux
      if (Platform.isAndroid || Platform.isIOS) {
        await requestBluetoothPermissions();
      }

      // reset previous list
      _devices.clear();

      // Get a list of paired devices
      final devices = await FlutterBluetoothSerial.instance.getBondedDevices();

      // Find HC-05
      for (final device in devices) {
        if (device.name == "HC-05") {
          _devices.add(device);
          setState(() {});
        }
      }

      if (_devices.isEmpty) {
        _message = 'Device not found!';
        setState(() {});
      }
    } catch (err) {
      if (kDebugMode) print('>> scan: $err');
      _message = "Can't scan bluetooth devices!";
      setState(() {});
    }
  }

  Future<void> disconnectDevice() async {
    // clear device data
    _device = null;
    _pulses.clear();
    _buffer = '';
    _calib.reset();
    setState(() {});
    // Close connection
    await connection?.finish();
    connection?.dispose();
    if (kDebugMode) print(">> Disconnected.");
    _message = 'Disconnected!';
    setState(() {});
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    try {
      if (connection != null) {
        await disconnectDevice();
        if (kDebugMode) print(">> Removing previous connection");
      }

      // Set active device
      _device = device;
      setState(() {});

      // Connect to HC-05
      connection = await BluetoothConnection.toAddress(device.address);
      _message = "Connected to ${device.name}";
      connectedAt = DateTime.now();
      setState(() {});

      // Listen for incoming data
      connection!.input?.listen((Uint8List data) {
        final output = String.fromCharCodes(data);
        _buffer += output;
        parseOutputToPulses();
      });

      // Send data
      connection!.output.add(Uint8List.fromList("A".codeUnits));
      await connection!.output.allSent;
      if (kDebugMode) print(">> Ack sent!");
    } catch (err) {
      if (kDebugMode) print('>> connect: $err');
      _message = 'Cannot connect, Try again!';
      setState(() {});
    }
  }

  // Main Pulse Parser

  void parseOutputToPulses() {
    final boxes = _buffer.split('ax:');
    // ignore last one - maybe it's not complete yet
    for (int i = 0; i < boxes.length - 2; i++) {
      // validate integrity of box
      final box = 'ax:${boxes[i]}';
      final corrupt = keys.any((k) => !box.contains(k));
      if (corrupt) continue; // incomplete, let it append later on
      final previous = _pulses.isEmpty ? null : _pulses.first;
      final pulse = Pulse.fromString(box, previous, _calib);
      _pulses.add(pulse); // add pulse
      checkAngleAlert(); // play alert
      calibLerp(); // calibrate
      _buffer = _buffer.replaceFirst(box, ''); // remove used box
      setState(() {});
    }
  }

  Color get onSurface => Theme.of(context).colorScheme.onSurface;
  Color get primary => Theme.of(context).colorScheme.primary;
  Color get secondary => Theme.of(context).colorScheme.secondary;
  Color get elevatedColor => secondary.withAlpha(25);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: buildNavBar(),
      body: SizedBox(
        child: SingleChildScrollView(
          controller: _scrollController,
          child: Padding(
            padding: EdgeInsets.all(0),
            child: Column(
              spacing: 12,
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Title
                const SizedBox(height: 12),
                SafeArea(top: true, child: buildTitle()),

                // Guage
                const SizedBox(height: 12),
                Transform.translate(
                  offset: Offset(0, -160),
                  child: Gauge(
                    angle: _pulses.lastOrNull?.angle ?? 0,
                    threshold: threshold,
                  ),
                ),

                // Messages
                const SizedBox(height: 48),
                Text(
                  _message.isEmpty ? 'Everything is fine!' : _message,
                  textAlign: TextAlign.center,
                ),
                Text(
                  _calibCountDown == 0
                      ? 'Reference at ${_calib.pitch.round()}°, ${_calib.roll.round()}°'
                      : 'Set Reference (${_calibCountDown}s)',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: primary),
                ),

                // Scroll Down
                const SizedBox(height: 32),
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  child: IconButton(
                    onPressed: _scrollToggle,
                    padding: EdgeInsets.zero,
                    style: ButtonStyle(
                      shape: WidgetStatePropertyAll(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            12,
                          ), // Adjust radius here
                        ),
                      ),
                      backgroundColor: WidgetStatePropertyAll(elevatedColor),
                    ),
                    icon: Transform.rotate(
                      angle: (scrolled ? 90 : -90).toDouble().toRadian(),
                      child: Icon(Icons.chevron_left),
                    ),
                    color: primary,
                  ),
                ),

                // Sliders
                const SizedBox(height: 48),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'Threshold: ${(threshold).toStringAsFixed(0)}°',
                    style: textStyleBold,
                    textAlign: TextAlign.center,
                  ),
                ),
                Slider(
                  min: minThreshold,
                  max: maxThreshold,
                  value: threshold,
                  padding: EdgeInsets.symmetric(
                    horizontal: px + 12,
                    vertical: 12,
                  ),
                  thumbColor: primary,
                  activeColor: secondary.withAlpha(70),
                  inactiveColor: Colors.transparent,
                  divisions: 5,
                  onChanged: (v) {
                    threshold = v;
                    setState(() {});
                  },
                ),

                const SizedBox(height: 8),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'Alert Delay: ${alertDelay}s',
                    style: textStyleBold,
                    textAlign: TextAlign.center,
                  ),
                ),
                Slider(
                  min: 1,
                  max: 10,
                  value: alertDelay.toDouble(),
                  padding: EdgeInsets.symmetric(
                    horizontal: px + 12,
                    vertical: 12,
                  ),
                  thumbColor: primary,
                  activeColor: secondary.withAlpha(70),
                  inactiveColor: Colors.transparent,
                  divisions: 10,
                  onChanged: (v) {
                    alertDelay = v.toInt();
                    setState(() {});
                  },
                ),

                // Charts
                const SizedBox(height: 68),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: px),
                  child: Text(
                    'Statistics',
                    style: textStyleBold,
                    textAlign: TextAlign.left,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: statSize,
                  child: ListView.separated(
                    itemCount: stats.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 20),
                    scrollDirection: Axis.horizontal,
                    itemBuilder: statBuilder,
                    padding: EdgeInsets.symmetric(horizontal: px),
                  ),
                ),

                const SizedBox(height: 68),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget buildTitle() {
    return Text.rich(
      textAlign: TextAlign.center,
      TextSpan(
        style: TextStyle(fontSize: 24, letterSpacing: 8),
        children: [
          TextSpan(
            text: '.:: ',
            style: TextStyle(
              color: secondary.withAlpha(30),
            ), // Semi-transparent
          ),
          TextSpan(
            text: 'VIRT',
            style: TextStyle(color: secondary.withAlpha(50)), // Blue text
          ),
          TextSpan(
            text: 'STAB',
            style: TextStyle(color: onSurface.withAlpha(140)), // Blue text
          ),
          TextSpan(
            text: ' ::.',
            style: TextStyle(
              color: secondary.withAlpha(30),
            ), // Semi-transparent
          ),
        ],
      ),
    );
  }

  List<Widget> get stats {
    return [
      Spline(
        chartData: pulsesData,
        maximum: threshold * 2,
        title: Text('Movement', style: textStyleBold),
      ),
      buildStatBox(
        title: 'Alerts',
        content: Text(
          '$alertsCount',
          style: TextStyle(
            fontSize: 64,
            fontWeight: FontWeight.w200,
            color: primary,
          ),
        ),
        caption: 'times',
      ),
      buildStatBox(
        title: 'Active',
        content: Text(
          '$activeTime',
          style: TextStyle(
            fontSize: 44,
            fontWeight: FontWeight.w200,
            color: primary,
          ),
        ),
        caption: 'hours',
      ),
      if (_device != null)
        buildStatBox(
          title: 'Device',
          content: Text(
            '${_device!.name}',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w200,
              color: connected ? primary : Colors.redAccent.shade100,
            ),
            maxLines: 1,
          ),
          caption: connected ? 'connected' : 'disconnected!',
        ),
    ];
  }

  Widget buildStatBox({
    required String title,
    required Widget content,
    required String caption,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: textStyleBold),
              Spacer(),
              content,
              Spacer(flex: 2),
            ],
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Text(
              caption.toUpperCase(),
              style: TextStyle(
                color: onSurface.withAlpha(120),
                letterSpacing: 2,
                fontSize: 12,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget statBuilder(BuildContext context, int i) {
    return Container(
      width: statSize,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: elevatedColor,
      ),
      child: stats[i],
      // child: Stack(),
    );
  }

  Widget buildNavBar() {
    return BottomAppBar(
      color: Colors.transparent,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 32,
        children: [
          IconButton(
            icon: Icon(
              muted
                  ? Icons.notifications_off_rounded
                  : Icons.notifications_rounded,
              size: 22,
            ),
            color: muted ? Colors.redAccent.shade100 : null,
            onPressed: () {
              muted = !muted;
              setState(() {});
            },
          ),
          IconButton(
            style: ButtonStyle(
              padding: WidgetStatePropertyAll(
                EdgeInsets.symmetric(vertical: 12, horizontal: 32),
              ),
              backgroundColor: WidgetStatePropertyAll(elevatedColor),
            ),
            color: _calibCountDown > 0 ? primary : null,
            icon: Icon(Icons.adjust, size: 22),
            onPressed: beginCalibrate,
          ),
          IconButton(
            icon: Icon(Icons.bluetooth_rounded, size: 22),
            onPressed: scanAndConnect,
            color: scanning ? primary : null,
          ),
        ],
      ),
    );
  }
}
