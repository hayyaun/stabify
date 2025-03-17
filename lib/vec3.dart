import 'dart:math';

class Vec3 {
  double x, y, z;

  Vec3(this.x, this.y, this.z);

  Vec3 operator +(Vec3 other) => Vec3(x + other.x, y + other.y, z + other.z);
  Vec3 operator -(Vec3 other) => Vec3(x - other.x, y - other.y, z - other.z);
  Vec3 operator *(double scalar) => Vec3(x * scalar, y * scalar, z * scalar);
  Vec3 operator /(double scalar) => Vec3(x / scalar, y / scalar, z / scalar);

  /// Dot product
  double dot(Vec3 other) => x * other.x + y * other.y + z * other.z;

  /// Cross product
  Vec3 cross(Vec3 other) => Vec3(
    y * other.z - z * other.y,
    z * other.x - x * other.z,
    x * other.y - y * other.x,
  );

  /// Magnitude of the vector
  double magnitude() => sqrt(x * x + y * y + z * z);

  /// Normalizes the vector
  Vec3 normalize() {
    double mag = magnitude();
    return mag == 0 ? Vec3(0, 0, 0) : this / mag;
  }

  Vec3 lerp(Vec3 other, double t) => this * (1 - t) + other * t;

  factory Vec3.zero() => Vec3(0, 0, 0);

  @override
  String toString() =>
      'Vec3(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)}, ${z.toStringAsFixed(3)})';

  void reset() {
    x = y = z = 0;
  }
}
