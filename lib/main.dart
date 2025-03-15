import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:semistab/pulse.dart';
import 'package:semistab/utils.dart';

void main() {
  runApp(const MyApp());
}

const keys = ['ax', 'ay', 'az', 'gx', 'gy', 'gz'];

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

const maxThreshold = 40;

class _MyHomePageState extends State<MyHomePage> {
  BluetoothDevice? _device;
  BluetoothConnection? connection;
  List<Pulse> pulses = [];
  String _message = 'Message';
  String _buffer = '';
  double thresholdFactor = 0.5;
  final player = AudioPlayer();

  @override
  void dispose() async {
    print("Widget Removed"); // Runs when the widget is destroyed
    await disconnectDevice();
    super.dispose();
  }

  void checkAlert(Pulse pulse) async {
    if (pulse.angle < threshold) return;
    print('Alert!!!!');
    await player.play(AssetSource('alert.mp3'));
  }

  void parseOutputToPulses() {
    var boxes = _buffer.split('ax:');
    // ignore last one - maybe it's not complete yet
    for (int i = 0; i < boxes.length - 2; i++) {
      // validate integrity of box
      var box = 'ax:${boxes[i]}';
      var corrupt = false;
      for (var k in keys) {
        if (!box.contains(k)) {
          corrupt = true;
          break;
        }
      }
      if (corrupt) continue; // incomplete, let it append later on
      var previous = pulses.isEmpty ? null : pulses.first;
      var pulse = Pulse.fromString(box, previous);
      pulses.add(pulse); // add pulse
      checkAlert(pulse); // play alert
      _buffer = _buffer.replaceFirst(box, ''); // remove used box
      setState(() {});
    }
  }

  Future<void> requestBluetoothPermissions() async {
    Map<Permission, PermissionStatus> statuses =
        await [
          Permission.bluetooth,
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.location,
        ].request();

    // Check if permissions were granted
    if (statuses[Permission.bluetooth]!.isGranted &&
        statuses[Permission.bluetoothScan]!.isGranted &&
        statuses[Permission.bluetoothConnect]!.isGranted) {
      setState(() {
        _message = "All Bluetooth permissions granted!";
      });
    } else {
      setState(() {
        _message = "Bluetooth permissions denied!";
      });
    }
  }

  Future<void> disconnectDevice() async {
    // Close connection
    connection?.finish();
    connection?.dispose();
    print("Disconnected.");
  }

  void connectToDevice() async {
    try {
      await requestBluetoothPermissions();

      // GPT EXAM
      // Get a list of paired devices
      List<BluetoothDevice> devices =
          await FlutterBluetoothSerial.instance.getBondedDevices();

      // Find HC-05
      for (var device in devices) {
        if (device.name == "HC-05") {
          _device = device;
          break;
        }
      }

      if (_device == null) {
        print("HC-05 not found. Make sure it's paired.");
        return;
      }

      if (connection != null) {
        await disconnectDevice();
        print("Remove previous connection to HC-05");
      }

      // Connect to HC-05
      connection = await BluetoothConnection.toAddress(_device!.address);
      print("Connected to HC-05");

      // Listen for incoming data
      connection!.input?.listen((Uint8List data) {
        var output = String.fromCharCodes(data);
        _buffer += output;
        parseOutputToPulses();
      });

      // Send data
      connection!.output.add(Uint8List.fromList("A".codeUnits));
      await connection!.output.allSent;
      print("Data sent!");
    } catch (err) {
      print('Cannot connect, err occured');
      print(err);
    }
  }

  get threshold => thresholdFactor * maxThreshold;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          widget.title,
          style: TextStyle(
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
            letterSpacing: 2.0,
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Devices:', style: headingStyle),
              const SizedBox(height: 12),
              Text(_message, style: Theme.of(context).textTheme.bodySmall),
              // TODO
              const SizedBox(height: 32),
              Text('Connected: ${_device?.name}', style: headingStyle),
              const SizedBox(height: 12),
              FilledButton(onPressed: () {}, child: Text('Calibrate Device')),
              FilledButton(onPressed: () {}, child: Text('Reset Reference')),
              FilledButton(
                onPressed: disconnectDevice,
                child: Text('Disconnect'),
              ),
              const SizedBox(height: 32),
              Text(
                'Threshold: ${(threshold).toStringAsFixed(0)}°',
                style: headingStyle,
              ),
              const SizedBox(height: 12),
              Slider(
                value: thresholdFactor,
                onChanged: (v) {
                  thresholdFactor = v;
                  setState(() {});
                },
              ),
              const SizedBox(height: 32),
              const Text('Angle:', style: headingStyle),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${pulses.lastOrNull?.angle.round() ?? 0}°',
                    style: TextStyle(
                      color: getColorByAngle(
                        pulses.lastOrNull?.angle ?? 0,
                        threshold,
                      ).withAlpha(120),
                      fontSize: 68,
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(bottom: 14, left: 4),
                    child: Text(
                      '~ ${calcPressureOnNeck(pulses.lastOrNull?.angle ?? 0).round()} Kg',
                      style: TextStyle(
                        color: getColorByAngle(
                          pulses.lastOrNull?.angle ?? 0,
                          threshold,
                        ),
                        fontSize: 24,
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(bottom: 16, left: 8),
                    child: Text('weight on your neck!', style: TextStyle()),
                  ),
                ],
              ),
              // SizedBox(
              //   height: 500, // Set the height you want
              //   child: Text(
              //     _buffer,
              //     style: Theme.of(context).textTheme.bodyMedium,
              //   ),
              // ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: connectToDevice,
        tooltip: 'Scan',
        child: const Icon(Icons.add),
      ),
    );
  }
}
