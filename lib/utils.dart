import 'dart:math';

import 'package:flutter/material.dart';

const headWeightKg = 5;

double calcPressureOnNeck(double theta) =>
    headWeightKg * (1 - cos(theta.abs() * pi / 180));

Color getColorByAngle(double angle, double threshold) {
  if (angle > threshold) return Colors.redAccent;
  if (angle > threshold / 2) return Colors.orangeAccent;
  return Colors.white;
}
