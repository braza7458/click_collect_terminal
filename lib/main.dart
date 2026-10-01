import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import 'config/stripe_config.dart';
import 'data/kiosk_config.dart';
import 'firebase_options.dart';
import 'screens/attract_screen.dart';
import 'screens/reception_screen.dart';
import 'screens/staff/staff_pin_dialog.dart';
import 'services/alert_service.dart';
import 'services/kiosk_mode.dart';
import 'services/staff_claim_service.dart';
import 'state/kiosk_state.dart';
import 'state/terminal_mode.dart';
import 'theme/app_theme.dart';
import 'widgets/inactivity_guard.dart';
import 'widgets/staff_exit_gate.dart';
import 'widgets/ui.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Sur le web (version de test en ligne), le PaymentSheet natif de Stripe
  // n'existe pas : pas d'initialisation, et le paiement se fait sur place.
  if (StripeConfig.isConfigured && !kIsWeb) {
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
    // Sur le web, le terminal est une simple page en ligne : pas de droits
    // "staff" automatiques, ils sont demandés avec le code équipe à
    // l'ouverture (voir _WebReceptionGate).
    if (!kIsWeb) await StaffClaimService.ensureClaimed();
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

  /// Version web : la réception ne s'ouvre qu'après le code équipe (droits
  /// staff + son autorisé par le navigateur).
  bool _webUnlocked = false;

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
        : (_mode == TerminalMode.reception
            ? (kIsWeb && !_webUnlocked ? _WebReceptionGate(onUnlocked: () => setState(() => _webUnlocked = true)) : const ReceptionScreen())
            : const AttractScreen());

    return KioskStateScope(
      state: _kioskState,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Les Poulets de Mamie — Terminal',
        debugShowCheckedModeBanner: false,
        theme: buildKioskTheme(),
        scrollBehavior: const KioskScrollBehavior(),
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
      body: Center(child: BrandSeal(size: 140)),
    );
  }
}

/// Écran d'accueil de la réception en version web. Deux raisons :
///  - les droits "staff" (lire toutes les commandes) ne sont accordés
///    qu'après le code équipe, pas à n'importe qui ouvrant le lien ;
///  - les navigateurs bloquent le son tant que la page n'a pas été touchée :
///    l'appui sur ce bouton autorise le bip des nouvelles commandes (un bip
///    de test est joué pour le confirmer).
class _WebReceptionGate extends StatefulWidget {
  const _WebReceptionGate({required this.onUnlocked});

  final VoidCallback onUnlocked;

  @override
  State<_WebReceptionGate> createState() => _WebReceptionGateState();
}

class _WebReceptionGateState extends State<_WebReceptionGate> {
  bool _busy = false;
  String? _error;

  Future<void> _start() async {
    final ok = await showStaffPinDialog(context, title: 'Code équipe');
    if (ok != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    // Bip de test (déverrouille le son dans le navigateur).
    unawaited(AlertService.startAlarm());
    Future.delayed(const Duration(milliseconds: 1200), AlertService.stopAlarm);
    final claimed = await StaffClaimService.ensureClaimed();
    if (!mounted) return;
    if (claimed) {
      widget.onUnlocked();
    } else {
      setState(() {
        _busy = false;
        _error = 'Connexion au serveur impossible — vérifiez internet et réessayez.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BrandSeal(size: 120),
                const SizedBox(height: 28),
                Text('Réception des commandes', style: textTheme.headlineLarge, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                Text(
                  "Toutes les commandes de l'application et des bornes s'afficheront ici en direct, avec un bip à "
                  'chaque nouvelle commande. Gardez cette page ouverte et le son du navigateur activé.',
                  style: textTheme.bodyLarge?.copyWith(color: AppColors.creamMuted),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                GlowButton(
                  icon: Icons.volume_up_rounded,
                  label: 'Démarrer la réception',
                  busy: _busy,
                  onPressed: _start,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: textTheme.bodyMedium?.copyWith(color: AppColors.red), textAlign: TextAlign.center),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
