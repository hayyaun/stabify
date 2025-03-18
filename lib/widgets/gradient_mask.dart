import 'package:flutter/material.dart';

class GradientMask extends StatelessWidget {
  final Widget child;

  const GradientMask(this.child, {super.key});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (Rect bounds) {
        return const LinearGradient(
          colors: [Colors.black, Colors.white, Colors.black],
          stops: [0.0, 0.5, 1.0],
        ).createShader(bounds);
      },
      child: child,
    );
  }
}
