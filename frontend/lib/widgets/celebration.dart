import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';

/// Tampilkan animasi sukses (lingkaran + centang tergambar) di atas semua layar.
/// [confetti] = true untuk momen spesial, misalnya target wishlist tercapai.
void showSuccess(BuildContext context, String message, {bool confetti = false}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _SuccessView(
      message: message,
      confetti: confetti,
      onDone: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
  HapticFeedback.mediumImpact();
}

class _SuccessView extends StatefulWidget {
  const _SuccessView({required this.message, required this.confetti, required this.onDone});

  final String message;
  final bool confetti;
  final VoidCallback onDone;

  @override
  State<_SuccessView> createState() => _SuccessViewState();
}

class _SuccessViewState extends State<_SuccessView> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.confetti ? 2600 : 1700),
  )..forward().whenComplete(widget.onDone);

  // Tahapan animasi dalam satu timeline
  late final _appear = CurvedAnimation(parent: _c, curve: const Interval(0, 0.25, curve: Curves.easeOutBack));
  late final _check = CurvedAnimation(parent: _c, curve: const Interval(0.18, 0.45, curve: Curves.easeOutCubic));
  late final _fadeOut = CurvedAnimation(parent: _c, curve: const Interval(0.82, 1, curve: Curves.easeIn));
  final _pieces = _createConfetti();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final opacity = (1 - _fadeOut.value) * _appear.value.clamp(0.0, 1.0);
          return Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(color: Colors.black.withValues(alpha: 0.35 * opacity)),
              ),
              if (widget.confetti)
                Positioned.fill(child: CustomPaint(painter: _ConfettiPainter(_pieces, _c.value))),
              Center(
                child: Opacity(
                  opacity: opacity,
                  child: Transform.scale(
                    scale: 0.6 + 0.4 * _appear.value,
                    child: Material(
                      color: theme.colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(28),
                      elevation: 12,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(32, 28, 32, 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 84,
                              height: 84,
                              child: CustomPaint(
                                painter: _CheckPainter(progress: _check.value, color: AppColors.emerald),
                              ),
                            ),
                            const SizedBox(height: 16),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 240),
                              child: Text(
                                widget.message,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Lingkaran terisi lalu centang putih tergambar mengikuti [progress] 0..1.
class _CheckPainter extends CustomPainter {
  _CheckPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;

    // Lingkaran luar (glow) + lingkaran utama
    canvas.drawCircle(center, radius, Paint()..color = color.withValues(alpha: 0.18));
    canvas.drawCircle(center, radius * (0.55 + 0.25 * progress), Paint()..color = color);

    // Centang
    final path = Path()
      ..moveTo(size.width * 0.33, size.height * 0.52)
      ..lineTo(size.width * 0.45, size.height * 0.64)
      ..lineTo(size.width * 0.68, size.height * 0.39);
    final metric = path.computeMetrics().fold<List<PathMetric>>([], (l, m) => l..add(m));
    final total = metric.fold<double>(0, (s, m) => s + m.length);
    var remaining = total * progress;
    final drawn = Path();
    for (final m in metric) {
      if (remaining <= 0) break;
      drawn.addPath(m.extractPath(0, math.min(remaining, m.length)), Offset.zero);
      remaining -= m.length;
    }
    canvas.drawPath(
      drawn,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.08
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.progress != progress;
}

// =============================================================
// Confetti
// =============================================================

class _Piece {
  _Piece(math.Random r)
      : angle = -math.pi / 2 + (r.nextDouble() - 0.5) * math.pi * 1.1,
        speed = 0.55 + r.nextDouble() * 0.75,
        spin = (r.nextDouble() - 0.5) * 14,
        size = 6 + r.nextDouble() * 7,
        isCircle = r.nextBool(),
        color = _colors[r.nextInt(_colors.length)];

  static const _colors = [
    AppColors.emerald,
    AppColors.mint,
    AppColors.gold,
    AppColors.goldSoft,
    Color(0xFF60A5FA),
    Color(0xFFF472B6),
  ];

  final double angle;
  final double speed;
  final double spin;
  final double size;
  final bool isCircle;
  final Color color;
}

/// Potongan confetti acak; dibuat sekali per animasi supaya geraknya stabil.
List<_Piece> _createConfetti({int count = 70}) {
  final r = math.Random();
  return List.generate(count, (_) => _Piece(r));
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.pieces, this.t);

  final List<_Piece> pieces;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final origin = Offset(size.width / 2, size.height * 0.48);
    final scale = size.shortestSide;
    final fade = t > 0.7 ? (1 - t) / 0.3 : 1.0;

    for (final p in pieces) {
      // Gerak parabola: meledak ke atas, lalu jatuh karena gravitasi
      final dx = math.cos(p.angle) * p.speed * t * scale * 0.9;
      final dy = math.sin(p.angle) * p.speed * t * scale * 0.9 + t * t * scale * 1.3;
      final pos = origin + Offset(dx, dy);
      final paint = Paint()..color = p.color.withValues(alpha: fade);

      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(p.spin * t);
      if (p.isCircle) {
        canvas.drawCircle(Offset.zero, p.size / 2.4, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.5),
            const Radius.circular(2),
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}

/// Confetti yang meledak sekali saat widget pertama muncul.
class ConfettiOnce extends StatefulWidget {
  const ConfettiOnce({super.key, this.delay = Duration.zero});

  final Duration delay;

  @override
  State<ConfettiOnce> createState() => _ConfettiOnceState();
}

class _ConfettiOnceState extends State<ConfettiOnce> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
  final _pieces = _createConfetti();

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => SizedBox.expand(child: CustomPaint(painter: _ConfettiPainter(_pieces, _c.value))),
      ),
    );
  }
}
