import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:stabify/devices/sensor_device.dart';
import 'package:stabify/pulse.dart';

class DrcadDevice extends SensorDevice {
  // TODO we'll use factory name later
  static const deviceName = "HC-05"; // used for detection
  static const _keys = ['ax', 'ay', 'az', 'gx', 'gy', 'gz'];

  DrcadDevice(
    this._device, {
    required super.name,
    super.telorance,
    super.address,
  });

  // props
  BluetoothConnection? _connection;
  BluetoothDevice _device;
  // data
  String _buffer = '';

  // methods

  factory DrcadDevice.fromBluetoothDevice(BluetoothDevice device) {
    return DrcadDevice(
      device,
      name: device.name ?? 'BT',
      address: device.address,
    );
  }

  @override
  bool get isConnected =>
      _device.isConnected && (_connection?.isConnected ?? false);

  @override
  Future<bool> connect() async {
    if (isConnected) await disconnect();
    _connection = await BluetoothConnection.toAddress(_device.address);
    return super.connect();
  }

  @override
  Future<void> disconnect() async {
    if (isConnected) await _connection!.finish();
    super.disconnect();
  }

  // Data
  @override
  Future<bool> begin() async {
    if (!await super.begin()) return false;
    _connection!.output.add(Uint8List.fromList("A".codeUnits));
    await _connection!.output.allSent;
    state = DeviceState.auto; // !!!!!!! AUTO
    return true;
  }

  @override
  Stream<Pulse>? get input async* {
    if (!isConnected || _connection!.input == null) return;
    await for (Uint8List data in _connection!.input!) {
      final chunk = String.fromCharCodes(data);
      _buffer += chunk;
      await for (Pulse pulse in _parseOutputToPulsesDRCAD()) {
        pulses.add(pulse);
        onPulseTick();
        yield pulse;
      }
    }
  }

  Stream<Pulse> _parseOutputToPulsesDRCAD() async* {
    final boxes = _buffer.split('ax:');
    // ignore last one - maybe it's not complete yet
    for (int i = 0; i < boxes.length - 2; i++) {
      // validate integrity of box
      final box = 'ax:${boxes[i]}';
      final corrupt = _keys.any((k) => !box.contains(k));
      if (corrupt) continue; // incomplete, let it append later on
      final pulse = Pulse.fromString(box, previous, calib);
      _buffer = _buffer.replaceFirst(box, ''); // remove used box
      yield pulse;
    }
  }

  @override
  Future<bool> checkIdle() async {
    if (!await super.checkIdle()) return false;
    // turn on idle mode
    _connection!.output.add(Uint8List.fromList("S".codeUnits));
    await _connection!.output.allSent;
    state = DeviceState.idle; // !!!!!!! IDLE
    /// Send '1' every 10s
    Timer.periodic(Duration(seconds: SensorDevice.idleAckPeriod), (t) async {
      if (state != DeviceState.idle) t.cancel();
      _connection!.output.add(Uint8List.fromList("1".codeUnits));
      await _connection!.output.allSent;
    });
    return true;
  }

  // Ack (periodic 10s) -> Wake (auto) / Off (after 30 periods)
  // This method only changes state of _device to AUTO/OFF mode (virtually and physically)
  @override
  Future<bool> checkOffOrWake() async {
    if (!await super.checkOffOrWake()) return false;

    /// max-age: if no changes after 30 periods -> OFF
    keepAliveTries++;
    if (keepAliveTries > SensorDevice.keepAliveMaxTry) {
      _connection!.output.add(Uint8List.fromList("0".codeUnits));
      await _connection!.output.allSent;
      state = DeviceState.off; // !!!!!!! OFF
      // maybe disconnect?
      keepAliveTries = 0;
      return true;
    }

    /// if any change based on telorance -> Wake = AUTO
    if (pulses.length < keepAliveTries) return false;
    final items = pulses.sublist(
      pulses.length - keepAliveTries,
    ); // check the ack (idle) pulses only
    final range = items.anglesRange;
    if (range < telorance) return false; // not moving! can't wake up
    // Moving! wake up
    await begin();
    return true;
  }
}
