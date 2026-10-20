import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import 'pulse_animation.dart';

/// Interactive vector map simulator rendering GPS routes, hospitals, and moving emergency vehicles
class MockMapWidget extends StatelessWidget {
  final double currentLat;
  final double currentLng;
  final String pickupName;
  final String destinationName;
  final double distanceRemainingKm;
  final int etaMinutes;
  final double height;

  const MockMapWidget({
    super.key,
    required this.currentLat,
    required this.currentLng,
    required this.pickupName,
    required this.destinationName,
    required this.distanceRemainingKm,
    required this.etaMinutes,
    this.height = 240,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // The map is sometimes asked to fill the space that is left over, which
    // means an infinite height. An infinite height must not reach the
    // layout: it would place the moving marker at an infinite offset and the
    // canvas would be handed a NaN coordinate.
    final fixedHeight = height.isFinite ? height : null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: fixedHeight,
        width: double.infinity,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A2130) : const Color(0xFFE8EEF5),
          border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Marker positions come from the size the map actually got, so
            // they are always finite and always inside the map.
            final double mapWidth =
                constraints.maxWidth.isFinite ? constraints.maxWidth : 0.0;
            final double mapHeight =
                constraints.maxHeight.isFinite ? constraints.maxHeight : 0.0;

            return Stack(
              children: [
                // Custom Painter for roads, grid, and route
                Positioned.fill(
                  child: CustomPaint(
                    painter: _MapGridPainter(isDark: isDark),
                  ),
                ),

                // Pickup Hospital Marker (Top Left Area)
                Positioned(
                  top: 20,
                  left: 20,
                  child: _LocationMarker(
                    label: pickupName,
                    icon: Icons.local_hospital_rounded,
                    color: const Color(0xFF1976D2),
                  ),
                ),

                // Destination Clinic Marker (Bottom Right Area)
                Positioned(
                  bottom: 52,
                  right: 20,
                  child: _LocationMarker(
                    label: destinationName,
                    icon: Icons.personal_injury_rounded,
                    color: AppColors.primary,
                  ),
                ),

                // Moving Ambulance Marker (Center of route)
                Positioned(
                  top: mapHeight * 0.42,
                  left: mapWidth * 0.42,
                  child: PulseAnimation(
                    pulseColor: AppColors.primary,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.emergency_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),

                // Live Telemetry Badge (Bottom Bar)
                Positioned(
                  bottom: 12,
                  left: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.black.withOpacity(0.8)
                          : Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: AppColors.softShadow,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.success,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'LIVE GPS (5s)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.success,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$distanceRemainingKm km remaining • ETA: $etaMinutes mins',
                            textAlign: TextAlign.right,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LocationMarker extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _LocationMarker({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.35),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 16),
        ),
        const SizedBox(height: 4),
        Container(
          constraints: const BoxConstraints(maxWidth: 130),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.65),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _MapGridPainter extends CustomPainter {
  final bool isDark;
  _MapGridPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final roadPaint = Paint()
      ..color = isDark ? const Color(0xFF2C394F) : const Color(0xFFD3DFEE)
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke;

    final routePaint = Paint()
      ..color = AppColors.primary.withOpacity(0.85)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Draw background grid lines (roads)
    canvas.drawLine(
        Offset(0, size.height * 0.3), Offset(size.width, size.height * 0.3), roadPaint);
    canvas.drawLine(
        Offset(0, size.height * 0.7), Offset(size.width, size.height * 0.7), roadPaint);
    canvas.drawLine(
        Offset(size.width * 0.25, 0), Offset(size.width * 0.25, size.height), roadPaint);
    canvas.drawLine(
        Offset(size.width * 0.75, 0), Offset(size.width * 0.75, size.height), roadPaint);

    // Draw emergency route connecting pickup to destination
    final path = Path();
    path.moveTo(45, 45);
    path.cubicTo(
      size.width * 0.3,
      size.height * 0.2,
      size.width * 0.45,
      size.height * 0.7,
      size.width - 45,
      size.height - 55,
    );

    canvas.drawPath(path, routePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
