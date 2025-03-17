import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:virtstab/blue.dart';
import 'package:virtstab/devices/phone_sensors.dart';
import 'package:virtstab/devices/sensor_device.dart';
import 'package:virtstab/pulse.dart';
import 'package:virtstab/styles.dart';
import 'package:virtstab/utils.dart';
import 'package:virtstab/widgets/app_title.dart';
import 'package:virtstab/widgets/gauge.dart';
import 'package:virtstab/widgets/spline.dart';
import 'package:virtstab/widgets/stat_box.dart';

void main() {
  runApp(const MyApp());
}

// styles
const px = 48.0;
const statSize = 128.0;
const scrollDuration = Duration(milliseconds: 500);
// config
const minThreshold = 10.0;
const maxThreshold = 60.0;
const defaultThreshold = 15.0;
const defaultAlertDelay = 4; // seconds avg
const bluetoothDeviceName = "HC-05";
// spline
const window = 5; // window window
const points = 10;

final phoneSensors = SensorDevice(device: PhoneSensors(), name: 'Sensors');

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
  bool _scrolled = false;
  int _alertsCount = 0;
  DateTime? _connectedAt;
  // config
  double _threshold = defaultThreshold;
  int _alertDelay = defaultAlertDelay;
  // device
  final List<SensorDevice> _devices = [];
  SensorDevice _device = phoneSensors;
  final _scanning = ValueNotifier(false);
  bool _connecting = false;
  // audio
  final _player = AudioPlayer();
  bool _muted = false;

  // getters

  bool get connected => _device.isConnected;

  String get activeTime {
    if (_connectedAt == null) return '0\' 0"';
    final diff = DateTime.now().difference(_connectedAt!);
    return '${diff.inHours}\' ${diff.inMinutes - diff.inHours * 60}"';
  }

  List<ChartData> get pulsesData {
    final len = _device.pulses.length;
    final data = List.generate(points, (i) {
      final currWindow = (points - i) * window;
      if (len > currWindow) {
        final slice = _device.pulses.sublist(
          len - currWindow,
          len - currWindow + window,
        );
        final total = slice.map((p) => p.angle).reduce((a, b) => a + b);
        final avg = total / slice.length.toDouble();
        return ChartData(i, avg);
      }
      return ChartData(i, 0);
    });
    return data;
  }

  String get connectionState =>
      _connecting
          ? 'connecting'
          : connected
          ? 'connected'
          : 'disconnected';

  String get connectionStatus {
    if (_connecting) {
      return "Connecting to ${_device.name}...";
    } else if (connected) {
      return "Connected to ${_device.name}!";
    } else {
      return "Disconnected from ${_device.name}!";
    }
  }

  Color get primary => Theme.of(context).colorScheme.primary;
  Color get secondary => Theme.of(context).colorScheme.secondary;
  Color get elevatedColor => secondary.withAlpha(25);

  @override
  void initState() {
    scanAndConnect();
    _scrollController.addListener(scrollListener);
    connectToDevice(_device); // no await - default sensors
    super.initState();
  }

  @override
  void dispose() async {
    await disconnectActiveDevice();
    _scrollController.removeListener(scrollListener);
    _scrollController.dispose();
    super.dispose();
  }

  // Scroll

  void scrollListener() {
    final max = _scrollController.position.maxScrollExtent;
    if (_scrollController.offset == max && !_scrolled) {
      _scrolled = true;
      setState(() {});
    } else if (_scrollController.offset == 0 && _scrolled) {
      _scrolled = false;
      setState(() {});
    }
  }

  Future<void> _scrollToggle() async {
    if (_scrolled) {
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

  // Audio Alert

  void checkAngleAlert() async {
    if (_muted) return;
    if (_device.pulses.length < _alertDelay) return;
    final start = _device.pulses.length - _alertDelay;
    final total = _device.pulses
        .sublist(start)
        .map((p) => p.angle)
        .reduce((a1, a2) => a1 + a2);
    final avgAngle = total / _alertDelay;
    if (avgAngle < _threshold) return;
    if (_player.state == PlayerState.completed) {
      _alertsCount++;
      setState(() {});
    }
    await _player.play(AssetSource('alert.mp3'));
  }

  // Device

  Future<void> scanAndConnect() async {
    _scanning.value = true;
    setState(() {});
    // look for bluetooth devices
    await scanDevices();
    if (_devices.length > 1) {
      await connectToDevice(_devices[1]);
    }
    _scanning.value = false;
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

      // add phone-sensor
      _devices.add(phoneSensors);

      // Get a list of paired devices
      final devices = await FlutterBluetoothSerial.instance.getBondedDevices();

      // Find HC-05
      for (final device in devices) {
        if (device.name == bluetoothDeviceName) {
          _devices.add(SensorDevice.fromBluetoothDevice(device));
          setState(() {});
        }
      }
    } catch (err) {
      if (kDebugMode) print('>> scan: $err');
      setState(() {});
    }
  }

  Future<void> disconnectActiveDevice() async {
    await _device.disconnect(); // clear device data
    if (kDebugMode) print(">> Disconnected.");
    setState(() {});
  }

  Future<void> connectToDevice(SensorDevice device) async {
    _connecting = true;
    try {
      // Connect to device
      if (device == _device) await disconnectActiveDevice();
      if (!await device.connect()) throw 'Cannot conenct';
      if (kDebugMode) print(">> Removing previous device");
      if (device != _device) await disconnectActiveDevice();
      _device = device; // set active device
      _connectedAt = DateTime.now();
      setState(() {});

      // Listen for incoming data
      device.input?.listen((Pulse data) {
        if (kDebugMode) print('chunk: $data');
        setState(() {}); // ensure data is up to date to user
        checkAngleAlert(); // play alert
      });

      // Send data
      await device.begin();
      if (kDebugMode) print(">> Ack sent!");
    } catch (err) {
      if (kDebugMode) print('>> connect: $err');
      setState(() {});
    }
    _connecting = false;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: buildNavigationBar(),
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
                SafeArea(top: true, child: AppTitle()),

                // Guage
                const SizedBox(height: 12),
                Transform.translate(
                  offset: Offset(0, -160),
                  child: Gauge(
                    angle: _device.pulses.lastOrNull?.angle ?? 0,
                    threshold: _threshold,
                  ),
                ),

                // Messages
                const SizedBox(height: 48),
                Text(connectionStatus, textAlign: TextAlign.center),
                Text(
                  _device.calibCountDown == 0
                      ? 'Reference at ${_device.calib.pitch.round()}°, ${_device.calib.roll.round()}°'
                      : 'Set Reference (${_device.calibCountDown}s)',
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
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      backgroundColor: WidgetStatePropertyAll(elevatedColor),
                    ),
                    icon: Transform.rotate(
                      angle: (_scrolled ? 90 : -90).toDouble().toRadian(),
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
                    'Threshold: ${(_threshold).toStringAsFixed(0)}°',
                    style: textStyleBold,
                    textAlign: TextAlign.center,
                  ),
                ),
                Slider(
                  min: minThreshold,
                  max: maxThreshold,
                  value: _threshold,
                  padding: EdgeInsets.symmetric(
                    horizontal: px + 12,
                    vertical: 12,
                  ),
                  thumbColor: primary,
                  activeColor: secondary.withAlpha(70),
                  inactiveColor: Colors.transparent,
                  divisions: 5,
                  onChanged: (v) {
                    _threshold = v;
                    setState(() {});
                  },
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'Alert Delay: ${_alertDelay}s',
                    style: textStyleBold,
                    textAlign: TextAlign.center,
                  ),
                ),
                Slider(
                  min: 1,
                  max: 10,
                  value: _alertDelay.toDouble(),
                  padding: EdgeInsets.symmetric(
                    horizontal: px + 12,
                    vertical: 12,
                  ),
                  thumbColor: primary,
                  activeColor: secondary.withAlpha(70),
                  inactiveColor: Colors.transparent,
                  divisions: 10,
                  onChanged: (v) {
                    _alertDelay = v.toInt();
                    setState(() {});
                  },
                ),

                // Statistics
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

  Widget statBuilder(BuildContext context, int i) {
    return Container(
      width: statSize,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: elevatedColor,
      ),
      child: stats[i],
    );
  }

  List<Widget> get stats {
    return [
      Spline(
        chartData: pulsesData,
        maximum: _threshold * 2,
        title: Text('Movement', style: textStyleBold),
      ),
      StatBox(
        title: 'Alerts',
        content: Text(
          '$_alertsCount',
          style: TextStyle(
            fontSize: 64,
            fontWeight: FontWeight.w200,
            color: primary,
          ),
        ),
        caption: 'times',
      ),
      StatBox(
        title: 'Active',
        content: Text(
          activeTime,
          style: TextStyle(
            fontSize: 44,
            fontWeight: FontWeight.w200,
            color: primary,
          ),
        ),
        caption: 'hours',
      ),
      InkWell(
        onTap: openSelectionDialog,
        radius: 16,
        child: StatBox(
          title: 'Device',
          content: Text(
            _device.name,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w200,
              color: connected ? primary : Colors.redAccent.shade100,
            ),
            maxLines: 1,
          ),
          caption: connectionState,
        ),
      ),
    ];
  }

  Widget selectDialogItem(SensorDevice item) {
    return SimpleDialogOption(
      child: Text(item.name),
      onPressed: () async {
        Navigator.pop(context);
        _device = item;
        await connectToDevice(item);
        setState(() {});
      },
    );
  }

  void openSelectionDialog() async {
    scanDevices();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return ValueListenableBuilder(
          valueListenable: _scanning,
          builder: (context, value, child) {
            return SimpleDialog(
              title: Text('Select a device'),
              children: _devices.map(selectDialogItem).toList(),
            );
          },
        );
      },
    );
  }

  Widget buildNavigationBar() {
    return BottomAppBar(
      color: Colors.transparent,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 32,
        children: [
          IconButton(
            icon: Icon(
              _muted
                  ? Icons.notifications_off_rounded
                  : Icons.notifications_rounded,
              size: 22,
            ),
            color: _muted ? Colors.redAccent.shade100 : null,
            onPressed: () {
              _muted = !_muted;
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
            color: _device.calibCountDown > 0 ? primary : null,
            icon: Icon(Icons.adjust, size: 22),
            onPressed: _device.calibrate,
          ),
          IconButton(
            icon: Icon(Icons.bluetooth_rounded, size: 22),
            onPressed:
                () => connectToDevice(_device), // connect selected device
            color: _connecting ? primary : null,
          ),
        ],
      ),
    );
  }
}
