# Stabify

Virtual Stablizer for Drcad Devices.

## Sensor Device Behavior

- [x] init connect = ACTIVE
- [x] if epsilon change in 60 last pulses = IDLE
- [x] Periodic 10s check = ACK
- [x] if change = ACTIVE
- [x] after 30 periods = OFF

Drcad Device: ACTIVE `A` / IDLE `S` / ACK `1` / OFF `0`

## ADB WSL Issue Fix

1. Phone: Revoke - Connect USB
1. Windows: taskkill /F /IM adb.exe && adb devices && adb tcpip 5555
1. WSL: adb connect
