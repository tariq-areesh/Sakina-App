// healthDashboardPage.dart
import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class HealthDashboardPage extends StatefulWidget {
  final bool isDeviceConnected;
  final String latestBleMessage;
  final int bleSequence;

  const HealthDashboardPage({
    super.key,
    required this.isDeviceConnected,
    required this.latestBleMessage,
    required this.bleSequence,
  });

  @override
  State<HealthDashboardPage> createState() => _HealthDashboardPageState();
}

class _HealthDashboardPageState extends State<HealthDashboardPage> {
  static const double stepX = 0.5;
  static const double visibleWindow = 11.5;

  Timer? _timer;

  List<FlSpot> _bvpSpots = [];
  List<FlSpot> _tempSpots = [];

  double _currentX = 0.0;

  double? _latestBvp;
  double? _latestTemp;
  DateTime? _lastBleUpdateAt;

  @override
  void initState() {
    super.initState();
    _consumeIncomingBleIfNeeded();
    _startTimeline();
  }

  @override
  void didUpdateWidget(covariant HealthDashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.bleSequence != widget.bleSequence ||
        oldWidget.isDeviceConnected != widget.isDeviceConnected ||
        oldWidget.latestBleMessage != widget.latestBleMessage) {
      _consumeIncomingBleIfNeeded();
    }
  }

  void _consumeIncomingBleIfNeeded() {
    if (!widget.isDeviceConnected || widget.latestBleMessage.trim().isEmpty) {
      _latestBvp = null;
      _latestTemp = null;
      _lastBleUpdateAt = null;
      return;
    }

    try {
      final parts = widget.latestBleMessage.split(',');
      final Map<String, String> data = {};

      for (final part in parts) {
        final kv = part.split(':');
        if (kv.length >= 2) {
          final key = kv.first.trim().toLowerCase();
          final value = kv.sublist(1).join(':').trim();
          data[key] = value;
        }
      }

      if (data.containsKey('bvp')) {
        _latestBvp = double.tryParse(data['bvp']!);
      }

      if (data.containsKey('temp')) {
        _latestTemp = double.tryParse(data['temp']!);
      }

      _lastBleUpdateAt = DateTime.now();
    } catch (_) {
      _latestBvp = null;
      _latestTemp = null;
      _lastBleUpdateAt = null;
    }
  }

  void _startTimeline() {
    _timer?.cancel();

    _timer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      if (!mounted) return;

      setState(() {
        _currentX += stepX;

        final hasFreshBleData =
            widget.isDeviceConnected &&
            _lastBleUpdateAt != null &&
            DateTime.now().difference(_lastBleUpdateAt!) <
                const Duration(seconds: 3);

        if (hasFreshBleData) {
          if (_latestBvp != null) {
            _bvpSpots.add(FlSpot(_currentX, _latestBvp!.clamp(0.2, 0.9)));
          }
          if (_latestTemp != null) {
            _tempSpots.add(FlSpot(_currentX, _latestTemp!.clamp(34.0, 37.5)));
          }
        }

        final minVisibleX = (_currentX - visibleWindow).clamp(0.0, _currentX);

        _bvpSpots = _bvpSpots.where((spot) => spot.x >= minVisibleX).toList();
        _tempSpots = _tempSpots.where((spot) => spot.x >= minVisibleX).toList();
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final minX = (_currentX - visibleWindow).clamp(0.0, _currentX);
    final maxX = _currentX < visibleWindow ? visibleWindow : _currentX;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isSmall = width < 360;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            isSmall ? 10 : 12,
            10,
            isSmall ? 10 : 12,
            16,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 20),
            child: Column(
              children: [
                const SizedBox(height: 4),
                Text(
                  "Dashboard",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isSmall ? 19 : 21,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),

                SizedBox(
                  height: isSmall ? 250 : 290,
                  child: _DashboardCard(
                    title: "Blood Volume Pulse (BVP)",
                    child: _RealtimeLineChart(
                      spots: _bvpSpots,
                      minX: minX,
                      maxX: maxX,
                      minY: 0.2,
                      maxY: 0.9,
                      leftTitle: "Raw",
                      bottomTitle: "Time (s)",
                      yLabelBuilder: (value) => value.toStringAsFixed(1),
                      lineColor: const Color(0xFF7B3A1E),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                SizedBox(
                  height: isSmall ? 250 : 290,
                  child: _DashboardCard(
                    title: "Body Temperature",
                    child: _RealtimeLineChart(
                      spots: _tempSpots,
                      minX: minX,
                      maxX: maxX,
                      minY: 34.0,
                      maxY: 37.0,
                      leftTitle: "C°",
                      bottomTitle: "Time (s)",
                      yLabelBuilder: (value) {
                        if (value % 1 == 0) return value.toInt().toString();
                        return value.toStringAsFixed(1);
                      },
                      lineColor: const Color(0xFFA85530),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DashboardCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _DashboardCard({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isSmall = MediaQuery.of(context).size.width < 360;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        isSmall ? 10 : 12,
        isSmall ? 8 : 10,
        isSmall ? 10 : 12,
        isSmall ? 10 : 12,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF4A1A08), width: 1.5),
      ),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: isSmall ? 15 : 17,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _RealtimeLineChart extends StatelessWidget {
  final List<FlSpot> spots;
  final double minX;
  final double maxX;
  final double minY;
  final double maxY;
  final String leftTitle;
  final String bottomTitle;
  final String Function(double value) yLabelBuilder;
  final Color lineColor;

  const _RealtimeLineChart({
    required this.spots,
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    required this.leftTitle,
    required this.bottomTitle,
    required this.yLabelBuilder,
    required this.lineColor,
  });

  @override
  Widget build(BuildContext context) {
    final isSmall = MediaQuery.of(context).size.width < 360;

    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: isSmall ? 20 : 24,
                child: Center(
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: Text(
                      leftTitle,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isSmall ? 10 : 12,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: LineChart(
                  LineChartData(
                    minX: minX,
                    maxX: maxX,
                    minY: minY,
                    maxY: maxY,
                    backgroundColor: Colors.transparent,
                    clipData: const FlClipData.all(),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: true,
                      horizontalInterval: (maxY - minY) / 5,
                      verticalInterval: 1,
                      getDrawingHorizontalLine: (_) => FlLine(
                        color: Colors.white.withOpacity(0.18),
                        strokeWidth: 1,
                      ),
                      getDrawingVerticalLine: (_) => FlLine(
                        color: Colors.white.withOpacity(0.18),
                        strokeWidth: 1,
                      ),
                    ),
                    borderData: FlBorderData(
                      show: true,
                      border: Border.all(
                        color: Colors.white.withOpacity(0.30),
                        width: 1,
                      ),
                    ),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: isSmall ? 24 : 30,
                          interval: (maxY - minY) / 5,
                          getTitlesWidget: (value, meta) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Text(
                                yLabelBuilder(value),
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.75),
                                  fontSize: isSmall ? 8 : 9,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: isSmall ? 18 : 22,
                          interval: 1,
                          getTitlesWidget: (value, meta) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                value.toInt().toString(),
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.75),
                                  fontSize: isSmall ? 8 : 9,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: true,
                        curveSmoothness: 0.22,
                        color: lineColor,
                        barWidth: isSmall ? 2 : 2.2,
                        isStrokeCapRound: true,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          color: lineColor.withOpacity(0.08),
                        ),
                      ),
                    ],
                    lineTouchData: const LineTouchData(enabled: false),
                  ),
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeInOut,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          bottomTitle,
          style: TextStyle(
            color: Colors.white,
            fontSize: isSmall ? 10 : 12,
          ),
        ),
      ],
    );
  }
}