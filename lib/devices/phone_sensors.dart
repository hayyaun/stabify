import 'package:sensors_plus/sensors_plus.dart';

class PhoneSensors {
  PhoneSensors({required this.name, this.isConnected = false});

  final String name;
  final bool isConnected;

  addListeners() {
    accelerometerEventStream(samplingPeriod: Duration(seconds: 1)).listen(
      (AccelerometerEvent event) {
        print(event);
      },
      onError: (error) {},
      cancelOnError: true,
    );

    gyroscopeEventStream(samplingPeriod: Duration(seconds: 1)).listen(
      (GyroscopeEvent event) {
        print(event);
      },
      onError: (error) {},
      cancelOnError: true,
    );
  }
}
