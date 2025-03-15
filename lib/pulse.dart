import 'dart:math';

import 'package:semistab/vec3.dart';

const alpha = 0.01;
const accelS9y = 16384.0; // 2g
const gyroS9y = 131.0; // 250deg/s

class Pulse {
  Pulse? _previous;
  Vec3 _a, _g;

  Pulse(this._previous, this._a, this._g);

  factory Pulse.fromString(String input, Pulse? previous) {
    var lines = input.split('\n');
    var a = Vec3(0, 0, 0);
    var g = Vec3(0, 0, 0);
    try {
      for (var line in lines) {
        var ln = line.replaceAll(' ', '');
        if (ln.isEmpty) continue;
        if (ln.contains('ax:')) {
          a.x = double.parse(ln.replaceAll('ax:', ''));
        } else if (ln.contains('ay:')) {
          a.y = double.parse(ln.replaceAll('ay:', ''));
        } else if (ln.contains('az:')) {
          a.z = double.parse(ln.replaceAll('az:', ''));
        } else if (ln.contains('gx:')) {
          g.x = double.parse(ln.replaceAll('gx:', ''));
        } else if (ln.contains('gy:')) {
          g.y = double.parse(ln.replaceAll('gy:', ''));
        } else if (ln.contains('gz:')) {
          g.z = double.parse(ln.replaceAll('gz:', ''));
        }
      }
    } catch (err) {
      print('$a $g $err');
    }
    return Pulse(previous, a, g);
  }

  Vec3 get a => _a / accelS9y;
  Vec3 get g => _g / gyroS9y;

  double get accelPitch =>
      atan2(-a.x, sqrt(pow(a.y, 2) + pow(a.z, 2))) * 180 / pi;
  double get accelRoll =>
      atan2(a.y, sqrt(pow(a.x, 2) + pow(a.z, 2))) * 180 / pi;

  double get gyroPitch => (_previous?.pitch ?? 0) + (g.y * 1);
  double get gyroRoll => (_previous?.roll ?? 0) + (g.x * 1);

  double get pitch => alpha * gyroPitch + (1 - alpha) * accelPitch;
  double get roll => alpha * gyroRoll + (1 - alpha) * accelRoll;

  double get angle => max(pitch.abs(), roll.abs());

  @override
  String toString() =>
      'Pulse(pitch: ${pitch.toStringAsFixed(2)}, roll: ${roll.toStringAsFixed(2)})';
}
