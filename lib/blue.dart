import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

Future<bool> checkBluetoothPermission() async {
  // Check if permissions were granted
  if (await Permission.bluetooth.isGranted &&
      await Permission.bluetoothScan.isGranted &&
      await Permission.bluetoothConnect.isGranted) {
    return true;
  }
  return false;
}

Future<bool> requestBluetoothPermissions() async {
  try {
    if (await checkBluetoothPermission()) return true;

    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
  } catch (err) {
    if (kDebugMode) print('>> bluetooth: $err');
  }
  return await checkBluetoothPermission();
}
