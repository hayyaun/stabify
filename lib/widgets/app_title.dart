import 'package:flutter/material.dart';

class AppTitle extends StatelessWidget {
  const AppTitle({super.key});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final secondary = Theme.of(context).colorScheme.secondary;
    return Text.rich(
      textAlign: TextAlign.center,
      TextSpan(
        style: TextStyle(fontSize: 24, letterSpacing: 8),
        children: [
          TextSpan(
            text: '.:: ',
            style: TextStyle(
              color: secondary.withAlpha(30),
            ), // Semi-transparent
          ),
          TextSpan(
            text: 'VIRT',
            style: TextStyle(color: secondary.withAlpha(50)), // Blue text
          ),
          TextSpan(
            text: 'STAB',
            style: TextStyle(color: onSurface.withAlpha(140)), // Blue text
          ),
          TextSpan(
            text: ' ::.',
            style: TextStyle(
              color: secondary.withAlpha(30),
            ), // Semi-transparent
          ),
        ],
      ),
    );
  }
}
