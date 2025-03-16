import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:semistab/blue.dart';
import 'package:semistab/gauge.dart';
import 'package:semistab/pulse.dart';

void main() {
  runApp(const MyApp());
}

const keys = ['ax', 'ay', 'az', 'gx', 'gy', 'gz'];
const minThreshold = 10.0;
const maxThreshold = 60.0;
const defaultThreshold = 15.0;
const calibLerpFactor = 0.33;
const setRefCount = 3;
const defaultAlertDelay = 4; // seconds avg

const headingStyle = TextStyle(fontWeight: FontWeight.bold);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VirtStab',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      darkTheme: ThemeData(colorScheme: ColorScheme.dark(primary: Colors.blue)),
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

  get connected => _device != null && (connection?.isConnected ?? false);

  @override
  void initState() {
    scanAndConnect();
    super.initState();
  }

  @override
  void dispose() async {
    await disconnectDevice();
    super.dispose();
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
      _calib.a = _calib.a * (1 - a) + pulse.a * a;
      _calib.g = _calib.g * (1 - a) + pulse.g * a;
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

  Widget buildTitle() {
    return Text.rich(
      textAlign: TextAlign.center,
      TextSpan(
        style: TextStyle(fontSize: 24, letterSpacing: 8),
        children: [
          TextSpan(
            text: '.: ',
            style: TextStyle(
              color: Colors.white.withAlpha(50),
            ), // Semi-transparent
          ),
          TextSpan(
            text: 'VIRT',
            style: TextStyle(color: Colors.white.withAlpha(80)), // Blue text
          ),
          TextSpan(
            text: 'STAB',
            style: TextStyle(color: Colors.white.withAlpha(180)), // Blue text
          ),
          TextSpan(
            text: ' :.',
            style: TextStyle(
              color: Colors.white.withAlpha(50),
            ), // Semi-transparent
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: BottomAppBar(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 32,
          children: [
            IconButton(
              icon: Icon(
                muted ? Icons.notifications_off : Icons.notifications,
                size: 22,
              ),
              color: muted ? Colors.orangeAccent.shade100 : null,
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
                backgroundColor: WidgetStatePropertyAll(
                  Colors.white.withAlpha(15),
                ),
              ),
              color: Colors.blueAccent.shade100,
              icon: Icon(Icons.adjust, size: 22),
              onPressed: beginCalibrate,
            ),
            IconButton(
              icon: Icon(Icons.search, size: 22),
              onPressed: scanAndConnect,
              color: scanning ? Colors.blueAccent.shade100 : null,
            ),
          ],
        ),
      ),
      body: SizedBox(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              spacing: 12,
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                SafeArea(top: true, child: buildTitle()),
                const SizedBox(height: 12),
                Transform.translate(
                  offset: Offset(0, -250),
                  child: Gauge(
                    angle: _pulses.lastOrNull?.angle ?? 0,
                    threshold: threshold,
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'Threshold: ${(threshold).toStringAsFixed(0)}°',
                    style: headingStyle,
                    textAlign: TextAlign.center,
                  ),
                ),
                Slider(
                  min: minThreshold,
                  max: maxThreshold,
                  value: threshold,
                  padding: EdgeInsets.symmetric(horizontal: 64, vertical: 12),
                  thumbColor: Colors.blueAccent.shade100,
                  activeColor: Colors.blueAccent.shade100.withAlpha(80),
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
                    style: headingStyle,
                    textAlign: TextAlign.center,
                  ),
                ),
                Slider(
                  min: 1,
                  max: 10,
                  value: alertDelay.toDouble(),
                  padding: EdgeInsets.symmetric(horizontal: 64, vertical: 12),
                  thumbColor: Colors.blueAccent.shade100,
                  activeColor: Colors.blueAccent.shade100.withAlpha(80),
                  divisions: 10,
                  onChanged: (v) {
                    alertDelay = v.toInt();
                    setState(() {});
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  _message.isEmpty ? 'Everything is fine!' : _message,
                  textAlign: TextAlign.center,
                ),
                Text(
                  _calibCountDown == 0
                      ? 'Reference at ${_calib.pitch.round()}°, ${_calib.roll.round()}°'
                      : 'Set Reference (${_calibCountDown}s)',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.blueAccent.shade100),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
