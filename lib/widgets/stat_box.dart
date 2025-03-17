import 'package:flutter/material.dart';
import 'package:virtstab/styles.dart';

class StatBox extends StatelessWidget {
  final String title;
  final Widget content;
  final String caption;

  const StatBox({
    super.key,
    required this.title,
    required this.content,
    required this.caption,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: textStyleBold),
              const Spacer(),
              content,
              const Spacer(flex: 2),
            ],
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Text(
              caption.toUpperCase(),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withAlpha(120),
                letterSpacing: 2,
                fontSize: 12,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
