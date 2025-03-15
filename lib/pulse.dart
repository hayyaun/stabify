import 'dart:math';

import 'package:semistab/vec3.dart';

const alpha = 0.01;
const accelS9y = 16384.0; // 2g
const gyroS9y = 131.0; // 250deg/s

class Pulse {
  Pulse? _previous, _calib;
  Vec3 _a, _g;

  Pulse({required Vec3 a, required Vec3 g, Pulse? previous, Pulse? calib})
    : _a = a,
      _g = g,
      _previous = previous,
      _calib = calib;

  factory Pulse.fromString(String input, Pulse? previous, Pulse? calib) {
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
    return Pulse(a: a, g: g, previous: previous, calib: calib);
  }

  Vec3 get a => _a / accelS9y;
  Vec3 get g => _g / gyroS9y;

  Vec3 get aRaw => _a;
  Vec3 get gRaw => _g;

  double get accelPitch =>
      atan2(-a.x, sqrt(pow(a.y, 2) + pow(a.z, 2))) * 180 / pi;
  double get accelRoll =>
      atan2(a.y, sqrt(pow(a.x, 2) + pow(a.z, 2))) * 180 / pi;

  double get gyroPitch => (_previous?.pitch ?? 0) + (g.y * 1);
  double get gyroRoll => (_previous?.roll ?? 0) + (g.x * 1);

  double get pitch =>
      alpha * gyroPitch + (1 - alpha) * accelPitch - (_calib?.pitch ?? 0);
  double get roll =>
      alpha * gyroRoll + (1 - alpha) * accelRoll - (_calib?.roll ?? 0);

  double get angle => max(pitch.abs(), roll.abs());

  set a(Vec3 a) => _a = a;
  set g(Vec3 g) => _g = g;

  @override
  String toString() =>
      'Pulse(pitch: ${pitch.toStringAsFixed(2)}, roll: ${roll.toStringAsFixed(2)})';
}
