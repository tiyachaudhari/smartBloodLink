import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';

import '../../models/inventory_item_model.dart';
import '../../providers/admin_provider.dart';
import '../../providers/app_mode_provider.dart';
import '../../services/mock_data_service.dart';
import '../../utils/app_colors.dart';
import '../../widgets/mode_switch.dart';

/// System-wide analytics and reports dashboard.
/// Shows donation trends, request outcomes, inventory levels, and donor activity.
class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports & Analytics'),
        actions: [
          const ModeSwitch(),
          IconButton(
            icon: const Icon(Icons.share_rounded),
            tooltip: 'Share Report',
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Report PDF generated and ready to share'),
                behavior: SnackBarBehavior.floating,
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Donations'),
            Tab(text: 'Inventory'),
            Tab(text: 'Requests'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _DonationsTab(),
          _InventoryTab(),
          _RequestsTab(),
        ],
      ),
    );
  }
}

// ─── Donations Tab ────────────────────────────────────────────────────────────

class _DonationsTab extends StatelessWidget {
  // Mock 6-month donation data
  static const _monthlyDonations = [42.0, 55.0, 38.0, 71.0, 63.0, 80.0];
  static const _months = ['Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isReal = context.watch<AppModeProvider>().isReal;
    final donors = MockDataService.initialUsers
        .where((u) => u.role.name == 'donor')
        .length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (isReal) ...[
          const _SimulatedCaption(
            'Simulated — the VitaLink server does not publish donation data yet',
          ),
          const SizedBox(height: 16),
        ],
        // KPI row
        Row(
          children: [
            _KpiCard(
              label: 'Total Donors',
              value: donors.toString(),
              icon: Icons.favorite_rounded,
              color: AppColors.bloodRed,
            ),
            const SizedBox(width: 12),
            _KpiCard(
              label: 'This Month',
              value: '80',
              icon: Icons.trending_up_rounded,
              color: AppColors.success,
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Bar chart
        Text('Monthly Donations', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        SizedBox(
          height: 220,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: 100,
              barTouchData: BarTouchData(enabled: true),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32,
                    getTitlesWidget: (v, _) => Text(
                      v.toInt().toString(),
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      return Text(
                        i < _months.length ? _months[i] : '',
                        style: theme.textTheme.labelSmall,
                      );
                    },
                  ),
                ),
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: FlGridData(
                drawHorizontalLine: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: theme.dividerColor, strokeWidth: 0.5),
              ),
              borderData: FlBorderData(show: false),
              barGroups: List.generate(
                _monthlyDonations.length,
                (i) => BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: _monthlyDonations[i],
                      color: AppColors.bloodRed,
                      width: 20,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(6),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Blood-group breakdown
        Text('Donations by Blood Group', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        _BloodGroupBreakdown(),
      ],
    );
  }
}

class _BloodGroupBreakdown extends StatelessWidget {
  static const _groups = {
    'O+': 0.30,
    'A+': 0.25,
    'B+': 0.20,
    'AB+': 0.10,
    'O-': 0.07,
    'A-': 0.05,
    'B-': 0.02,
    'AB-': 0.01,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: _groups.entries.map((e) {
        final pct = (e.value * 100).toInt();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                child: Text(e.key, style: theme.textTheme.bodySmall),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: e.value,
                    minHeight: 10,
                    backgroundColor:
                        theme.colorScheme.surfaceContainerHighest,
                    color: AppColors.bloodRed,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('$pct%', style: theme.textTheme.labelSmall),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ─── Inventory Tab ────────────────────────────────────────────────────────────

class _InventoryTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isReal = context.watch<AppModeProvider>().isReal;
    final provider = context.watch<AdminProvider>();

    // In real mode the numbers come from the bags the cold-chain devices
    // reported; in demo mode the bundled simulation is used.
    final List<BloodBagModel> inventory =
        isReal ? provider.bags : MockDataService.initialInventory;

    final byGroup = <String, int>{};
    for (final bag in inventory) {
      byGroup[bag.bloodGroup] = (byGroup[bag.bloodGroup] ?? 0) + bag.units;
    }

    final total = inventory.fold<int>(0, (sum, b) => sum + b.units);
    final available =
        inventory.where((b) => b.status.name == 'available').length;
    final expiringSoon = inventory
        .where((b) => b.expiryDate.difference(DateTime.now()).inDays <= 7)
        .length;

    // The server only publishes an expiry date for some bags, so the
    // "expiring soon" count is only shown when it is known.
    final expiryKnownBags = inventory.where((b) => b.expiryKnown).toList();
    final expiringSoonValue = isReal
        ? (expiryKnownBags.isEmpty
            ? null
            : expiryKnownBags
                .where((b) =>
                    b.expiryDate.difference(DateTime.now()).inDays <= 7)
                .length)
        : expiringSoon;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (isReal) ...[
          const _SourceCaption(
            'Live stock reported by the VitaLink cold-chain devices',
          ),
          const SizedBox(height: 16),
        ],
        Row(
          children: [
            _KpiCard(
              label: 'Total Units',
              value: total.toString(),
              icon: Icons.water_drop_rounded,
              color: AppColors.info,
            ),
            const SizedBox(width: 12),
            _KpiCard(
              label: isReal ? 'Bags Reported' : 'Available',
              value: isReal
                  ? inventory.length.toString()
                  : available.toString(),
              icon: Icons.check_circle_rounded,
              color: AppColors.success,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _KpiCard(
              label: 'Expiring ≤ 7d',
              value: expiringSoonValue?.toString() ?? '—',
              icon: Icons.timer_off_rounded,
              color: AppColors.warning,
            ),
            const SizedBox(width: 12),
            _KpiCard(
              label: 'Blood Groups',
              value: byGroup.length.toString(),
              icon: Icons.category_rounded,
              color: AppColors.bloodRed,
            ),
          ],
        ),
        const SizedBox(height: 20),

        Text('Units by Blood Group', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),

        if (byGroup.isEmpty)
          const Center(child: Text('No inventory data'))
        else
          SizedBox(
            height: 220,
            child: PieChart(
              PieChartData(
                sectionsSpace: 3,
                centerSpaceRadius: 48,
                sections: byGroup.entries.indexed.map((entry) {
                  final idx = entry.$1;
                  final e = entry.$2;
                  final colors = [
                    AppColors.bloodRed,
                    AppColors.info,
                    AppColors.success,
                    AppColors.warning,
                    Colors.purple,
                    Colors.teal,
                    Colors.orange,
                    Colors.indigo,
                  ];
                  return PieChartSectionData(
                    value: e.value.toDouble(),
                    title: '${e.key}\n${e.value}',
                    color: colors[idx % colors.length],
                    radius: 72,
                    titleStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Requests Tab ─────────────────────────────────────────────────────────────

class _RequestsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isReal = context.watch<AppModeProvider>().isReal;
    final requests = MockDataService.initialRequests;

    final fulfilled =
        requests.where((r) => r.status.name == 'fulfilled').length;
    final pending = requests.where((r) => r.status.name == 'pending').length;
    final cancelled =
        requests.where((r) => r.status.name == 'cancelled').length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (isReal) ...[
          const _SimulatedCaption(
            'Simulated — the VitaLink server does not publish request data yet',
          ),
          const SizedBox(height: 16),
        ],
        Row(
          children: [
            _KpiCard(
              label: 'Fulfilled',
              value: fulfilled.toString(),
              icon: Icons.done_all_rounded,
              color: AppColors.success,
            ),
            const SizedBox(width: 12),
            _KpiCard(
              label: 'Pending',
              value: pending.toString(),
              icon: Icons.hourglass_top_rounded,
              color: AppColors.warning,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _KpiCard(
              label: 'Cancelled',
              value: cancelled.toString(),
              icon: Icons.cancel_rounded,
              color: AppColors.error,
            ),
            const SizedBox(width: 12),
            _KpiCard(
              label: 'Total',
              value: requests.length.toString(),
              icon: Icons.receipt_long_rounded,
              color: AppColors.info,
            ),
          ],
        ),
        const SizedBox(height: 20),

        Text('Fulfillment Rate', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),

        if (requests.isNotEmpty) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: requests.isEmpty ? 0 : fulfilled / requests.length,
              minHeight: 18,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              color: AppColors.success,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            requests.isEmpty
                ? '0%'
                : '${(fulfilled / requests.length * 100).toStringAsFixed(1)}% of requests fulfilled',
            style: theme.textTheme.bodySmall,
          ),
        ],

        const SizedBox(height: 20),
        Text('Urgency Breakdown', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),

        ...['emergency', 'urgent', 'routine'].map((level) {
          final count =
              requests.where((r) => r.urgency.name == level).length;
          final color = level == 'emergency'
              ? AppColors.error
              : level == 'urgent'
                  ? AppColors.warning
                  : AppColors.success;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 76,
                  child: Text(
                    level[0].toUpperCase() + level.substring(1),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: requests.isEmpty ? 0 : count / requests.length,
                      minHeight: 10,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('$count', style: theme.textTheme.labelSmall),
              ],
            ),
          );
        }),
      ],
    );
  }
}

// ─── Captions ─────────────────────────────────────────────────────────────────

/// Marks a section whose numbers come from the bundled simulation because
/// the VitaLink server does not publish that data.
class _SimulatedCaption extends StatelessWidget {
  final String message;

  const _SimulatedCaption(this.message);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withOpacity(0.6)),
      ),
      child: Row(
        children: [
          const Icon(Icons.science_rounded, size: 16, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.warning,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Marks a section whose numbers come from the VitaLink server.
class _SourceCaption extends StatelessWidget {
  final String message;

  const _SourceCaption(this.message);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.successLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.success.withOpacity(0.6)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_done_rounded,
              size: 16, color: AppColors.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.success,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Shared KPI card ──────────────────────────────────────────────────────────

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: theme.dividerColor),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: color.withOpacity(0.15),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
