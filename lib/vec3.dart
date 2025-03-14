import 'dart:math';

class Vec3 {
  double x, y, z;

  Vec3(this.x, this.y, this.z);

  /// Adds two vectors
  Vec3 operator +(Vec3 other) => Vec3(x + other.x, y + other.y, z + other.z);

  /// Subtracts two vectors
  Vec3 operator -(Vec3 other) => Vec3(x - other.x, y - other.y, z - other.z);

  /// Scalar multiplication
  Vec3 operator *(double scalar) => Vec3(x * scalar, y * scalar, z * scalar);

  /// Scalar division
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

  @override
  String toString() => 'Vec3($x, $y, $z)';
}
