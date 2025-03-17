import 'package:async/async.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:virtstab/pulse.dart';
import 'package:virtstab/vec3.dart';

class PhoneSensors {
  PhoneSensors();

  Stream<Pulse> get pulses {
    final gyroStream = gyroscopeEventStream(
      samplingPeriod: Duration(seconds: 1),
    );
    final accelStream = accelerometerEventStream(
      samplingPeriod: Duration(seconds: 1),
    );

    return StreamZip([accelStream, gyroStream]).map((events) {
      final a = events[0] as AccelerometerEvent;
      final g = events[1] as GyroscopeEvent;
      return Pulse(a: Vec3(a.x, a.y, a.z), g: Vec3(g.x, g.y, g.z));
    });
  }
}
