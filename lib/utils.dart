import 'dart:math';

const headWeightKg = 50;

double calcPressureOnNeck(double theta) =>
    headWeightKg * (1 - cos(theta.abs() * pi / 180));
