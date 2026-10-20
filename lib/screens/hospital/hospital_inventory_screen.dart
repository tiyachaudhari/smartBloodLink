import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../providers/hospital_provider.dart';
import '../../utils/app_colors.dart';
import '../../widgets/animated_card.dart';
import '../../widgets/mode_switch.dart';
import '../../widgets/status_badge.dart';
import 'add_blood_unit_screen.dart';
import 'rfid_bag_details_screen.dart';

/// Hospital Blood Bank Inventory Management Screen
class HospitalInventoryScreen extends StatefulWidget {
  const HospitalInventoryScreen({super.key});

  @override
  State<HospitalInventoryScreen> createState() =>
      _HospitalInventoryScreenState();
}

class _HospitalInventoryScreenState extends State<HospitalInventoryScreen> {
  String _statusFilter = 'All';

  @override
  Widget build(BuildContext context) {
    final hospitalProvider = context.watch<HospitalProvider>();
    final bags = hospitalProvider.bags;

    final filtered = bags.where((b) {
      if (_statusFilter == 'All') return true;
      return b.status.name.toLowerCase() == _statusFilter.toLowerCase();
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Blood Bank Inventory'),
        actions: [
          const ModeSwitch(),
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AddBloodUnitScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                'All',
                'Stored',
                'Reserved',
                'Issued',
                'Transferred',
                'Discarded'
              ].map((status) {
                final isSelected = _statusFilter == status;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(status),
                    selected: isSelected,
                    selectedColor: AppColors.primary.withOpacity(0.2),
                    onSelected: (val) {
                      setState(() {
                        _statusFilter = status;
                      });
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(),

          Expanded(
            child: filtered.isEmpty
                ? _emptyState(hospitalProvider)
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final bag = filtered[index];
                      return AnimatedCard(
                        margin: const EdgeInsets.only(bottom: 12),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  RfidBagDetailsScreen(bag: bag),
                            ),
                          );
                        },
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Text(
                                  bag.bloodGroup,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        bag.bagId,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      StatusBadge.fromBagStatus(bag.status),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'RFID: ${bag.rfidTag}',
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      // The server may not send an expiry
                                      // date, so a missing one is shown as
                                      // "not reported" instead of a date.
                                      Flexible(
                                        child: Text(
                                          bag.expiryKnown
                                              ? 'Expires: ${DateFormat("dd MMM yyyy").format(bag.expiryDate)}'
                                              : 'Expiry: not reported by the device',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: bag.expiryKnown &&
                                                    bag.daysUntilExpiry < 7
                                                ? AppColors.error
                                                : Colors.grey,
                                            fontWeight: bag.expiryKnown &&
                                                    bag.daysUntilExpiry < 7
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                          ),
                                        ),
                                      ),
                                      const Spacer(),
                                      const Icon(
                                        Icons.arrow_forward_ios_rounded,
                                        size: 13,
                                        color: Colors.grey,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// Explains why the list is empty.
  ///
  /// In real mode the inventory is whatever the cold-chain device reported,
  /// so an empty list means "the device has not reported a bag yet" rather
  /// than "this hospital has no blood".
  Widget _emptyState(HospitalProvider hospitalProvider) {
    final noBagsAtAll = hospitalProvider.bags.isEmpty;
    final isReal = hospitalProvider.isRealMode;

    if (isReal && noBagsAtAll) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.inventory_2_outlined,
                size: 44,
                color: Colors.grey.withOpacity(0.6),
              ),
              const SizedBox(height: 12),
              const Text(
                'No bags reported by the device yet.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Tap a new bag on the RFID reader to add it.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return const Center(
      child: Text(
        'No blood units matching selected filter',
        style: TextStyle(fontSize: 13, color: Colors.grey),
      ),
    );
  }
}
