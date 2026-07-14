import 'package:flutter/material.dart';

class PaperBackground extends StatelessWidget {
  final Widget child;
  final bool isDark;

  const PaperBackground({
    super.key,
    required this.child,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Base color
        Container(
          color: isDark ? const Color(0xFF0B0F19) : const Color(0xFFFCFBF7),
        ),
        // Ruled Lines Painter
        Positioned.fill(
          child: CustomPaint(
            painter: PaperPainter(isDark: isDark),
          ),
        ),
        // Folds / Creases Overlay 1 (Shadow and Highlight 135deg)
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(isDark ? 0.02 : 0.35),
                  Colors.black.withOpacity(isDark ? 0.22 : 0.06),
                  Colors.white.withOpacity(isDark ? 0.04 : 0.25),
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
        ),
        // Folds / Creases Overlay 2 (Fold 45deg)
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomLeft,
                end: Alignment.topRight,
                colors: [
                  Colors.black.withOpacity(isDark ? 0.18 : 0.04),
                  Colors.white.withOpacity(isDark ? 0.02 : 0.2),
                  Colors.black.withOpacity(isDark ? 0.25 : 0.08),
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
        ),
        // Actual Content
        Positioned.fill(
          child: child,
        ),
      ],
    );
  }
}

class PaperPainter extends CustomPainter {
  final bool isDark;

  PaperPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    // Ruled lines spacing
    const double lineSpacing = 24.0;
    
    final paintLine = Paint()
      ..color = isDark ? const Color(0xFF2E3B4E).withOpacity(0.4) : const Color(0xFF93C5FD).withOpacity(0.3)
      ..strokeWidth = 1.0;

    final paintMargin = Paint()
      ..color = isDark ? const Color(0xFFF43F5E).withOpacity(0.5) : const Color(0xFFEF4444).withOpacity(0.3)
      ..strokeWidth = 1.5;

    // Draw horizontal lines across the canvas
    for (double y = lineSpacing; y < size.height; y += lineSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paintLine);
    }

    // Draw a single pink vertical margin line at 80px offset
    canvas.drawLine(const Offset(80.0, 0), Offset(80.0, size.height), paintMargin);
  }

  @override
  bool shouldRepaint(covariant PaperPainter oldDelegate) {
    return oldDelegate.isDark != isDark;
  }
}
