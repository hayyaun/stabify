# Stabify

Virtual Stablizer for DrCAD Devices.

## Sensor Device Behavior

- [x] init connect = ACTIVE
  - [x] ACTIVE: if `60 last pulses avg` change < epsilon = IDLE
- [x] IDLE: Periodic 10s check = ACK
  - [x] if `30 last pulses avg` change > epsilon = ACTIVE
  - [x] if `30+ pulses` received without waking up = OFF

> **DrCAD Device:** ACTIVE `A` / IDLE `S` / ACK `1` / OFF `0`

## ADB WSL Issue Fix

1. Phone: Revoke - Connect USB
1. Windows: taskkill /F /IM adb.exe && adb devices && adb tcpip 5555
1. WSL: adb connect
