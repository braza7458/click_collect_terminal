import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/kiosk_config.dart';

const _claimedPrefsKey = 'staff_claim_granted_v1';

/// Upgrades this terminal's anonymous Firebase Auth session with a
/// `staff: true` custom claim, by calling the `claimStaffTerminal` Cloud
/// Function with [KioskConfig.staffPin] as the setup code. This is what
/// lets `firestore.rules` allow the terminal to read every order (not just
/// ones it created itself) and advance their status — see
/// `orders_repository.dart` and the rules file in click_collect_app.
///
/// Idempotent and safe to call on every launch: does nothing once already
/// granted (tracked locally), and silently no-ops offline — the terminal
/// still starts, it just won't see incoming orders until connectivity and
/// this call both succeed.
class StaffClaimService {
  const StaffClaimService._();

  static Future<void> ensureClaimed() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_claimedPrefsKey) == true) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFunctions.instance
          .httpsCallable('claimStaffTerminal')
          .call<Map<String, dynamic>>({'setupCode': KioskConfig.staffPin});
      // Custom claims only appear in a fresh ID token.
      await user.getIdToken(true);
      await prefs.setBool(_claimedPrefsKey, true);
    } catch (_) {
      // Offline on first launch, or the function isn't deployed yet — try
      // again next launch rather than blocking startup.
    }
  }
}
