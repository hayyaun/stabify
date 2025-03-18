import 'package:async/async.dart';
import 'package:rxdart/rxdart.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:stabify/pulse.dart';
import 'package:stabify/vec3.dart';

class PhoneSensors {
  PhoneSensors();

  Stream<Pulse> get pulses {
    final gyroStream = gyroscopeEventStream(
      samplingPeriod: Duration(milliseconds: 100),
    );
    final accelStream = accelerometerEventStream(
      samplingPeriod: Duration(milliseconds: 100),
    );

    return StreamZip([accelStream, gyroStream])
        .map((events) {
          final a = events[0] as AccelerometerEvent;
          final g = events[1] as GyroscopeEvent;
          return Pulse(a: Vec3(a.x, a.y, a.z), g: Vec3(g.x, g.y, g.z));
        })
        .throttleTime(Duration(seconds: 1));
  }
}
