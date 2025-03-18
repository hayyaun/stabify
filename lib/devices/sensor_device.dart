import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:stabify/devices/phone_sensors.dart';
import 'package:stabify/pulse.dart';

const hc05Keys = ['ax', 'ay', 'az', 'gx', 'gy', 'gz']; // hc-05
const resetRefCountDown = 3;
const calibLerpFactor = 0.33;
const defaultTelorance = 2.0; // (-1,+1)
const idleSeconds = 60;
const idleAckPeriod = 10;
const keepAliveMaxTry = 30; // 30 * 10 seconds

enum DeviceType { phone, drcad }

enum DeviceState { auto, idle, off }

class SensorDevice {
  SensorDevice(
    this._device, {
    required this.type,
    required this.name,
    this.telorance = defaultTelorance,
    this.address,
  });

  // props
  final DeviceType type;
  final dynamic _device;
  final String name;
  final String? address;
  final double telorance;
  BluetoothConnection? _connection;
  DateTime? _connectedAt;
  // data
  String _buffer = '';
  final List<Pulse> _pulses = [];
  // calibrate
  final _calib = Pulse.zero();
  int _calibCountDown = 0;
  // state
  DeviceState state = DeviceState.auto;
  int turnOffCDEnabled = 0;
  int keepAliveTries = 0;

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
  bool get isPhone => _device is PhoneSensors && type == DeviceType.phone;
  bool get isDRCAD => _device is BluetoothDevice && type == DeviceType.drcad;

  //internal
  Pulse? get _previous => _pulses.lastOrNull;

  // methods

  factory SensorDevice.fromBluetoothDevice(
    BluetoothDevice device,
    DeviceType type,
  ) {
    return SensorDevice(
      device,
      type: type,
      name: device.name ?? 'BT',
      address: device.address,
    );
  }

  bool get isConnected {
    if (isDRCAD) {
      return (_device as BluetoothDevice).isConnected &&
          (_connection?.isConnected ?? false);
    }
    if (isPhone) return true;
    return false;
  }

  Future<bool> connect() async {
    if (isDRCAD) {
      if (isConnected) await disconnect();
      _connection = await BluetoothConnection.toAddress(_device.address);
    }
    _connectedAt = DateTime.now();
    return isConnected;
  }

  Future<void> disconnect() async {
    if (isDRCAD && isConnected) {
      await _connection!.finish();
    }

    // global
    _pulses.clear();
    _calib.reset();
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

  // Data
  Future<bool> begin() async {
    if (isDRCAD && isConnected) {
      _connection!.output.add(Uint8List.fromList("A".codeUnits));
      await _connection!.output.allSent;
      state = DeviceState.auto; // !!!!!!! AUTO
      return true;
    }
    if (isPhone) return true;
    return false;
  }

  Stream<Pulse>? get input async* {
    if (isDRCAD && isConnected && _connection!.input != null) {
      await for (Uint8List data in _connection!.input!) {
        final chunk = String.fromCharCodes(data);
        _buffer += chunk;
        final pulses = _parseOutputToPulsesDRCAD();
        await for (Pulse pulse in pulses) {
          _pulses.add(pulse);
          _calibLerp();
          _checkIdle();
          _checkOffOrWake();
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

  /// HC-05 Custom device
  Stream<Pulse> _parseOutputToPulsesDRCAD() async* {
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

  // Idle (after 60s telorance) -> Stop
  // This method only changes state of device to IDLE mode (virtually and physically)
  void _checkIdle() async {
    if (state != DeviceState.auto) return; // only in auto mode
    if (_pulses.length < idleSeconds) return;
    final range = _pulses.sublist(_pulses.length - idleSeconds).anglesRange;
    if (range > telorance) return; // moving! not idle

    // turn on idle mode
    if (isDRCAD && isConnected) {
      _connection!.output.add(Uint8List.fromList("S".codeUnits));
      await _connection!.output.allSent;

      state = DeviceState.idle; // !!!!!!! IDLE

      /// Send '1' every 10s
      Timer.periodic(Duration(seconds: idleAckPeriod), (t) async {
        if (state != DeviceState.idle) t.cancel();
        _connection!.output.add(Uint8List.fromList("1".codeUnits));
        await _connection!.output.allSent;
      });

      return;
    }
  }

  // Ack (periodic 10s) -> Wake (auto) / Off (after 30 periods)
  // This method only changes state of device to AUTO/OFF mode (virtually and physically)
  void _checkOffOrWake() async {
    if (state != DeviceState.idle) return; // only in idle mode

    if (isDRCAD && isConnected) {
      /// max-age: if no changes after 30 periods -> OFF
      keepAliveTries++;
      if (keepAliveTries > keepAliveMaxTry) {
        _connection!.output.add(Uint8List.fromList("0".codeUnits));
        await _connection!.output.allSent;
        state = DeviceState.off; // !!!!!!! OFF
        // maybe disconnect?
        keepAliveTries = 0;
        return;
      }

      /// if any change based on telorance -> Wake = AUTO
      if (_pulses.length < keepAliveTries) return;
      final items = _pulses.sublist(
        _pulses.length - keepAliveTries,
      ); // check the ack (idle) pulses only
      final range = items.anglesRange;
      if (range < telorance) return; // not moving! can't wake up
      // Moving! wake up
      await begin();
    }
  }
}
