import 'dart:async';

import 'package:flutter/material.dart';

import 'package:app_links/app_links.dart';
import 'package:provider/provider.dart';

import 'package:omi/backend/preferences.dart';
import 'package:omi/mobile/mobile_app.dart';
import 'package:omi/pages/settings/usage_page.dart';
import 'package:omi/pages/settings/wrapped_2025_page.dart';
import 'package:omi/providers/auth_provider.dart';
import 'package:omi/providers/home_provider.dart';
import 'package:omi/providers/message_provider.dart';
import 'package:omi/providers/people_provider.dart';
import 'package:omi/providers/usage_provider.dart';
import 'package:omi/providers/user_provider.dart';
import 'package:omi/services/notifications.dart';
import 'package:omi/utils/logger.dart';
import 'package:omi/utils/platform/platform_manager.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  Future<void> initDeepLinks() async {
    _appLinks = AppLinks();

    final initialUri = await _appLinks.getInitialLink();
    if (initialUri != null) {
      Logger.debug('onInitialAppLink: $initialUri');
      openAppLink(initialUri);
    }

    _linkSubscription = _appLinks.uriLinkStream.distinct().listen((uri) {
      Logger.debug('onAppLink: $uri');
      openAppLink(uri);
    });
  }

  void openAppLink(Uri uri) {
    if (uri.pathSegments.isEmpty) {
      Logger.debug('No path segments in URI: $uri');
      return;
    }

    if (uri.pathSegments.first == 'wrapped') {
      if (mounted) {
        PlatformManager.instance.mixpanel.track('Wrapped Opened From DeepLink');
        Navigator.of(context).push(MaterialPageRoute(builder: (context) => const Wrapped2025Page()));
      }
      return;
    }

    if (uri.pathSegments.first == 'unlimited') {
      if (mounted) {
        PlatformManager.instance.mixpanel.track('Plans Opened From DeepLink');
        Navigator.of(context).push(MaterialPageRoute(builder: (context) => const UsagePage(showUpgradeDialog: true)));
      }
      return;
    }

    Logger.debug('Unknown link: $uri');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initializeProviders();
      if (mounted) {
        initDeepLinks();
      }
    });
  }

  Future<void> _initializeProviders() async {
    if (!mounted) return;

    final isSignedIn = context.read<AuthenticationProvider>().isSignedIn();
    if (isSignedIn) {
      context.read<HomeProvider>().setupHasSpeakerProfile();
      context.read<HomeProvider>().setupUserPrimaryLanguage();
      context.read<UserProvider>().initialize();
      context.read<PeopleProvider>().initialize();

      try {
        await PlatformManager.instance.intercom.loginIdentifiedUser(SharedPreferencesUtil().uid);
      } catch (e) {
        Logger.debug('Failed to login to Intercom: $e');
      }

      if (!mounted) return;
      context.read<MessageProvider>().setMessagesFromCache();
      context.read<MessageProvider>().refreshMessages();
      context.read<UsageProvider>().fetchSubscription();
      NotificationService.instance.saveNotificationToken();
    } else {
      if (!PlatformManager.instance.isAnalyticsSupported) {
        await PlatformManager.instance.intercom.loginUnidentifiedUser();
      }
      if (!mounted) return;
    }

    PlatformManager.instance.intercom.setUserAttributes();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const MobileApp();
  }
}
