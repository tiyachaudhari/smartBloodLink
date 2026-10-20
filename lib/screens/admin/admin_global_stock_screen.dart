import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/iot_models.dart';
import '../../providers/admin_provider.dart';
import '../../providers/app_mode_provider.dart';
import '../../utils/app_colors.dart';
import '../../utils/constants.dart';
import '../../widgets/animated_card.dart';
import '../../widgets/mode_switch.dart';

/// Screen aggregating city-wide blood bank inventory and regional shortage heatmaps
class AdminGlobalStockScreen extends StatelessWidget {
  const AdminGlobalStockScreen({super.key});

  /// The bundled simulation used in demo mode.
  static const Map<String, int> _demoUnits = {
    'O+': 42,
    'O-': 8,
    'A+': 36,
    'A-': 11,
    'B+': 54,
    'B-': 7,
    'AB+': 28,
    'AB-': 5,
  };

  /// Below this many units a blood group is considered short.
  static const int _lowStockThreshold = 3;

  @override
  Widget build(BuildContext context) {
    final adminProvider = context.watch<AdminProvider>();
    final modeProvider = context.watch<AppModeProvider>();
    final isReal = modeProvider.isReal;

    final stock = isReal ? _realStock(adminProvider) : _demoStock();
    final shortageGroups = _shortageGroups(stock);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Global Blood Stock Health'),
        actions: const [ModeSwitch()],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Critical Shortage Warning Banner
            if (isReal)
              _realShortageBanner(shortageGroups)
            else
              const _DemoShortageBanner(),
            if (isReal && shortageGroups.isNotEmpty) const SizedBox(height: 20),
            if (!isReal) const SizedBox(height: 20),

            Text(
              isReal
                  ? 'City-Wide Stock Matrix (Live Server Data)'
                  : 'City-Wide Stock Matrix (24 Blood Centers)',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: BloodConstants.groups.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1.6,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemBuilder: (context, index) {
                final group = BloodConstants.groups[index];
                final data = stock[group]!;

                return AnimatedCard(
                  padding: const EdgeInsets.all(14),
                  border: Border.all(color: data.color.withOpacity(0.4)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            group,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: data.color.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              data.status,
                              style: TextStyle(
                                color: data.color,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${data.units} Bags Available',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: data.color,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 24),

            // Top Blood Centers by Inventory Volume
            Text(
              isReal
                  ? 'Cold-Chain Gateways (VitaLink Server)'
                  : 'Connected Blood Bank Hubs',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            if (isReal)
              _DeviceList(devices: adminProvider.devices)
            else
              const AnimatedCard(
                padding: EdgeInsets.all(14),
                child: Column(
                  children: [
                    _CenterRow('City Apex Blood Center & Research', '84 Units',
                        true),
                    Divider(),
                    _CenterRow('Sassoon General Hospital Red Cross', '112 Units',
                        true),
                    Divider(),
                    _CenterRow('Ruby Hall Clinic Blood Bank', '68 Units', true),
                    Divider(),
                    _CenterRow('Deenanath Mangeshkar Blood Center', '72 Units',
                        true),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─── Data ────────────────────────────────────────────────────────────

  /// Stock per blood group, as reported by the VitaLink server.
  Map<String, _GroupStock> _realStock(AdminProvider provider) {
    final counts = provider.stockCounts;
    final stock = <String, _GroupStock>{};
    for (final group in BloodConstants.groups) {
      final units = counts[group] ?? 0;
      stock[group] = _GroupStock.fromUnits(units);
    }
    return stock;
  }

  /// The bundled simulation used in demo mode.
  Map<String, _GroupStock> _demoStock() {
    const statusByGroup = <String, String>{
      'O+': 'Optimal',
      'O-': 'Critical Shortage',
      'A+': 'Optimal',
      'A-': 'Moderate',
      'B+': 'Surplus',
      'B-': 'Critical Shortage',
      'AB+': 'Optimal',
      'AB-': 'Critical Shortage',
    };
    const colorByGroup = <String, Color>{
      'O+': AppColors.success,
      'O-': AppColors.error,
      'A+': AppColors.success,
      'A-': AppColors.warning,
      'B+': AppColors.success,
      'B-': AppColors.error,
      'AB+': AppColors.success,
      'AB-': AppColors.error,
    };

    final stock = <String, _GroupStock>{};
    for (final group in BloodConstants.groups) {
      final units = _demoUnits[group] ?? 0;
      stock[group] = _GroupStock(
        units: units,
        status: statusByGroup[group] ?? 'Optimal',
        color: colorByGroup[group] ?? AppColors.success,
      );
    }
    return stock;
  }

  /// Groups that are not stocked at all or hold fewer units than the
  /// emergency buffer.
  List<String> _shortageGroups(Map<String, _GroupStock> stock) {
    return stock.entries
        .where((e) => e.value.units < _lowStockThreshold)
        .map((e) => e.key)
        .toList();
  }

  // ─── Banners ─────────────────────────────────────────────────────────

  Widget _realShortageBanner(List<String> shortageGroups) {
    if (shortageGroups.isEmpty) return const SizedBox.shrink();
    final label = shortageGroups.join(', ');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.errorLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.error),
      ),
      child: Row(
        children: [
          const Icon(Icons.emergency_rounded, color: AppColors.error, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'REGIONAL SHORTAGE WARNING: $label '
              '${shortageGroups.length == 1 ? 'is' : 'are'} below the emergency '
              'buffer of $_lowStockThreshold units reported by the devices.',
              style: const TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The demo shortage banner — the bundled simulation always warns.
class _DemoShortageBanner extends StatelessWidget {
  const _DemoShortageBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.errorLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.error),
      ),
      child: const Row(
        children: [
          Icon(Icons.emergency_rounded, color: AppColors.error, size: 30),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'REGIONAL SHORTAGE WARNING: Rh-Negative reserves (O-, B-, AB-) are below critical emergency buffer thresholds.',
              style: TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The cold-chain devices the VitaLink server knows about.
class _DeviceList extends StatelessWidget {
  final List<IotDevice> devices;

  const _DeviceList({required this.devices});

  @override
  Widget build(BuildContext context) {
    if (devices.isEmpty) {
      return const AnimatedCard(
        padding: EdgeInsets.all(14),
        child: Column(
          children: [
            Icon(Icons.ac_unit_rounded, color: Colors.grey, size: 32),
            SizedBox(height: 8),
            Text(
              'No cold-chain devices are registered on the VitaLink server',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      );
    }
    return AnimatedCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          for (int i = 0; i < devices.length; i++) ...[
            if (i > 0) const Divider(),
            _DeviceRow(device: devices[i]),
          ],
        ],
      ),
    );
  }
}

/// One cold-chain device with its online state and bag count.
class _DeviceRow extends StatelessWidget {
  final IotDevice device;

  const _DeviceRow({required this.device});

  @override
  Widget build(BuildContext context) {
    final online = device.online;
    final color = online ? AppColors.success : AppColors.error;
    final storage = device.storageUnit.isEmpty ? '—' : device.storageUnit;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  storage,
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                online ? 'ONLINE' : 'OFFLINE',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  color: color,
                ),
              ),
              Text(
                '${device.bagCount} bags',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Stock of a single blood group.
class _GroupStock {
  final int units;
  final String status;
  final Color color;

  const _GroupStock({
    required this.units,
    required this.status,
    required this.color,
  });

  /// Status derived from the number of units the server reported.
  factory _GroupStock.fromUnits(int units) {
    if (units <= 0) {
      return _GroupStock(
        units: units,
        status: 'Not stocked',
        color: Colors.grey,
      );
    }
    if (units < 3) {
      return _GroupStock(
        units: units,
        status: 'Low',
        color: AppColors.warning,
      );
    }
    return _GroupStock(
      units: units,
      status: 'Optimal',
      color: AppColors.success,
    );
  }
}

class _CenterRow extends StatelessWidget {
  final String name;
  final String units;
  final bool isOnline;

  const _CenterRow(this.name, this.units, this.isOnline);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                name,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          Text(
            units,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}
