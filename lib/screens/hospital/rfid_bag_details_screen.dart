import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/inventory_item_model.dart';
import '../../providers/hospital_provider.dart';
import '../../utils/app_colors.dart';
import '../../utils/constants.dart';
import '../../widgets/animated_card.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/status_badge.dart';

/// Screen displaying comprehensive RFID blood bag record and status transition controls
class RfidBagDetailsScreen extends StatefulWidget {
  final BloodBagModel bag;
  const RfidBagDetailsScreen({super.key, required this.bag});

  @override
  State<RfidBagDetailsScreen> createState() => _RfidBagDetailsScreenState();
}

class _RfidBagDetailsScreenState extends State<RfidBagDetailsScreen> {
  late BagStatus _currentStatus;

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.bag.status;
  }

  @override
  Widget build(BuildContext context) {
    final hospitalProvider = context.watch<HospitalProvider>();
    final bag = hospitalProvider.bags.firstWhere(
      (b) => b.bagId == widget.bag.bagId,
      orElse: () => widget.bag,
    );
    final isReal = hospitalProvider.isRealMode;

    // The server does not publish a hospital name for a bag, so the row is
    // hidden instead of showing a made-up centre.
    final showHospital = bag.hospitalName.isNotEmpty;

    // The server does not publish a bag volume either, so a server-backed
    // bag only shows how many units it is.
    final volumeUnits = bag.serverBacked
        ? '${bag.units} unit'
        : '${bag.units} Unit (~450 mL)';

    // The server only sends a temperature when the device reported one.
    final coldChainTemp = !bag.temperatureKnown
        ? '—'
        : (bag.serverBacked
            ? '${bag.currentTempCelsius.toStringAsFixed(1)}°C (from device)'
            : '${bag.currentTempCelsius}°C (Normal)');

    // A collection date derived from the expiry date is labelled as such.
    final collectionText = !bag.collectionDateKnown
        ? '—'
        : ('${DateFormat('dd MMM yyyy').format(bag.collectionDate)}'
            '${bag.collectionDateEstimated ? ' (estimated)' : ''}');

    final expiryText = bag.expiryKnown
        ? DateFormat('dd MMM yyyy').format(bag.expiryDate)
        : '—';

    return Scaffold(
      appBar: AppBar(
        title: Text('RFID Unit: ${bag.bagId}'),
        actions: [
          StatusBadge.fromBagStatus(bag.status),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // RFID Tag Identifier Banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primary.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.nfc_rounded,
                      color: AppColors.primary, size: 32),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'HARDWARE RFID TAG UID',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          bag.rfidTag,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Bag Details
            AnimatedCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Blood Bag Specifications',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const Divider(),
                  _Row('Blood Group', bag.bloodGroup),
                  _Row('Volume Units', volumeUnits),
                  if (showHospital) _Row('Hospital Center', bag.hospitalName),
                  _Row('Storage Location', bag.storageUnitName),
                  _Row('Cold-Chain Temp', coldChainTemp),
                  _Row('Collection Date', collectionText),
                  _Row('Expiration Date', expiryText),
                  if (bag.reservedForRequestId != null)
                    _Row('Reserved For Request', bag.reservedForRequestId!),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Status Transitions (Stored -> Reserved -> Issued -> Transferred -> Discarded)
            if (!isReal) ...[
              const Text(
                'Update Bag Provenance Status',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              AnimatedCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<BagStatus>(
                      value: _currentStatus,
                      decoration: const InputDecoration(
                        labelText: 'Select New Status',
                      ),
                      items: BagStatus.values.map((status) {
                        return DropdownMenuItem(
                          value: status,
                          child: Text(status.displayName),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _currentStatus = val;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    CustomButton(
                      text: 'Confirm Status Transition',
                      onPressed: () async {
                        try {
                          await hospitalProvider.updateBagStatus(
                            bag.bagId,
                            _currentStatus,
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Bag ${bag.bagId} updated to ${_currentStatus.displayName}'),
                              backgroundColor: AppColors.success,
                            ),
                          );
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(e.toString().replaceAll('Exception: ', '')),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ] else
              _deviceManagedCard(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  /// Real mode: the bag state belongs to the cold-chain device, so the app
  /// only reports it.
  Widget _deviceManagedCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Bag Provenance Status',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        AnimatedCard(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.devices_other_rounded,
                  color: AppColors.primary, size: 26),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Managed on the cold-chain device',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'The bag state is recorded on the cold-chain device and '
                      'cannot be changed from the app. It updates here once '
                      'the device reports its new state.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _Row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
