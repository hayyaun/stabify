import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:semistab/pulse.dart';

void main() {
  runApp(const MyApp());
}

const keys = ['ax', 'ay', 'az', 'gx', 'gy', 'gz'];

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
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
  BluetoothDevice? hc05;
  BluetoothConnection? connection;
  List<Pulse> pulses = [];
  String _message = 'Message';
  String _buffer = '';

  @override
  void dispose() async {
    print("Widget Removed"); // Runs when the widget is destroyed
    await disconnectHC05();
    super.dispose();
  }

  void parsePulses() {
    var boxes = _buffer.split('\n\n');
    for (var box in boxes) {
      // validate integrity of box
      var corrupt = false;
      for (var k in keys) {
        if (!box.contains(k)) {
          corrupt = true;
          break;
        }
      }
      if (corrupt) continue; // incomplete, let it append later on
      var previous = pulses.isEmpty ? null : pulses.first;
      pulses.add(Pulse.fromString(box, previous)); // add pulse
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

  Future<void> disconnectHC05() async {
    // Close connection
    connection?.finish();
    connection?.dispose();
    print("Disconnected.");
  }

  void connectToHC05() async {
    try {
      await requestBluetoothPermissions();

      // GPT EXAM
      // Get a list of paired devices
      List<BluetoothDevice> devices =
          await FlutterBluetoothSerial.instance.getBondedDevices();

      // Find HC-05
      for (var device in devices) {
        if (device.name == "HC-05") {
          hc05 = device;
          break;
        }
      }

      if (hc05 == null) {
        print("HC-05 not found. Make sure it's paired.");
        return;
      }

      if (connection != null) {
        await disconnectHC05();
        print("Remove previous connection to HC-05");
      }

      // Connect to HC-05
      connection = await BluetoothConnection.toAddress(hc05!.address);
      print("Connected to HC-05");

      // Listen for incoming data
      connection!.input?.listen((Uint8List data) {
        var output = String.fromCharCodes(data);
        print("Received: ${output}");
        _buffer += output;
        parsePulses();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text('Devices:'),
            Text(
              pulses.isNotEmpty ? pulses.last.toString() : '',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            Text(_buffer, style: Theme.of(context).textTheme.bodyMedium),
            Text(_message, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: connectToHC05,
        tooltip: 'Scan',
        child: const Icon(Icons.add),
      ),
    );
  }
}
