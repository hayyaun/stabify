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
const alertRange = 4; // seconds avg

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
  final player = AudioPlayer();
  final List<BluetoothDevice> _devices = [];
  double threshold = defaultThreshold;
  String _message = '';
  // device
  BluetoothDevice? _device;
  BluetoothConnection? connection;
  String _buffer = '';
  final List<Pulse> _pulses = [];
  // calibrate
  final _calib = Pulse.zero();
  int _calibCountDown = 0;

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

  // Alert

  void checkAngleAlert() async {
    if (_pulses.length < alertRange) return;
    final start = _pulses.length - alertRange;
    final total = _pulses
        .sublist(start)
        .map((p) => p.angle)
        .reduce((a1, a2) => a1 + a2);
    final avgAngle = total / alertRange;
    if (avgAngle < threshold) return;
    await player.play(AssetSource('alert.mp3'));
  }

  // Device

  Future<void> scanAndConnect() async {
    // look for bluetooth devices
    await scanDevices();
    if (_devices.isNotEmpty) {
      await connectToDevice(_devices[0]);
    }
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

  get connected => connection?.isConnected ?? false;

  Widget buildDevices(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        spacing: 6,
        children:
            _devices.map((d) {
              final active = d.address == _device?.address && connected;
              return FilledButton(
                onPressed: () async {
                  if (active) {
                    await disconnectDevice();
                  } else {
                    await connectToDevice(d);
                  }
                },
                style: ButtonStyle(
                  backgroundColor: WidgetStatePropertyAll(
                    active ? Colors.greenAccent : Colors.blueAccent,
                  ),
                  shape: WidgetStateProperty.all(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        8,
                      ), // Adjust roundness
                    ),
                  ),
                  padding: WidgetStatePropertyAll(
                    EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      d.name ?? 'Device',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(d.address, style: TextStyle(fontSize: 8)),
                  ],
                ),
              );
            }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      bottomNavigationBar: BottomAppBar(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 32,
          children: [
            IconButton(
              icon: Icon(Icons.notifications, size: 22),
              onPressed: () {},
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
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            spacing: 12,
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '.: ${widget.title.toUpperCase()} :.',
                style: TextStyle(
                  letterSpacing: 8,
                  fontSize: 24,
                  color: Colors.white.withAlpha(85),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Gauge(
                angle: _pulses.lastOrNull?.angle ?? 0,
                threshold: threshold,
              ),
              const SizedBox(height: 0),
              Text(
                'Threshold: ${(threshold).toStringAsFixed(0)}°',
                style: headingStyle,
                textAlign: TextAlign.center,
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
              if (_message.isNotEmpty)
                Text(_message, textAlign: TextAlign.center),
              if (_calibCountDown > 0)
                Text(
                  'Set Reference (${_calibCountDown}s)',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.blueAccent.shade100),
                ),
              const SizedBox(height: 20),
              // const Text('Devices:', style: headingStyle),
              // Text(_message, style: Theme.of(context).textTheme.bodySmall),
              // buildDevices(context),
              // SizedBox(height: 54),
            ],
          ),
        ),
      ),
    );
  }
}
