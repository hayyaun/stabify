import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stabify/blue.dart';
import 'package:stabify/devices/drcad_device.dart';
import 'package:stabify/devices/phone_sensors.dart';
import 'package:stabify/devices/sensor_device.dart';
import 'package:stabify/pulse.dart';
import 'package:stabify/styles.dart';
import 'package:stabify/utils.dart';
import 'package:stabify/widgets/gauge.dart';
import 'package:stabify/widgets/gradient_mask.dart';
import 'package:stabify/widgets/spline.dart';
import 'package:stabify/widgets/stat_box.dart';

void main() {
  runApp(const MyApp());
}

// styles
const px = 48.0;
const statSize = 128.0;
const scrollDuration = Duration(milliseconds: 500);
// config
const appName = 'Stabify';
const appNameUpper = 'STABIFY';
const minThreshold = 10.0;
const maxThreshold = 60.0;
const defaultThreshold = 30.0;
const defaultAlertDelay = 4; // seconds avg
// spline
const window = 5; // window window
const points = 10;

final phoneSensors = PhoneSensors(name: 'Phone');

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appName,
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
      home: const MyHomePage(title: appName),
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
  final _scrolled = ValueNotifier(false);
  final _alertsCount = ValueNotifier(0);
  // config - persisted
  double _threshold = defaultThreshold;
  int _alertDelay = defaultAlertDelay;
  String? _lastDeviceAddress;
  // device
  final List<SensorDevice> _devices = [];
  SensorDevice _device = phoneSensors;
  final _scanning = ValueNotifier(false);
  final _connecting = ValueNotifier(false);
  // audio
  final _player = AudioPlayer();
  bool _muted = false;

  // getters

  bool get connected => _device.isConnected;

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
      _connecting.value
          ? 'connecting'
          : connected
          ? 'connected'
          : 'disconnected';

  String get connectionStatus {
    if (_connecting.value) {
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

  // prefs

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _threshold = prefs.getDouble('threshold') ?? defaultThreshold;
    _alertDelay = prefs.getInt('alertDelay') ?? defaultAlertDelay;
    _lastDeviceAddress = prefs.getString('lastDeviceAddress');
    if (kDebugMode) {
      print(
        'prefs: threshold:$_threshold alertDelay:$_alertDelay lastDeviceAddress:$_lastDeviceAddress',
      );
    }
    setState(() {});
  }

  Future<void> _updateThreshold(double value) async {
    final prefs = await SharedPreferences.getInstance();
    _threshold = value;
    await prefs.setDouble('threshold', _threshold);
    setState(() {});
  }

  Future<void> _updateAlertDelay(double value) async {
    final prefs = await SharedPreferences.getInstance();
    _alertDelay = value.toInt();
    await prefs.setInt('alertDelay', _alertDelay);
    setState(() {});
  }

  Future<void> _updateDevice(SensorDevice value) async {
    final prefs = await SharedPreferences.getInstance();
    _device = value;
    if (value.address?.isNotEmpty ?? false) {
      await prefs.setString('lastDeviceAddress', value.address!);
    }
    setState(() {});
  }

  // overrides

  @override
  void initState() {
    _loadPrefs().then((_) {
      _onInitScanAndConnect(); // sets _device
    });
    _scrollController.addListener(scrollListener);
    super.initState();
  }

  @override
  void dispose() async {
    await _device.disconnect();
    _scrollController.removeListener(scrollListener);
    _scrollController.dispose();
    super.dispose();
  }

  // Scroll

  void scrollListener() {
    final max = _scrollController.position.maxScrollExtent;
    if (_scrollController.offset == max && !_scrolled.value) {
      _scrolled.value = true;
    } else if (_scrollController.offset == 0 && _scrolled.value) {
      _scrolled.value = false;
    }
  }

  Future<void> _scrollToggle() async {
    if (_scrolled.value) {
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
      _alertsCount.value++;
    }
    await _player.play(AssetSource('alert.mp3'));
  }

  // Device

  Future<void> _onInitScanAndConnect() async {
    _scanning.value = true;
    // look for bluetooth devices
    await scanDevices();
    // connect to last device connected
    final lastDevice =
        _devices.where((d) => d.address == _lastDeviceAddress).firstOrNull;
    if (lastDevice != null) {
      await connectToDevice(lastDevice);
    } else {
      await connectToDevice(_device);
    }
    _scanning.value = false;
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

      // Find and relate devices to their class
      for (final device in devices) {
        if (DrcadDevice.isValidDevice(device)) {
          _devices.add(DrcadDevice.fromBluetoothDevice(device));
        }
      }
    } catch (err) {
      if (kDebugMode) print('>> scan: $err');
    }
    setState(() {});
  }

  Future<void> connectToDevice(SensorDevice device) async {
    _connecting.value = true;
    try {
      // Connect to device
      if (!await device.connect()) throw 'Cannot conenct';

      // Remove current device before setting new
      if (kDebugMode) print(">> Removing previous device");
      if (device != _device) await _device.disconnect();
      await _updateDevice(device); // set active device

      // Listen for incoming data
      device.input?.listen((Pulse data) {
        /// Since all SensorDevices are configured to send 1s periodic pulse
        /// `setState()` equals to `Timer.periodic(Duration(seconds: 1), ...)`.
        setState(() {}); // ensure data is up to date to user
        checkAngleAlert(); // play alert
      });

      // Send data
      await device.begin();
      if (kDebugMode) print(">> Ack sent!");
    } catch (err) {
      if (kDebugMode) print('>> connect: $err');
    }
    _connecting.value = false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: buildNavigationBar(),
      body: SizedBox(
        child: SingleChildScrollView(
          controller: _scrollController,
          child: Column(
            spacing: 12,
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title
              const SizedBox(height: 12),
              const SafeArea(
                top: true,
                child: GradientMask(
                  Text(
                    '.:: $appNameUpper ::.',
                    style: TextStyle(fontSize: 24, letterSpacing: 8),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),

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
                  icon: ValueListenableBuilder(
                    valueListenable: _scrolled,
                    builder:
                        (_, scrolled, _) => Transform.rotate(
                          angle: (scrolled ? 90 : -90).toDouble().toRadian(),
                          child: Icon(Icons.chevron_left),
                        ),
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
                divisions: ((maxThreshold - minThreshold) / 5).toInt(),
                onChanged: _updateThreshold,
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
                onChanged: _updateAlertDelay,
              ),

              // Statistics
              const SizedBox(height: 68),
              const Padding(
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
        content: ValueListenableBuilder(
          valueListenable: _alertsCount,
          builder:
              (_, alertCount, _) => Text(
                '$alertCount',
                style: TextStyle(
                  fontSize: 58,
                  fontWeight: FontWeight.w200,
                  color: primary,
                ),
              ),
        ),
        caption: 'times',
      ),
      StatBox(
        title: 'Active',
        content: Text(
          _device.activeTime,
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
        _scrollToTop();
        await _updateDevice(item);
        await connectToDevice(item);
        setState(() {});
      },
    );
  }

  void openSelectionDialog() async {
    scanDevices(); // parallel
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return ValueListenableBuilder(
          valueListenable: _scanning,
          builder: (_, value, _) {
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
          ValueListenableBuilder(
            valueListenable: _connecting,
            builder:
                (_, connecting, _) => IconButton(
                  icon: Icon(Icons.bluetooth_rounded, size: 22),
                  onPressed:
                      () => connectToDevice(_device), // connect selected device
                  color: connecting ? primary : null,
                ),
          ),
        ],
      ),
    );
  }
}
