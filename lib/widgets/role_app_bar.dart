import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_mode_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/hospital_provider.dart';
import '../providers/notification_provider.dart';
import '../providers/theme_provider.dart';
import '../screens/common/profile_screen.dart';
import '../utils/app_colors.dart';
import 'mode_switch.dart';

/// Standard app bar across role dashboards with the data-source switch,
/// theme switcher, notifications, and profile
class RoleAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool showBackButton;

  const RoleAppBar({
    super.key,
    required this.title,
    this.showBackButton = false,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final notificationProvider = context.watch<NotificationProvider>();
    final role = authProvider.currentRole;
    final unread = _unreadCount(context, notificationProvider);

    return AppBar(
      automaticallyImplyLeading: showBackButton,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.bloodtype_rounded,
              color: AppColors.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  role.displayName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        // Demo / Real data source switch — always in the top-right corner
        const ModeSwitch(),

        // Dark / Light Mode Switcher
        IconButton(
          tooltip: 'Toggle Theme',
          icon: Icon(
            themeProvider.isDarkMode
                ? Icons.light_mode_rounded
                : Icons.dark_mode_rounded,
            size: 22,
          ),
          onPressed: () => themeProvider.toggleTheme(),
        ),

        // Notifications with live badge
        Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              tooltip: 'Notifications',
              icon: const Icon(Icons.notifications_none_rounded, size: 24),
              onPressed: () {
                _showNotificationsModal(context, notificationProvider);
              },
            ),
            if (unread > 0)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$unread',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),

        // Profile Avatar
        IconButton(
          tooltip: 'User Profile',
          icon: CircleAvatar(
            radius: 15,
            backgroundColor: AppColors.primary.withOpacity(0.15),
            child: Text(
              authProvider.currentUser?.name.isNotEmpty == true
                  ? authProvider.currentUser!.name.substring(0, 1)
                  : 'U',
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            );
          },
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  /// Number shown on the notification badge.
  ///
  /// Real mode shows the server alerts, demo mode the bundled notifications.
  int _unreadCount(BuildContext context, NotificationProvider notifProvider) {
    if (context.watch<AppModeProvider>().isReal) {
      return context.watch<HospitalProvider>().activeAlerts.length;
    }
    return notifProvider.unreadCount;
  }

  void _showNotificationsModal(
    BuildContext context,
    NotificationProvider notifProvider,
  ) {
    final isReal = context.read<AppModeProvider>().isReal;
    if (!isReal) notifProvider.markAllAsRead();
    final alerts = isReal
        ? context.read<HospitalProvider>().activeAlerts
        : const <dynamic>[];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          height: MediaQuery.of(context).size.height * 0.65,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Notifications & Alerts',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              if (isReal)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Live alerts raised by the VitaLink server',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
              const Divider(),
              Expanded(
                child: isReal
                    ? _alertsList(context, alerts)
                    : _notificationsList(context, notifProvider),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Server alerts, shown while the app is in real mode.
  Widget _alertsList(BuildContext context, List<dynamic> alerts) {
    if (alerts.isEmpty) {
      return const Center(child: Text('No active server alerts'));
    }
    return ListView.separated(
      itemCount: alerts.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final alert = alerts[index];
        return ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (alert.isCritical ? AppColors.error : AppColors.warning)
                  .withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              alert.isCritical
                  ? Icons.warning_rounded
                  : Icons.thermostat_rounded,
              color: alert.isCritical ? AppColors.error : AppColors.warning,
              size: 20,
            ),
          ),
          title: Text(
            alert.type.replaceAll('_', ' '),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(alert.message, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 4),
              Text(
                alert.openedAt == null
                    ? ''
                    : '${alert.openedAt!.hour.toString().padLeft(2, '0')}:'
                        '${alert.openedAt!.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Bundled notifications, shown while the app is in demo mode.
  Widget _notificationsList(
      BuildContext context, NotificationProvider notifProvider) {
    if (notifProvider.notifications.isEmpty) {
      return const Center(child: Text('No active notifications'));
    }
    return ListView.separated(
      itemCount: notifProvider.notifications.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = notifProvider.notifications[index];
        return ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.campaign_rounded,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          title: Text(
            item.title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(item.body, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 4),
              Text(
                '${item.timestamp.hour.toString().padLeft(2, '0')}:'
                '${item.timestamp.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          ),
        );
      },
    );
  }
}
