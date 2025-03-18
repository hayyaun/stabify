import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:stabify/vec3.dart';

const alpha = 0.01;
const accelS9y = 16384.0; // 2g
const gyroS9y = 131.0; // 250deg/s

class Pulse {
  Vec3 a, g;
  DateTime date;
  Pulse? _previous, _delta;

  Pulse({
    required this.a,
    required this.g,
    required this.date,
    Pulse? previous,
    Pulse? delta,
  }) : _previous = previous,
       _delta = delta;

  factory Pulse.zero() {
    return Pulse(a: Vec3.zero(), g: Vec3.zero(), date: DateTime.now());
  }

  factory Pulse.fromString(String input, Pulse? previous, Pulse? delta) {
    final lines = input.split('\n');
    final a = Vec3(0, 0, 0);
    final g = Vec3(0, 0, 0);
    final mappings = {
      'ax': (double value) => a.x = value,
      'ay': (double value) => a.y = value,
      'az': (double value) => a.z = value,
      'gx': (double value) => g.x = value,
      'gy': (double value) => g.y = value,
      'gz': (double value) => g.z = value,
    };

    try {
      for (final line in lines) {
        final ln = line.replaceAll(' ', '');
        if (ln.isEmpty) continue;
        for (final entry in mappings.entries) {
          if (ln.contains(entry.key)) {
            final numPart = ln.replaceAll(entry.key, '').replaceAll(':', '');
            final value = double.tryParse(numPart) ?? 0;
            entry.value(value);
            break;
          }
        }
      }
    } catch (err) {
      if (kDebugMode) print('>> pulse fromString: $a $g $err');
    }
    return Pulse(
      a: a,
      g: g,
      previous: previous,
      delta: delta,
      date: DateTime.now(),
    );
  }

  Vec3 get aNorm => a / accelS9y;
  Vec3 get gNorm => g / gyroS9y;

  double get accelPitch =>
      atan2(-aNorm.x, sqrt(pow(aNorm.y, 2) + pow(aNorm.z, 2))) * 180 / pi;
  double get accelRoll =>
      atan2(aNorm.y, sqrt(pow(aNorm.x, 2) + pow(aNorm.z, 2))) * 180 / pi;

  double get gyroPitch => (_previous?.pitch ?? 0) + (gNorm.y * 1);
  double get gyroRoll => (_previous?.roll ?? 0) + (gNorm.x * 1);

  double get pitch =>
      alpha * gyroPitch + (1 - alpha) * accelPitch - (_delta?.pitch ?? 0);
  double get roll =>
      alpha * gyroRoll + (1 - alpha) * accelRoll - (_delta?.roll ?? 0);

  double get angle => max(pitch.abs(), roll.abs());

  Pulse operator +(Pulse other) =>
      Pulse(a: a + other.a, g: a + other.g, date: other.date);
  Pulse operator -(Pulse other) =>
      Pulse(a: a - other.a, g: a - other.g, date: other.date);
  Pulse operator *(double n) => Pulse(a: a * n, g: a * n, date: date);
  Pulse operator /(double n) => Pulse(a: a / n, g: a / n, date: date);

  Pulse lerp(Pulse other, double t) => this * (1 - t) + other * t;

  @override
  String toString() =>
      'Pulse(pitch: ${pitch.toStringAsFixed(2)}, roll: ${roll.toStringAsFixed(2)})';

  Pulse copyWith({required Pulse? previous, required Pulse? delta}) {
    return Pulse(a: a, g: g, delta: delta, previous: previous, date: date);
  }

  void reset() {
    a.reset();
    g.reset();
    _previous?.reset();
    _delta?.reset();
  }
}

extension PulseMethods on List<Pulse> {
  double get anglesRange {
    final angles = map((p) => p.angle);
    final minValue = angles.reduce((a, b) => a < b ? a : b);
    final maxValue = angles.reduce((a, b) => a > b ? a : b);
    return maxValue - minValue;
  }
}
