import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

const _securityGraphCounts = <int>[24, 18, 32, 28, 36, 22, 14]; // 추후 백엔드 반영
const _weekdaySymbolsKo = ['월', '화', '수', '목', '금', '토', '일'];

class SecurityGraphCard extends StatefulWidget {
  const SecurityGraphCard({
    super.key,
    required this.name,
    required this.alertCount,
    required this.onlineDevices,
  });

  final String name;
  final int alertCount;
  final int onlineDevices;

  @override
  State<SecurityGraphCard> createState() => _SecurityGraphCardState();
}

class _SecurityGraphCardState extends State<SecurityGraphCard> {
  int? _hoveredIndex;
  double? _hoverDx;
  double? _graphWidth;
  _WeekContext? _cachedWeekContext;

  _WeekContext get _weekContext =>
      _cachedWeekContext ??= _WeekContext.fromDate(DateTime.now());

  void _updateGraphWidth(double width) {
    _graphWidth = width;
  }

  void _updateHover(double dx, double width) {
    final step = width / (_securityGraphCounts.length - 1);
    final index = (dx / step).round().clamp(0, _securityGraphCounts.length - 1);

    setState(() {
      _hoveredIndex = index;
      _hoverDx = dx.clamp(0, width);
    });
  }

  void _clearHover() {
    if (_hoveredIndex != null || _hoverDx != null) {
      setState(() {
        _hoveredIndex = null;
        _hoverDx = null;
      });
    }
  }

  void _jumpToDay(int index) {
    final width = _graphWidth;
    if (width == null || _securityGraphCounts.isEmpty) return;

    if (_hoveredIndex == index) {
      _clearHover();
      return;
    }

    final step = width / (_securityGraphCounts.length - 1);
    final dx = step * index;
    _updateHover(dx, width);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final points = _securityGraphCounts;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF0B1224)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: SafeOnColors.accent,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: SafeOnColors.accent.withOpacity(0.5),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Live security pulse',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                'Hello, ${widget.name}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white70,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '${_weekContext.month}월 ${_weekContext.weekOfMonth}주차',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '이번주 안전 탐지 현황',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white70,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 190,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final graphWidth = constraints.maxWidth;
                _updateGraphWidth(graphWidth);

                return MouseRegion(
                  onHover: (event) => _updateHover(event.localPosition.dx, graphWidth),
                  onExit: (_) => _clearHover(),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) => _updateHover(details.localPosition.dx, graphWidth),
                    onPanUpdate: (details) => _updateHover(details.localPosition.dx, graphWidth),
                    onPanEnd: (_) => _clearHover(),
                    child: Stack(
                      children: [
                        CustomPaint(
                          painter: _SecurityLinePainter(
                            points: points.map((point) => point.toDouble()).toList(),
                            strokeColor: SafeOnColors.primary,
                            fillColor: SafeOnColors.primary.withOpacity(0.24),
                            highlightIndex: _hoveredIndex,
                          ),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                            alignment: Alignment.bottomLeft,
                            child: Text(
                              'SafeOn Detection Count',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: Colors.white70,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                        if (_hoveredIndex != null && _hoverDx != null)
                          Positioned(
                            left: (_hoverDx! - 48)
                                .clamp(0, graphWidth > 96 ? graphWidth - 96 : 0),
                            top: 12,
                            child: _GraphTooltip(
                              label:
                                  '${_weekContext.dayLabels[_hoveredIndex!]} • ${points[_hoveredIndex!]}',
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          _WeekLegend(
            labels: _weekContext.dayLabels,
            counts: points,
            highlightIndex: _hoveredIndex,
            onTapDay: _jumpToDay,
          ),
          const SizedBox(height: 14),
          Column(
            children: [
              _GraphStat(
                label: 'Active devices',
                value: '${widget.onlineDevices}',
                chipColor: SafeOnColors.success,
              ),
              const SizedBox(height: 8),
              _GraphStat(
                label: 'Alerts today',
                value: '${widget.alertCount}',
                chipColor: SafeOnColors.accent,
              ),
              const SizedBox(height: 8),
              _GraphStat(
                label: 'Feed status',
                value: 'Simulated',
                chipColor: colorScheme.secondary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GraphStat extends StatelessWidget {
  const _GraphStat({
    required this.label,
    required this.value,
    required this.chipColor,
  });

  final String label;
  final String value;
  final Color chipColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: chipColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: Colors.white70,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _GraphTooltip extends StatelessWidget {
  const _GraphTooltip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.96),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(color: SafeOnColors.primary.withOpacity(0.25)),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: SafeOnColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _WeekLegend extends StatelessWidget {
  const _WeekLegend({
    required this.labels,
    required this.counts,
    required this.highlightIndex,
    required this.onTapDay,
  });

  final List<String> labels;
  final List<int> counts;
  final int? highlightIndex;
  final void Function(int index) onTapDay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(labels.length, (index) {
        final isActive = highlightIndex == index;
        return Expanded(
          child: InkWell(
            onTap: () => onTapDay(index),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: isActive ? Colors.white.withOpacity(0.14) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withOpacity(isActive ? 0.3 : 0.12),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      labels[index],
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: Colors.white70,
                        fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${counts[index]}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _SecurityLinePainter extends CustomPainter {
  _SecurityLinePainter({
    required this.points,
    required this.strokeColor,
    required this.fillColor,
    this.highlightIndex,
  });

  final List<double> points;
  final Color strokeColor;
  final Color fillColor;
  final int? highlightIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final path = Path();
    final fillPath = Path();
    final maxPoint = points
        .reduce((a, b) => a > b ? a : b)
        .clamp(0.01, double.infinity)
        .toDouble();

    final dx = size.width / (points.length - 1);
    final firstY = size.height - (points.first / maxPoint) * size.height;
    final offsets = <Offset>[];

    path.moveTo(0, firstY);
    fillPath.moveTo(0, size.height);
    fillPath.lineTo(0, firstY);
    offsets.add(Offset(0, firstY));

    for (var i = 1; i < points.length; i++) {
      final x = dx * i;
      final y = size.height - (points[i] / maxPoint) * size.height;
      path.lineTo(x, y);
      fillPath.lineTo(x, y);
      offsets.add(Offset(x, y));
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        colors: [fillColor, Colors.transparent],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = strokeColor
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 0.8);

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, strokePaint);

    if (highlightIndex != null &&
        highlightIndex! >= 0 &&
        highlightIndex! < offsets.length) {
      final point = offsets[highlightIndex!];

      final glowPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = strokeColor.withOpacity(0.28);

      final dotPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = Colors.white;

      final innerDotPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = strokeColor;

      canvas.drawCircle(point, 10, glowPaint);
      canvas.drawCircle(point, 5.5, dotPaint);
      canvas.drawCircle(point, 3.6, innerDotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SecurityLinePainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.strokeColor != strokeColor ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.highlightIndex != highlightIndex;
  }
}

class _WeekContext {
  _WeekContext({
    required this.month,
    required this.weekOfMonth,
    required this.dayLabels,
  });

  final int month;
  final int weekOfMonth;
  final List<String> dayLabels;

  factory _WeekContext.fromDate(DateTime date) {
    final local = DateTime(date.year, date.month, date.day);
    final startOfWeek = local.subtract(Duration(days: (local.weekday + 6) % 7)); // Monday as 0
    final days = List.generate(7, (i) => startOfWeek.add(Duration(days: i)));

    final firstOfMonth = DateTime(local.year, local.month, 1);
    final firstWeekdayOffset = (firstOfMonth.weekday + 6) % 7; // 0-based, Monday start
    final dayIndex = local.day + firstWeekdayOffset - 1;
    final weekOfMonth = (dayIndex / 7).floor() + 1;

    return _WeekContext(
      month: local.month,
      weekOfMonth: weekOfMonth,
      dayLabels: days.map((d) => _weekdaySymbolsKo[(d.weekday + 6) % 7]).toList(),
    );
  }
}
