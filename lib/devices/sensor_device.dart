import 'dart:async';

import 'package:stabify/pulse.dart';

enum DeviceState { auto, idle, off }

abstract class SensorDevice {
  static const resetRefCountDown = 3;
  static const calibLerpFactor = 0.33;
  static const defaultTelorance = 2.0; // (-1,+1)
  static const idleSeconds = 60;
  static const idleAckPeriod = 10;
  static const keepAliveMaxTry = 30; // 30 * 10 seconds

  SensorDevice({
    required this.name,
    this.telorance = defaultTelorance,
    this.address,
  });

  // state
  DeviceState state = DeviceState.auto;
  int turnOffCDEnabled = 0;
  int keepAliveTries = 0;
  // data
  final List<Pulse> pulses = [];
  // props
  final String name;
  final String? address;
  final double telorance;
  DateTime? _connectedAt;
  // calibrate
  final calib = Pulse.zero();
  int calibCountDown = 0;

  String get activeTime {
    if (_connectedAt == null) return '0\' 0"';
    final diff = DateTime.now().difference(_connectedAt!);
    return '${diff.inHours}\' ${diff.inMinutes - diff.inHours * 60}"';
  }

  // internal
  Pulse? get previous => pulses.lastOrNull;
  bool get isConnected;

  Future<bool> connect() async {
    _connectedAt = DateTime.now();
    return isConnected;
  }

  Future<void> disconnect() async {
    pulses.clear();
    calib.reset();
  }

  // Clib
  void calibrate() {
    if (!isConnected) return;
    calibCountDown = resetRefCountDown;
  }

  void _calibLerp() {
    final pulse = pulses.lastOrNull;
    if (pulse == null) return;
    if (calibCountDown == 0) return;
    if (calibCountDown == resetRefCountDown) {
      calib.a = pulse.a;
      calib.g = pulse.g;
    } else {
      final a = calibLerpFactor;
      calib.a = calib.a.lerp(pulse.a, a);
      calib.g = calib.g.lerp(pulse.g, a);
    }
    calibCountDown -= 1;
  }

  // Data
  Future<bool> begin() async {
    if (!isConnected) return false;
    return true;
  }

  void onPulseTick() {
    // FIXME Replace with a proper tick method later
    // the new devices might not send pulse each second!!!
    _calibLerp();
    checkIdle(); // varies
    checkOffOrWake(); // varies
  }

  Stream<Pulse>? get input async* {}

  // Idle (after 60s telorance) -> Stop
  // This method only changes state of device to IDLE mode (virtually and physically)
  // NOTICE Return value is used by overriding classes to continue check or not
  Future<bool> checkIdle() async {
    if (!isConnected) return false;
    if (state != DeviceState.auto) return false; // only in auto mode
    if (pulses.length < idleSeconds) return false;
    final range = pulses.sublist(pulses.length - idleSeconds).anglesRange;
    if (range > telorance) return false; // moving! not idle
    return true;
  }

  // Ack (periodic 10s) -> Wake (auto) / Off (after 30 periods)
  // This method only changes state of device to AUTO/OFF mode (virtually and physically)
  // NOTICE Return value is used by overriding classes to continue check or not
  Future<bool> checkOffOrWake() async {
    if (state != DeviceState.idle) return false; // only in idle mode
    if (!isConnected) return false;
    return true;
  }
}
