import 'package:flutter/material.dart';
import 'package:semistab/utils.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';

class Gauge extends StatefulWidget {
  const Gauge({super.key, required this.angle, required this.threshold});

  final double angle;
  final double threshold;

  @override
  State<Gauge> createState() => _GaugeState();
}

class _GaugeState extends State<Gauge> {
  @override
  Widget build(BuildContext context) {
    final color = getColorByAngle(widget.angle, widget.threshold);
    final start = 0.0;
    final mid = widget.threshold / 2;
    final stop = widget.threshold + mid;
    return SfRadialGauge(
      enableLoadingAnimation: true,
      axes: <RadialAxis>[
        RadialAxis(
          minimum: start,
          maximum: stop,
          radiusFactor: 1, // TODO
          axisLineStyle: AxisLineStyle(thickness: 0),
          labelOffset: 40,
          pointers: <GaugePointer>[
            MarkerPointer(
              value: widget.angle,
              enableAnimation: true,
              color: Colors.white,
              markerOffset: 32,
            ),
          ],
          ranges: <GaugeRange>[
            GaugeRange(
              startValue: 0,
              startWidth: 20,
              endWidth: 20,
              endValue: stop,
              gradient: SweepGradient(
                colors: [
                  Colors.tealAccent,
                  Colors.yellowAccent,
                  Colors.pinkAccent,
                ],
              ),
            ),
          ],
          annotations: <GaugeAnnotation>[
            GaugeAnnotation(
              angle: 90,
              positionFactor: 0.05,
              widget: Padding(
                padding: EdgeInsets.only(left: 28),
                child: Text(
                  '${widget.angle.toStringAsFixed(0)}°',
                  style: TextStyle(
                    fontSize: 92,
                    fontWeight: FontWeight.w100,
                    color: color?.shade100,
                  ),
                ),
              ),
            ),
            GaugeAnnotation(
              angle: 90,
              positionFactor: 1.7,
              widget: Column(
                children: [
                  Text(
                    '${calcPressureOnNeck(widget.angle).toStringAsFixed(1)} Kg',
                    style: TextStyle(fontSize: 22, color: color),
                  ),
                  Text('extra weight on neck!', style: TextStyle(fontSize: 10)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
