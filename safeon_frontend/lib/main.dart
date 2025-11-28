import 'package:flutter/material.dart';

import 'models/user_profile.dart';
import 'models/user_session.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/safeon_api.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.initialize();
  runApp(const SafeOnApp());
}

class SafeOnApp extends StatefulWidget {
  const SafeOnApp({super.key});

  @override
  State<SafeOnApp> createState() => _SafeOnAppState();
}

class _SafeOnAppState extends State<SafeOnApp> {
  final SafeOnApiClient _apiClient = SafeOnApiClient();
  bool _completedOnboarding = false;
  UserSession? _session;
  String _cachedEmail = 'Godten@example.com';
  String _cachedNickname = 'Young';
  String _cachedPassword = '12345678';

  void _completeOnboarding() {
    setState(() => _completedOnboarding = true);
  }

  void _handleLoginSuccess(UserSession session, String password) {
    setState(() {
      _session = session;
      _cachedEmail = session.profile.email;
      _cachedPassword = password;
      _cachedNickname = session.profile.name;
    });
  }

  void _handleProfileUpdated(UserProfile updatedProfile) {
    if (_session == null) return;
    setState(() {
      _session = _session!.copyWith(profile: updatedProfile);
      _cachedNickname = updatedProfile.name;
    });
  }

  void _handleLogout() {
    setState(() {
      _session = null;
      _completedOnboarding = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SafeOn',
      debugShowCheckedModeBanner: false,
      theme: buildSafeOnTheme(),
      home: _completedOnboarding
          ? _session != null
              ? DashboardScreen(
                  onLogout: _handleLogout,
                  onProfileUpdated: _handleProfileUpdated,
                  session: _session!,
                  apiClient: _apiClient,
                )
              : LoginScreen(
                  onLoginSuccess: _handleLoginSuccess,
                  apiClient: _apiClient,
                  initialEmail: _cachedEmail,
                  initialPassword: _cachedPassword,
                  initialNickname: _cachedNickname,
                )
          : OnboardingScreen(onContinue: _completeOnboarding),
    );
  }
}
