import 'package:async/async.dart';
import 'package:rxdart/rxdart.dart';
import 'package:sensors_plus/sensors_plus.dart' as sensor;
import 'package:stabify/devices/sensor_device.dart';
import 'package:stabify/pulse.dart';
import 'package:stabify/vec3.dart';

class PhoneSensors extends SensorDevice {
  PhoneSensors({required super.name, super.telorance});

  @override
  bool get isConnected => true;

  Stream<Pulse> get inputRaw {
    final gyroStream = sensor.gyroscopeEventStream(
      samplingPeriod: Duration(milliseconds: 100),
    );
    final accelStream = sensor.accelerometerEventStream(
      samplingPeriod: Duration(milliseconds: 100),
    );

    return StreamZip([accelStream, gyroStream])
        .map((events) {
          final a = events[0] as sensor.AccelerometerEvent;
          final g = events[1] as sensor.GyroscopeEvent;
          return Pulse(
            a: Vec3(a.x, a.y, a.z),
            g: Vec3(g.x, g.y, g.z),
            date: DateTime.now(),
          );
        })
        .throttleTime(Duration(seconds: 1));
  }

  @override
  Stream<Pulse>? get input async* {
    if (!isConnected) return;
    await for (Pulse pulse in inputRaw) {
      pulses.add(pulse.copyWith(previous: previous, delta: calib));
      onPulseTick();
      yield pulse;
    }
  }

  @override
  Future<bool> checkIdle() async {
    return false; // ignore excessive checks
  }

  @override
  Future<bool> checkOffOrWake() async {
    return false; // ignore excessive checks
  }
}
