import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/hospital_provider.dart';
import '../../utils/app_colors.dart';
import '../../widgets/animated_card.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/mode_switch.dart';
import '../../widgets/rfid_scanner_overlay.dart';
import 'rfid_bag_details_screen.dart';

/// Interactive RFID / NFC scanner interface with simulated hardware triggers
class RfidScannerScreen extends StatefulWidget {
  const RfidScannerScreen({super.key});

  @override
  State<RfidScannerScreen> createState() => _RfidScannerScreenState();
}

class _RfidScannerScreenState extends State<RfidScannerScreen> {
  static const String _demoTag = 'RFID-9844-B-POS';

  final _manualTagController = TextEditingController(text: _demoTag);

  @override
  void dispose() {
    _manualTagController.dispose();
    super.dispose();
  }

  void _processScannedTag(String tag) async {
    final hospitalProvider = context.read<HospitalProvider>();
    final success = await hospitalProvider.scanRfidTag(tag);

    if (success && mounted && hospitalProvider.lastScannedBag != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('RFID Tag scanned successfully!'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              RfidBagDetailsScreen(bag: hospitalProvider.lastScannedBag!),
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(hospitalProvider.scanError ?? 'Tag not found'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hospitalProvider = context.watch<HospitalProvider>();
    final isReal = hospitalProvider.isRealMode;

    // The demo tag is meaningless on a real device, so start from an empty
    // field as soon as the app runs on server data. The reset is deferred to
    // the next frame because the text field must not be touched while the
    // tree is building.
    if (isReal && _manualTagController.text == _demoTag) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_manualTagController.text == _demoTag) {
          _manualTagController.clear();
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('RFID Blood Bag Scanner'),
        actions: [
          const ModeSwitch(),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Animated Scanner Viewfinder
            RfidScannerOverlay(
              isScanning: hospitalProvider.isScanning,
              onTriggerScan: () =>
                  _processScannedTag(_manualTagController.text.trim()),
            ),
            const SizedBox(height: 24),

            if (isReal)
              _deviceScanCard(context, hospitalProvider)
            else
              _demoProbeCard(context, hospitalProvider),
            const SizedBox(height: 20),

            if (isReal)
              _realBagChips(context, hospitalProvider)
            else
              _sampleTags(),
          ],
        ),
      ),
    );
  }

  /// Demo-only hardware probe.
  Widget _demoProbeCard(BuildContext context, HospitalProvider hospitalProvider) {
    return AnimatedCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Simulated RFID Hardware Probe',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Simulate hardware read of blood bag RFID tag:',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 14),
          CustomTextField(
            label: 'RFID Tag UID or Bag ID',
            controller: _manualTagController,
            prefixIcon: Icons.nfc_rounded,
          ),
          const SizedBox(height: 16),
          CustomButton(
            text: 'Simulate Hardware Tag Tap',
            icon: Icons.contactless_rounded,
            isLoading: hospitalProvider.isScanning,
            onPressed: () =>
                _processScannedTag(_manualTagController.text.trim()),
          ),
        ],
      ),
    );
  }

  /// Real mode: the bag is registered by tapping its tag on the cold-chain
  /// device, so the app asks the device to open its reader and then looks
  /// the tag up in the server's bag list.
  Widget _deviceScanCard(
      BuildContext context, HospitalProvider hospitalProvider) {
    return AnimatedCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Scan on the cold-chain device',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Ask the cold-chain device to open its RFID reader, then tap the '
            'bag on the device. The tag is then looked up in the server bag '
            'list.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 14),
          CustomTextField(
            label: 'RFID Tag UID or Bag ID',
            controller: _manualTagController,
            prefixIcon: Icons.nfc_rounded,
          ),
          const SizedBox(height: 16),
          CustomButton(
            text: 'Start RFID scan on device',
            icon: Icons.contactless_rounded,
            isLoading: hospitalProvider.isScanning,
            onPressed: () async {
              final ok = await hospitalProvider.sendCommand('START_RFID_SCAN');
              await hospitalProvider.refresh();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(ok
                      ? 'RFID scan requested on the cold-chain device'
                      : 'Could not reach the cold-chain device'),
                  backgroundColor: ok ? AppColors.success : AppColors.error,
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          CustomButton(
            text: 'Look up tag on server',
            icon: Icons.search_rounded,
            variant: ButtonVariant.outline,
            isLoading: hospitalProvider.isScanning,
            onPressed: () =>
                _processScannedTag(_manualTagController.text.trim()),
          ),
        ],
      ),
    );
  }

  /// Real mode: the bags the device reported, so staff can open one directly.
  Widget _realBagChips(
      BuildContext context, HospitalProvider hospitalProvider) {
    final bags = hospitalProvider.bags;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Bags reported by the device',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (bags.isEmpty)
          const Text(
            'No bags reported by the device yet.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: bags.map((bag) {
              return ActionChip(
                label: Text('${bag.rfidTag} (${bag.bloodGroup})'),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RfidBagDetailsScreen(bag: bag),
                    ),
                  );
                },
              );
            }).toList(),
          ),
      ],
    );
  }

  /// Demo-only sample tags.
  Widget _sampleTags() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Sample Pre-configured Blood Bag Tags',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(
              label: const Text('RFID-9844-B-POS (B+)'),
              onPressed: () {
                _manualTagController.text = 'RFID-9844-B-POS';
                _processScannedTag('RFID-9844-B-POS');
              },
            ),
            ActionChip(
              label: const Text('RFID-9842-O-POS (O+)'),
              onPressed: () {
                _manualTagController.text = 'RFID-9842-O-POS';
                _processScannedTag('RFID-9842-O-POS');
              },
            ),
            ActionChip(
              label: const Text('RFID-9843-O-NEG (O-)'),
              onPressed: () {
                _manualTagController.text = 'RFID-9843-O-NEG';
                _processScannedTag('RFID-9843-O-NEG');
              },
            ),
          ],
        ),
      ],
    );
  }
}
