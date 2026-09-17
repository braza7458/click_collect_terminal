import 'package:shared_preferences/shared_preferences.dart';

const _terminalModePrefsKey = 'terminal_mode_v1';

/// What this physical terminal is doing right now.
///  - [reception]: staff screen showing orders placed through the mobile
///    app live, as they arrive — the primary use case.
///  - [borne]: the original self-service ordering flow (attract screen →
///    menu → cart → ticket), kept as-is for walk-in customers.
enum TerminalMode { reception, borne }

/// Persists which mode this terminal last opened in, so it comes back up
/// the same way after a restart instead of always defaulting to one.
class TerminalModeStore {
  const TerminalModeStore._();

  static Future<TerminalMode> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_terminalModePrefsKey);
    return raw == 'borne' ? TerminalMode.borne : TerminalMode.reception;
  }

  static Future<void> save(TerminalMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_terminalModePrefsKey, mode.name);
  }
}
