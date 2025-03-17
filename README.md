# semistab

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

- init connect = ACTIVE -> Send "A"
- if epsilon change in 60 last pulses = IDLE -> Send "S"
- Periodic 10s check = ACK -> Send "1"
- if change = ACTIVE -> Send "A"
- after 30 periods = OFF -> Send "0"
