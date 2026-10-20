import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_mode_provider.dart';
import '../providers/auth_provider.dart';
import '../services/vitalink_session.dart';
import '../utils/app_colors.dart';
import '../utils/constants.dart';
import 'vitalink_connect_dialog.dart';

/// Compact Demo / Real switch for the top-right corner of the app bar.
///
/// Tapping it flips the app-wide data source. Real mode needs a VitaLink
/// hospital or admin session, so the switch asks for one when it is missing.
class ModeSwitch extends StatelessWidget {
  const ModeSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    final isReal = context.watch<AppModeProvider>().isReal;
    final color = isReal ? AppColors.success : Colors.grey;

    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Tooltip(
        message: isReal
            ? 'Real mode: cold-chain data comes from the VitaLink server'
            : 'Demo mode: every module is simulated on this device',
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _toggle(context, isReal),
          onLongPress: () => _showDetails(context, isReal),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: color.withOpacity(0.14),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withOpacity(0.55)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isReal ? Icons.cloud_done_rounded : Icons.science_rounded,
                  size: 14,
                  color: color,
                ),
                const SizedBox(width: 4),
                Text(
                  isReal ? 'REAL' : 'DEMO',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: color,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(width: 3),
                Icon(Icons.swap_horiz_rounded, size: 14, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggle(BuildContext context, bool isReal) async {
    final modeProvider = context.read<AppModeProvider>();
    if (isReal) {
      await modeProvider.setMode(AppMode.demo);
      return;
    }

    final role = context.read<AuthProvider>().currentRole;
    if (role != UserRole.hospital && role != UserRole.admin) {
      await _showBlocked(context, role);
      return;
    }

    if (!VitalinkSession.instance.canUseIot) {
      final connected = await VitalinkConnectDialog.show(context, role);
      if (!connected) return;
    }

    await modeProvider.setMode(AppMode.real);
  }

  /// Explains what is live and what stays simulated in the current mode.
  Future<void> _showDetails(BuildContext context, bool isReal) async {
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isReal ? Icons.cloud_done_rounded : Icons.science_rounded,
                  color: isReal ? AppColors.success : Colors.grey,
                ),
                const SizedBox(width: 10),
                Text(
                  isReal ? 'Real mode' : 'Demo mode',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (isReal) ...[
              const Text(
                'Live from the VitaLink server',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              const Text(
                'Devices · temperature · weight · bag count · security · RFID · '
                'Wi-Fi · firmware · thresholds · temperature history · bag list '
                'and expiry · cold-chain alerts · alarm policy · device '
                'commands · admin device list · admin audit trail',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 14),
              const Text(
                'Still simulated',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              const Text(
                'The server does not publish these yet, so they keep their '
                'bundled demo values: blood requests · donors and rewards · '
                'donation and request reports · ambulance trips · the admin '
                'user list · notifications',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ] else ...[
              const Text(
                'Everything is simulated on this device',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              const Text(
                'No server is contacted. The cold-chain readings, the bag '
                'inventory and every other module come from the bundled '
                'simulation, so the app works with the fridge and the server '
                'switched off.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            const SizedBox(height: 16),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showBlocked(BuildContext context, UserRole role) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.lock_outline_rounded, color: AppColors.warning),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Real mode is not available for this role',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: const Text(
          'The VitaLink server only serves the cold-chain data to hospital '
          'and admin accounts. This account stays in demo mode, where every '
          'module is simulated on the device.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}
