# Stabify

A new Flutter project.

## Sensor Device Behavior

- [x] init connect = ACTIVE -> Send "A"
- [x] if epsilon change in 60 last pulses = IDLE -> Send "S"
- [x] Periodic 10s check = ACK -> Send "1"
- [x] if change = ACTIVE -> Send "A"
- [x] after 30 periods = OFF -> Send "0"

## ADB WSL Issue Fix

1. Phone: Revoke - Connect USB
1. Windows: taskkill /F /IM adb.exe && adb devices && adb tcpip 5555
1. WSL: adb connect
