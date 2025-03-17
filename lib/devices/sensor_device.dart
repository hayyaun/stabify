import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

class SensorDevice<T> {
  SensorDevice({required this.device, required this.name, this.address});

  final dynamic device;
  final String name;
  final String? address;
  BluetoothConnection? connection;
  DateTime? connectedAt;

  factory SensorDevice.fromBluetoothDevice(BluetoothDevice bt) {
    return SensorDevice(device: bt, name: bt.name ?? 'BT', address: bt.address);
  }

  Future<bool> connect() async {
    if (device is BluetoothDevice) {
      connection = await BluetoothConnection.toAddress(device.address);
      final connected = connection?.isConnected ?? false;
      if (connected) connectedAt = DateTime.now();
      if (connected) _begin();
      return connected;
    }
    return false;
  }

  Future<bool> get isConnected async {
    if (device is BluetoothDevice) {
      return (device as BluetoothDevice).isConnected &&
          (connection?.isConnected ?? false);
    }

    return false;
  }

  Future<bool> _begin() async {
    try {
      if (device is BluetoothDevice && await isConnected) {
        connection!.output.add(Uint8List.fromList("A".codeUnits));
        await connection!.output.allSent;
        return true;
      }
    } catch (err) {
      print('begin $err');
    }
    return false;
  }

  Stream<String>? listen() async* {
    if (device is BluetoothDevice && await isConnected) {
      await for (Uint8List data in connection!.input!) {
        yield String.fromCharCodes(data);
      }
    }
  }

  Future<void> disconnect() async {
    if (device is BluetoothDevice && await isConnected) {
      await connection!.finish();
    }
  }
}
