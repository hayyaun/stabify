import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:virtstab/devices/phone_sensors.dart';
import 'package:virtstab/pulse.dart';

const setRefCount = 3;
const keys = ['ax', 'ay', 'az', 'gx', 'gy', 'gz']; // hc-05
const calibLerpFactor = 0.33;

class SensorDevice {
  SensorDevice({required this.device, required this.name, this.address});

  final dynamic device;
  final String name;
  final String? address;
  BluetoothConnection? connection;
  DateTime? connectedAt;

  // data
  String _buffer = '';
  final List<Pulse> _pulses = [];

  List<Pulse> get pulses => _pulses;

  // calibrate
  final _calib = Pulse.zero();
  int _calibCountDown = 0;

  Pulse get calib => _calib;
  int get calibCountDown => _calibCountDown;

  // previous
  Pulse? get _previous => _pulses.isEmpty ? null : _pulses.first;

  // methods

  factory SensorDevice.fromBluetoothDevice(BluetoothDevice bt) {
    return SensorDevice(device: bt, name: bt.name ?? 'BT', address: bt.address);
  }

  bool get isBT => device is BluetoothDevice;
  bool get isPhone => device is PhoneSensors;

  Future<bool> connect() async {
    if (isBT) {
      connection = await BluetoothConnection.toAddress(device.address);
      final connected = connection?.isConnected ?? false;
      if (connected) connectedAt = DateTime.now();
      return connected;
    }
    if (isPhone) return true;
    return false;
  }

  Future<void> disconnect() async {
    if (isBT && isConnected) {
      await connection!.finish();
    }

    // global
    _pulses.clear();
    _calib.reset();
  }

  bool get isConnected {
    if (isBT) {
      return (device as BluetoothDevice).isConnected &&
          (connection?.isConnected ?? false);
    }
    if (isPhone) return true;
    return false;
  }

  Future<bool> begin() async {
    if (isBT && isConnected) {
      connection!.output.add(Uint8List.fromList("A".codeUnits));
      await connection!.output.allSent;
      return true;
    }
    if (isPhone) return true;
    return false;
  }

  Stream<Pulse>? get input async* {
    if (isBT && isConnected && connection!.input != null) {
      await for (Uint8List data in connection!.input!) {
        final chunk = String.fromCharCodes(data);
        _buffer += chunk;
        final pulses = parseOutputToPulses();
        await for (Pulse pulse in pulses) {
          _pulses.add(pulse);
          _calibLerp();
          yield pulse;
        }
      }
    }
    if (isPhone && isConnected) {
      await for (Pulse pulse in (device as PhoneSensors).pulses) {
        _pulses.add(pulse.copyWith(previous: _previous, delta: _calib));
        _calibLerp(); // calibrate
        yield pulse;
      }
    }
  }

  // Clib
  void calibrate() {
    if (!isConnected) return;
    _calibCountDown = setRefCount;
  }

  void _calibLerp() {
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
  }

  /// HC-05 Custom device
  Stream<Pulse> parseOutputToPulses() async* {
    final boxes = _buffer.split('ax:');
    // ignore last one - maybe it's not complete yet
    for (int i = 0; i < boxes.length - 2; i++) {
      // validate integrity of box
      final box = 'ax:${boxes[i]}';
      final corrupt = keys.any((k) => !box.contains(k));
      if (corrupt) continue; // incomplete, let it append later on
      final pulse = Pulse.fromString(box, _previous, _calib);
      _buffer = _buffer.replaceFirst(box, ''); // remove used box
      yield pulse;
    }
  }
}
