import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:virtstab/devices/phone_sensors.dart';
import 'package:virtstab/pulse.dart';

const hc05Keys = ['ax', 'ay', 'az', 'gx', 'gy', 'gz']; // hc-05
const resetRefCountDown = 3;
const calibLerpFactor = 0.33;

class SensorDevice {
  SensorDevice({required device, required this.name, this.address})
    : _device = device;

  // props
  final dynamic _device;
  final String name;
  final String? address;
  BluetoothConnection? _connection;
  DateTime? _connectedAt;
  // data
  String _buffer = '';
  final List<Pulse> _pulses = [];
  // calibrate
  final _calib = Pulse.zero();
  int _calibCountDown = 0;

  // expose
  List<Pulse> get pulses => _pulses;
  Pulse get calib => _calib;
  int get calibCountDown => _calibCountDown;

  String get activeTime {
    if (_connectedAt == null) return '0\' 0"';
    final diff = DateTime.now().difference(_connectedAt!);
    return '${diff.inHours}\' ${diff.inMinutes - diff.inHours * 60}"';
  }

  // is
  bool get isBT => _device is BluetoothDevice;
  bool get isPhone => _device is PhoneSensors;

  //internal
  Pulse? get _previous => _pulses.lastOrNull;

  // methods

  factory SensorDevice.fromBluetoothDevice(BluetoothDevice bt) {
    return SensorDevice(device: bt, name: bt.name ?? 'BT', address: bt.address);
  }

  bool get isConnected {
    if (isBT) {
      return (_device as BluetoothDevice).isConnected &&
          (_connection?.isConnected ?? false);
    }
    if (isPhone) return true;
    return false;
  }

  Future<bool> connect() async {
    if (isBT) {
      if (isConnected) await disconnect();
      _connection = await BluetoothConnection.toAddress(_device.address);
    }
    _connectedAt = DateTime.now();
    return isConnected;
  }

  Future<void> disconnect() async {
    if (isBT && isConnected) {
      await _connection!.finish();
    }

    // global
    _pulses.clear();
    _calib.reset();
  }

  Future<bool> begin() async {
    if (isBT && isConnected) {
      _connection!.output.add(Uint8List.fromList("A".codeUnits));
      await _connection!.output.allSent;
      return true;
    }
    if (isPhone) return true;
    return false;
  }

  Stream<Pulse>? get input async* {
    if (isBT && isConnected && _connection!.input != null) {
      await for (Uint8List data in _connection!.input!) {
        final chunk = String.fromCharCodes(data);
        _buffer += chunk;
        final pulses = __parseHC05OutputToPulses();
        await for (Pulse pulse in pulses) {
          _pulses.add(pulse);
          _calibLerp();
          yield pulse;
        }
      }
    }
    if (isPhone && isConnected) {
      await for (Pulse pulse in (_device as PhoneSensors).pulses) {
        _pulses.add(pulse.copyWith(previous: _previous, delta: _calib));
        _calibLerp(); // calibrate
        yield pulse;
      }
    }
  }

  // Clib
  void calibrate() {
    if (!isConnected) return;
    _calibCountDown = resetRefCountDown;
  }

  void _calibLerp() {
    final pulse = _pulses.lastOrNull;
    if (pulse == null) return;
    if (_calibCountDown == 0) return;
    if (_calibCountDown == resetRefCountDown) {
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
  Stream<Pulse> __parseHC05OutputToPulses() async* {
    final boxes = _buffer.split('ax:');
    // ignore last one - maybe it's not complete yet
    for (int i = 0; i < boxes.length - 2; i++) {
      // validate integrity of box
      final box = 'ax:${boxes[i]}';
      final corrupt = hc05Keys.any((k) => !box.contains(k));
      if (corrupt) continue; // incomplete, let it append later on
      final pulse = Pulse.fromString(box, _previous, _calib);
      _buffer = _buffer.replaceFirst(box, ''); // remove used box
      yield pulse;
    }
  }
}
