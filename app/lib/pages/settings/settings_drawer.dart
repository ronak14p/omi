import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'package:omi/backend/preferences.dart';
import 'package:omi/core/app_shell.dart';
import 'package:omi/pages/conversations/sync_page.dart';
import 'package:omi/pages/settings/device_settings.dart';
import 'package:omi/pages/settings/notifications_settings_page.dart';
import 'package:omi/pages/settings/usage_page.dart';
import 'package:omi/providers/device_provider.dart';
import 'package:omi/providers/usage_provider.dart';
import 'package:omi/services/auth_service.dart';
import 'package:omi/utils/analytics/mixpanel.dart';
import 'package:omi/utils/l10n_extensions.dart';
import 'package:omi/utils/platform/platform_service.dart';

class SettingsDrawer extends StatefulWidget {
  const SettingsDrawer({super.key});

  @override
  State<SettingsDrawer> createState() => _SettingsDrawerState();

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const SettingsDrawer(),
    );
  }
}

class _SettingsDrawerState extends State<SettingsDrawer> {
  String? version;
  String? buildVersion;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      version = packageInfo.version;
      buildVersion = packageInfo.buildNumber;
    });
  }

  Widget _item({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color iconColor = Colors.white,
    Color textColor = Colors.white,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 1),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              FaIcon(icon, color: iconColor, size: 18),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(color: textColor, fontSize: 16),
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF3C3C43), size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _logout() async {
    MixpanelManager().logout();
    await AuthService.instance.signOut();
    SharedPreferencesUtil().onboardingCompleted = false;

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const AppShell()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayText = buildVersion != null ? '${version ?? ''} ($buildVersion)' : (version ?? '');

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0D0D10),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade700,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      context.l10n.settings,
                      style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white70),
                    )
                  ],
                ),
                const SizedBox(height: 12),
                _item(
                  icon: FontAwesomeIcons.bell,
                  title: context.l10n.notifications,
                  onTap: () {
                    MixpanelManager().pageOpened('Notification Settings');
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsSettingsPage()));
                  },
                ),
                _item(
                  icon: FontAwesomeIcons.mobileScreenButton,
                  title: context.l10n.device,
                  onTap: () {
                    MixpanelManager().pageOpened('Device Settings');
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DeviceSettings()));
                  },
                ),
                _item(
                  icon: FontAwesomeIcons.cloudArrowUp,
                  title: context.l10n.sync,
                  onTap: () {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SyncPage()));
                  },
                ),
                _item(
                  icon: FontAwesomeIcons.chartLine,
                  title: context.l10n.usage,
                  onTap: () async {
                    final usageProvider = context.read<UsageProvider>();
                    await usageProvider.fetchSubscription();
                    if (!mounted) return;
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UsagePage()));
                  },
                ),
                _item(
                  icon: FontAwesomeIcons.rightFromBracket,
                  iconColor: Colors.redAccent,
                  textColor: Colors.redAccent,
                  title: context.l10n.logout,
                  onTap: _logout,
                ),
                const SizedBox(height: 20),
                if (Platform.isIOS || Platform.isAndroid)
                  Center(
                    child: GestureDetector(
                      onTap: () => Clipboard.setData(ClipboardData(text: displayText)),
                      child: Text(
                        displayText,
                        style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 12),
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                if (!PlatformService.isDesktop)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      context.read<DeviceProvider>().pairedDevice?.name ?? '',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
