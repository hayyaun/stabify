import 'package:flutter/material.dart';
import 'package:virtstab/utils.dart';
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
    return SizedBox(
      width: 350,
      height: 350,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Opacity(
            opacity: 0.18,
            child: Transform.scale(
              scale: 2.1,
              child: ClipOval(
                child: ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    Colors.blueAccent.withAlpha(120),
                    BlendMode.darken,
                  ),
                  child: Image.asset('assets/dial.png'),
                ),
              ),
            ),
          ),
          SfRadialGauge(
            enableLoadingAnimation: true,
            axes: <RadialAxis>[
              RadialAxis(
                minimum: start,
                maximum: stop,
                radiusFactor: 2,
                startAngle: 50,
                endAngle: 180 - 50,
                axisLineStyle: AxisLineStyle(thickness: 0),
                labelOffset: 32 + 32,
                pointers: <GaugePointer>[
                  MarkerPointer(
                    value: widget.angle,
                    enableAnimation: true,
                    color: Colors.white,
                    markerOffset: 32 + 12,
                  ),
                ],
                ranges: <GaugeRange>[
                  GaugeRange(
                    startValue: 0,
                    startWidth: 32,
                    endWidth: 32,
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
                    positionFactor: 0.25,
                    widget: Padding(
                      padding: EdgeInsets.only(left: 42),
                      child: Text(
                        '${widget.angle.toStringAsFixed(0)}°',
                        style: TextStyle(
                          fontSize: 142,
                          fontWeight: FontWeight.w100,
                          color: color?.shade100,
                        ),
                      ),
                    ),
                  ),
                  GaugeAnnotation(
                    angle: 90,
                    positionFactor: 0.6,
                    verticalAlignment: GaugeAlignment.near,
                    widget: Column(
                      children: [
                        Text(
                          '${calcPressureOnNeck(widget.angle).toStringAsFixed(1)} Kg',
                          style: TextStyle(
                            fontSize: 22,
                            color: color?.withAlpha(180),
                          ),
                        ),
                        Text(
                          'extra weight on neck!',
                          style: TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
