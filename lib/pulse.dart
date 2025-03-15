import 'dart:math';

import 'package:semistab/vec3.dart';

const alpha = 0.01;
const accelS9y = 16384.0; // 2g
const gyroS9y = 131.0; // 250deg/s

class Pulse {
  Pulse? _previous, _delta;
  Vec3 a, g;

  Pulse({required this.a, required this.g, Pulse? previous, Pulse? delta})
    : _previous = previous,
      _delta = delta;

  factory Pulse.fromString(String input, Pulse? previous, Pulse? delta) {
    var lines = input.split('\n');
    var a = Vec3(0, 0, 0);
    var g = Vec3(0, 0, 0);
    try {
      for (var line in lines) {
        var ln = line.replaceAll(' ', '');
        if (ln.isEmpty) continue;

        if (ln.contains('ax')) {
          a.x =
              double.tryParse(ln.replaceAll(':', '').replaceAll('ax', '')) ?? 0;
        } else if (ln.contains('ay')) {
          a.y =
              double.tryParse(ln.replaceAll(':', '').replaceAll('ay', '')) ?? 0;
        } else if (ln.contains('az')) {
          a.z =
              double.tryParse(ln.replaceAll(':', '').replaceAll('az', '')) ?? 0;
        } else if (ln.contains('gx')) {
          g.x =
              double.tryParse(ln.replaceAll(':', '').replaceAll('gx', '')) ?? 0;
        } else if (ln.contains('gy')) {
          g.y =
              double.tryParse(ln.replaceAll(':', '').replaceAll('gy', '')) ?? 0;
        } else if (ln.contains('gz')) {
          g.z =
              double.tryParse(ln.replaceAll(':', '').replaceAll('gz', '')) ?? 0;
        }
      }
    } catch (err) {
      print('$a $g $err');
    }
    return Pulse(a: a, g: g, previous: previous, delta: delta);
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

  Pulse operator +(Pulse other) => Pulse(a: a + other.a, g: a + other.g);
  Pulse operator *(double n) => Pulse(a: a * n, g: a * n);

  @override
  String toString() =>
      'Pulse(pitch: ${pitch.toStringAsFixed(2)}, roll: ${roll.toStringAsFixed(2)})';
}
