import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:semistab/vec3.dart';

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
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  BluetoothConnection? connection;
  String _message = 'Message';
  String _output = '';
  List<Vec3> aList = [];
  List<Vec3> gList = [];

  @override
  void dispose() {
    print("Widget Removed"); // Runs when the widget is destroyed
    disconnectHC05();
    super.dispose();
  }

  void appendVectors(String input) {
    var lines = input.split('\n');
    var a = Vec3(0, 0, 0);
    var g = Vec3(0, 0, 0);
    for (var line in lines) {
      var lineTrim = line.replaceAll(' ', '');
      if (lineTrim.isEmpty) continue;
      if (lineTrim.contains('ax:')) {
        a.x = double.parse(lineTrim.replaceAll('ax:', ''));
      } else if (lineTrim.contains('ay:')) {
        a.y = double.parse(lineTrim.replaceAll('ay:', ''));
      } else if (lineTrim.contains('az:')) {
        a.z = double.parse(lineTrim.replaceAll('az:', ''));
      } else if (lineTrim.contains('gx:')) {
        g.x = double.parse(lineTrim.replaceAll('gx:', ''));
      } else if (lineTrim.contains('gy:')) {
        g.y = double.parse(lineTrim.replaceAll('gy:', ''));
      } else if (lineTrim.contains('gz:')) {
        g.z = double.parse(lineTrim.replaceAll('gz:', ''));
      }
    }
    aList.add(a);
    gList.add(g);
    setState(() {});
  }

  void toVec() {
    var boxes = _output.split('\n\n');
    for (var box in boxes) {
      var corrupt = false;
      for (var k in keys) {
        if (!box.contains(k)) {
          corrupt = true;
          break;
        }
      }
      if (corrupt) continue;
      appendVectors(box);
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

  void disconnectHC05() async {
    // TODO add a button for manual disconnect
    // Close connection
    await Future.delayed(Duration(seconds: 25));
    connection?.finish();
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
      BluetoothDevice? hc05;
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

      // Connect to HC-05
      connection = await BluetoothConnection.toAddress(hc05.address);
      print("Connected to HC-05");

      // Listen for incoming data
      connection!.input?.listen((Uint8List data) {
        var output = String.fromCharCodes(data);
        print("Received: ${output}");
        _output += output;
        toVec();
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
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          //
          // TRY THIS: Invoke "debug painting" (choose the "Toggle Debug Paint"
          // action in the IDE, or press "p" in the console), to see the
          // wireframe for each widget.
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text('Devices:'),
            Text(
              gList.isNotEmpty ? gList.last.toString() : '',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            Text(_message, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: connectToHC05,
        tooltip: 'Scan',
        child: const Icon(Icons.add),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
