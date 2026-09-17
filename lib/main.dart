import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import 'config/stripe_config.dart';
import 'data/kiosk_config.dart';
import 'firebase_options.dart';
import 'screens/attract_screen.dart';
import 'screens/reception_screen.dart';
import 'services/kiosk_mode.dart';
import 'services/staff_claim_service.dart';
import 'state/kiosk_state.dart';
import 'state/terminal_mode.dart';
import 'theme/app_theme.dart';
import 'widgets/inactivity_guard.dart';
import 'widgets/staff_exit_gate.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (StripeConfig.isConfigured) {
    Stripe.publishableKey = StripeConfig.publishableKey;
    await Stripe.instance.applySettings();
  }
  try {
    // The terminal signs in anonymously (once — Firebase Auth persists the
    // session) so Firestore's `orders` rule, which requires *some*
    // authenticated caller, accepts tickets and status updates from it.
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously();
    }
    // Upgrades that same anonymous session with the `staff` custom claim it
    // needs to read every app order and advance their status — see
    // staff_claim_service.dart. No-ops once already granted.
    await StaffClaimService.ensureClaimed();
  } catch (_) {
    // Offline on first launch, or anonymous sign-in disabled on the
    // project — the terminal still runs; syncing (and, in Réception mode,
    // seeing orders) resumes once connectivity and the claim both succeed.
  }
  await enableKioskMode();
  runApp(const ClickCollectTerminalApp());
}

class ClickCollectTerminalApp extends StatefulWidget {
  /// [kioskState] and [initialMode] let tests inject a pre-seeded state
  /// (e.g. with a menu already set) and pick which mode to start in,
  /// instead of hitting the real Firestore backend / shared_preferences.
  const ClickCollectTerminalApp({super.key, KioskState? kioskState, TerminalMode? initialMode})
      : _injectedState = kioskState,
        _injectedMode = initialMode;

  final KioskState? _injectedState;
  final TerminalMode? _injectedMode;

  @override
  State<ClickCollectTerminalApp> createState() => _ClickCollectTerminalAppState();
}

class _ClickCollectTerminalAppState extends State<ClickCollectTerminalApp> {
  late final _kioskState = widget._injectedState ?? KioskState();
  TerminalMode? _mode;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final results = await Future.wait([
      _kioskState.load(),
      _kioskState.loadCatalog(),
      widget._injectedMode != null ? Future.value(widget._injectedMode) : TerminalModeStore.load(),
    ]);
    if (!mounted) return;
    setState(() {
      _mode = results[2] as TerminalMode;
      _loaded = true;
    });
  }

  void _handleInactivityTimeout() {
    // Only the Borne flow has a cart to abandon — in Réception mode
    // KioskState.mode/cart never get touched, so hasActiveSession stays
    // false and this is a no-op.
    if (!_kioskState.hasActiveSession) return;
    _kioskState.resetSession();
    navigatorKey.currentState?.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final home = !_loaded
        ? const _SplashScreen()
        : (_mode == TerminalMode.reception ? const ReceptionScreen() : const AttractScreen());

    return KioskStateScope(
      state: _kioskState,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Les Poulets de Mamie — Terminal',
        debugShowCheckedModeBanner: false,
        theme: buildKioskTheme(),
        home: home,
        builder: (context, child) {
          return StaffExitGate(
            navigatorKey: navigatorKey,
            child: InactivityGuard(
              timeout: KioskConfig.inactivityTimeout,
              onTimeout: _handleInactivityTimeout,
              child: child!,
            ),
          );
        },
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
