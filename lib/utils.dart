import 'dart:math';

import 'package:flutter/material.dart';

const headWeightKg = 5;

extension DoubleExtensions on double {
  double toRadian() => this * (pi / 180.0);
}

double calcPressureOnNeck(double theta) =>
    headWeightKg * (1 - cos(theta.abs().toRadian()));

MaterialAccentColor? getColorByAngle(double angle, double threshold) {
  if (angle > threshold) return Colors.pinkAccent;
  if (angle > threshold / 2) return Colors.limeAccent;
  return null;
}
