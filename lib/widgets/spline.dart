import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

const offsetMinY = 5;

class ChartData {
  ChartData(this.x, this.y);
  final int x;
  final double y;
}

class Spline extends StatefulWidget {
  const Spline({
    super.key,
    required this.chartData,
    required this.maximum,
    required this.title,
  });

  final List<ChartData> chartData;
  final double maximum;
  final Widget title;

  @override
  State<Spline> createState() => _SplineState();
}

class _SplineState extends State<Spline> {
  Color get primary => Theme.of(context).colorScheme.primary;
  Color get secondary => Theme.of(context).colorScheme.secondary;
  List<ChartData> get chartData =>
      widget.chartData.map((d) => ChartData(d.x, d.y + offsetMinY)).toList();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SfCartesianChart(
          margin: EdgeInsets.all(0),
          primaryXAxis: NumericAxis(isVisible: false),
          primaryYAxis: NumericAxis(
            isVisible: false,
            minimum: 0,
            maximum: widget.maximum,
          ),
          borderColor: Colors.transparent,
          borderWidth: 0,
          series: <CartesianSeries>[
            SplineAreaSeries<ChartData, int>(
              dataSource: chartData,
              animationDuration: 0,
              borderWidth: 2,
              xValueMapper: (ChartData data, _) => data.x,
              yValueMapper: (ChartData data, _) => data.y,
              gradient: LinearGradient(
                colors: [
                  Color.lerp(Colors.lightGreenAccent, primary, 0.25)!,
                  Color.lerp(Colors.lightGreenAccent, primary, 0.75)!,
                  primary,
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ],
        ),
        Positioned(top: 10, left: 12, child: widget.title),
      ],
    );
  }
}
