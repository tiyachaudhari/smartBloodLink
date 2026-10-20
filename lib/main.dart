import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'providers/theme_provider.dart';
import 'providers/app_mode_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/patient_provider.dart';
import 'providers/donor_provider.dart';
import 'providers/hospital_provider.dart';
import 'providers/ambulance_provider.dart';
import 'providers/admin_provider.dart';
import 'providers/notification_provider.dart';

import 'services/auth_service.dart';
import 'services/vitalink_session.dart';
import 'utils/app_theme.dart';
import 'screens/auth/splash_screen.dart';

/// Global navigator key — allows navigation from outside widget tree
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait orientations for consistent mobile UX
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Style system overlays to blend with Material 3 theming
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  // Restore a live hospital/admin session before the first frame so the
  // IoT providers can connect immediately when that role is active.
  await AuthService().bootstrap();

  // Restore the Demo/Real choice before the first frame too, so the app
  // opens in the mode the user last used.
  await AppModeProvider.instance.load();

  // Real mode needs a VitaLink hospital or admin session. Without one the
  // app opens in demo mode instead of showing a broken live view.
  if (AppModeProvider.instance.isReal &&
      !VitalinkSession.instance.canUseIot) {
    await AppModeProvider.instance.setMode(AppMode.demo);
  }

  runApp(const SmartBloodLinkApp());
}

class SmartBloodLinkApp extends StatelessWidget {
  const SmartBloodLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Theme — must be first so downstream providers can read theme data
        ChangeNotifierProvider(create: (_) => ThemeProvider()),

        // Demo / Real data source — shared by every role provider
        ChangeNotifierProvider.value(value: AppModeProvider.instance),

        // Auth — owns the current user session
        ChangeNotifierProvider(create: (_) => AuthProvider()),

        // Notification — cross-cutting, independent of role
        ChangeNotifierProvider(create: (_) => NotificationProvider()),

        // Role-specific ViewModels — lazily instantiated.
        // The hospital and admin view models follow the app-wide mode, so
        // they are wired through a proxy that pushes mode changes into them.
        ChangeNotifierProvider(create: (_) => PatientProvider()),
        ChangeNotifierProvider(create: (_) => DonorProvider()),
        ChangeNotifierProxyProvider<AppModeProvider, HospitalProvider>(
          create: (_) => HospitalProvider(),
          update: (_, mode, hospital) => hospital!..setMode(mode.mode),
        ),
        ChangeNotifierProvider(create: (_) => AmbulanceProvider()),
        ChangeNotifierProxyProvider<AppModeProvider, AdminProvider>(
          create: (_) => AdminProvider(),
          update: (_, mode, admin) => admin!..setMode(mode.mode),
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'Smart BloodLink',
            debugShowCheckedModeBanner: false,
            navigatorKey: navigatorKey,

            // Material 3 theme switching
            themeMode: themeProvider.themeMode,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,

            // Entry point — SplashScreen decides where to route based on auth state
            home: const SplashScreen(),

            // Global error boundary — prevents blank white screens on uncaught widget errors
            builder: (context, child) {
              return MediaQuery(
                // Prevent system font scaling from breaking layouts
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(
                    MediaQuery.of(context).textScaleFactor.clamp(0.8, 1.2),
                  ),
                ),
                child: child ?? const SizedBox.shrink(),
              );
            },
          );
        },
      ),
    );
  }
}
