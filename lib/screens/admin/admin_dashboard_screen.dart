import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/admin_provider.dart';
import '../../providers/app_mode_provider.dart';
import '../../utils/app_colors.dart';
import '../../widgets/animated_card.dart';
import '../../widgets/role_app_bar.dart';
import '../hospital/iot_temperature_screen.dart';
import 'admin_system_settings_screen.dart';

/// Administrator Overview Dashboard with platform metrics, uptime, and system monitoring
class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final adminProvider = context.watch<AdminProvider>();
    final modeProvider = context.watch<AppModeProvider>();
    final metrics = adminProvider.metrics;
    final isReal = modeProvider.isReal;

    return Scaffold(
      appBar: const RoleAppBar(title: 'Admin Console'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Server trouble banner — only meaningful in real mode
            if (isReal && adminProvider.realError != null) ...[
              _WarningBanner(message: adminProvider.realError!),
              const SizedBox(height: 12),
            ],

            // Top Executive KPI Row
            _buildKpiRows(adminProvider, metrics, isReal),
            const SizedBox(height: 24),

            // Real-Time System Health Architecture
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'System Infrastructure Status',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Live cold-chain telemetry',
                      icon: const Icon(Icons.ac_unit_rounded, size: 20),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const IotTemperatureScreen(),
                          ),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.settings_outlined, size: 20),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AdminSystemSettingsScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            AnimatedCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: isReal
                    ? _realHealthRows(adminProvider, metrics)
                    : _demoHealthRows(),
              ),
            ),
            const SizedBox(height: 24),

            // Recent Security Audit Events
            const Text(
              'Recent Security & Audit Trail',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            AnimatedCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: adminProvider.auditLogs.isEmpty
                    ? [
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'No audit entries published by the VitaLink server',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ),
                      ]
                    : adminProvider.auditLogs.take(4).map((log) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: log.severity == 'Critical'
                                ? AppColors.errorLight
                                : (log.severity == 'Warning'
                                    ? AppColors.warningLight
                                    : AppColors.infoLight),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            log.severity == 'Critical'
                                ? Icons.warning_rounded
                                : Icons.security_rounded,
                            size: 16,
                            color: log.severity == 'Critical'
                                ? AppColors.error
                                : (log.severity == 'Warning'
                                    ? AppColors.warning
                                    : AppColors.info),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                log.action,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                log.details,
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${log.timestamp.hour.toString().padLeft(2, '0')}:${log.timestamp.minute.toString().padLeft(2, '0')}',
                          style: const TextStyle(
                              fontSize: 10, color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // ─── KPI cards ───────────────────────────────────────────────────────

  /// Builds the two KPI rows. In real mode every number comes from the
  /// VitaLink server; in demo mode the bundled simulation is used.
  Widget _buildKpiRows(
    AdminProvider adminProvider,
    Map<String, int> metrics,
    bool isReal,
  ) {
    if (isReal) {
      final openAlerts = metrics['openAlerts'];
      final alertCount = openAlerts ?? 0;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _KpiCard(
                  title: 'COLD-CHAIN DEVICES',
                  value: _metricText(metrics, 'totalDevices'),
                  subtitle:
                      '${_metricText(metrics, 'onlineDevices')} online',
                  color: AppColors.primary,
                  icon: Icons.ac_unit_rounded,
                  caption: _captionFor(adminProvider, 'totalDevices'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _KpiCard(
                  title: 'HOSPITALS LINKED',
                  value: _metricText(metrics, 'totalHospitals'),
                  subtitle: 'With cold-chain devices',
                  color: const Color(0xFF1976D2),
                  icon: Icons.local_hospital_rounded,
                  caption: _captionFor(adminProvider, 'totalHospitals'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _KpiCard(
                  title: 'CITY BLOOD UNITS',
                  value: _metricText(metrics, 'totalUnitsInStock'),
                  subtitle: 'Reported by the devices',
                  color: AppColors.success,
                  icon: Icons.inventory_2_rounded,
                  caption: _captionFor(adminProvider, 'totalUnitsInStock'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _KpiCard(
                  title: 'OPEN ALERTS',
                  value: _metricText(metrics, 'openAlerts'),
                  subtitle: alertCount > 0
                      ? 'Requires attention'
                      : 'No open cold-chain alerts',
                  color: alertCount > 0 ? AppColors.error : AppColors.success,
                  icon: Icons.notifications_active_rounded,
                  caption: _captionFor(adminProvider, 'openAlerts'),
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _KpiCard(
                title: 'REGISTERED DONORS',
                value: '${metrics['totalDonors'] ?? 1420}',
                subtitle: '+18 this week',
                color: AppColors.primary,
                icon: Icons.volunteer_activism_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _KpiCard(
                title: 'HOSPITALS LINKED',
                value: '${metrics['totalHospitals'] ?? 24}',
                subtitle: '100% Verified',
                color: const Color(0xFF1976D2),
                icon: Icons.local_hospital_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _KpiCard(
                title: 'CITY BLOOD UNITS',
                value: '${metrics['totalUnitsInStock'] ?? 384}',
                subtitle: 'Across all banks',
                color: AppColors.success,
                icon: Icons.inventory_2_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _KpiCard(
                title: 'MATCHING LATENCY',
                value: '1.4s',
                subtitle: 'Under 2s target',
                color: AppColors.warning,
                icon: Icons.speed_rounded,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// A missing metric is shown as a dash instead of an invented number.
  String _metricText(Map<String, int> metrics, String key) {
    final value = metrics[key];
    return value == null ? '—' : '$value';
  }

  /// Marks a value the server did not publish.
  String? _captionFor(AdminProvider provider, String key) {
    if (!provider.isRealMode) return null;
    return provider.isSimulatedMetric(key) ? 'simulated' : null;
  }

  // ─── Infrastructure status rows ──────────────────────────────────────

  /// Demo rows — the bundled simulation describes the whole platform.
  List<Widget> _demoHealthRows() {
    return [
      _HealthRow(
        service: 'Cloud Functions Matching Engine',
        status: 'OPERATIONAL',
        latency: '42ms',
        isHealthy: true,
      ),
      const Divider(),
      _HealthRow(
        service: 'ESP32 Cold-Chain IoT Gateways',
        status: '24/24 ONLINE',
        latency: '4.0s tick',
        isHealthy: true,
      ),
      const Divider(),
      _HealthRow(
        service: 'Firestore Transaction Concurrency Locks',
        status: 'ACTIVE (0 Conflicts)',
        latency: '12ms',
        isHealthy: true,
      ),
      const Divider(),
      _HealthRow(
        service: 'Firebase Cloud Messaging (FCM Push)',
        status: 'CONNECTED',
        latency: '820ms',
        isHealthy: true,
      ),
    ];
  }

  /// Real rows — everything is derived from the VitaLink server.
  List<Widget> _realHealthRows(
    AdminProvider provider,
    Map<String, int> metrics,
  ) {
    final devices = metrics['totalDevices'];
    final online = metrics['onlineDevices'];
    final openAlerts = metrics['openAlerts'] ?? 0;
    final lastSync = provider.lastSync;
    final syncText = lastSync == null
        ? '—'
        : '${lastSync.hour.toString().padLeft(2, '0')}:'
            '${lastSync.minute.toString().padLeft(2, '0')}:'
            '${lastSync.second.toString().padLeft(2, '0')}';

    return [
      _HealthRow(
        service: 'VitaLink API',
        status: provider.realError == null ? 'OPERATIONAL' : 'DEGRADED',
        isHealthy: provider.realError == null,
        detail: provider.realError ?? 'Connected to the VitaLink server',
      ),
      const Divider(),
      _HealthRow(
        service: 'ESP32 Cold-Chain Gateways',
        status: '${online ?? 0}/${devices ?? 0} ONLINE',
        isHealthy: devices != null && devices > 0 && online == devices,
        detail: 'Cold-chain devices registered on the server',
      ),
      const Divider(),
      _HealthRow(
        service: 'Cold-chain alerts',
        status: '$openAlerts open',
        isHealthy: openAlerts == 0,
        detail: 'Open alerts raised by the VitaLink server',
      ),
      const Divider(),
      _HealthRow(
        service: 'Last server sync',
        status: syncText,
        isHealthy: lastSync != null,
        detail: 'Last successful poll of the VitaLink server',
      ),
    ];
  }

  Widget _KpiCard({
    required String title,
    required String value,
    required String subtitle,
    required Color color,
    required IconData icon,
    String? caption,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: color,
                  letterSpacing: 0.5,
                ),
              ),
              Icon(icon, size: 18, color: color),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          if (caption != null) ...[
            const SizedBox(height: 2),
            Text(
              caption,
              style: const TextStyle(
                fontSize: 9,
                color: Colors.grey,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _HealthRow({
    required String service,
    required String status,
    String? latency,
    String? detail,
    required bool isHealthy,
  }) {
    final sub = detail ?? (latency != null ? 'Latency: $latency' : '');
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                service,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              if (sub.isNotEmpty)
                Text(
                  sub,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: (isHealthy ? AppColors.success : AppColors.error)
                .withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            status,
            style: TextStyle(
              color: isHealthy ? AppColors.success : AppColors.error,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }
}

/// Small banner that explains why the server data may be incomplete.
class _WarningBanner extends StatelessWidget {
  final String message;

  const _WarningBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.cloud_off_rounded, color: AppColors.warning, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Live data unavailable — $message',
              style: const TextStyle(
                color: AppColors.warning,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
