import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:click_collect_terminal/data/kiosk_config.dart';
import 'package:click_collect_terminal/data/menu_data.dart';
import 'package:click_collect_terminal/main.dart';
import 'package:click_collect_terminal/models/incoming_order.dart';
import 'package:click_collect_terminal/screens/reception_screen.dart';
import 'package:click_collect_terminal/theme/app_theme.dart';
import 'package:click_collect_terminal/state/kiosk_state.dart';
import 'package:click_collect_terminal/state/terminal_mode.dart';

/// The menu now lives in Firestore, which isn't reachable from a widget
/// test — inject a small fixture instead of hitting the network.
/// `loadCatalog()` fails silently offline and keeps this untouched.
KioskState _testKioskState() => KioskState()
  ..menuCategories = const [
    MenuCategory(
      title: 'Poulets rôtis',
      icon: IconIdentifier.chicken,
      items: [MenuItem(name: 'Le Poulet Rôti', price: 20.50)],
    ),
  ];

/// Taille d'écran réaliste pour une borne / un terminal en paysage.
Future<void> _useKioskScreen(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1280, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  setUp(() {
    // Pas d'animation d'ambiance infinie : pumpAndSettle ne finirait jamais.
    KioskConfig.ambientAnimations = false;
    // KioskState persists to shared_preferences on every change, and the
    // terminal's mode is also read from there — the test environment has
    // no real platform storage, so mock it empty.
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Réception mode shows the live-orders screen by default', (WidgetTester tester) async {
    await _useKioskScreen(tester);
    await tester.pumpWidget(ClickCollectTerminalApp(kioskState: _testKioskState()));
    await tester.pumpAndSettle();

    expect(find.text('Commandes en direct'), findsOneWidget);
    // No Firebase app is initialized in this test, so the stream fails to
    // even attach — the screen should show its offline fallback rather
    // than crash.
    expect(find.text('Connexion au serveur impossible.'), findsOneWidget);
  });

  testWidgets('Borne mode shows the restaurant name and a call to action', (WidgetTester tester) async {
    await _useKioskScreen(tester);
    await tester.pumpWidget(
      ClickCollectTerminalApp(kioskState: _testKioskState(), initialMode: TerminalMode.borne),
    );
    await tester.pumpAndSettle();

    expect(find.text('Les Poulets de Mamie'), findsOneWidget);
    expect(find.text('Touchez l\'écran pour commander'), findsOneWidget);
  });

  testWidgets('A customer can order a chicken and reach a ticket number', (WidgetTester tester) async {
    await _useKioskScreen(tester);
    await tester.pumpWidget(
      ClickCollectTerminalApp(kioskState: _testKioskState(), initialMode: TerminalMode.borne),
    );
    await tester.pumpAndSettle();

    // Attract -> order type.
    await tester.tap(find.text('Touchez l\'écran pour commander'));
    await tester.pumpAndSettle();

    // Order type -> menu.
    await tester.tap(find.text('Sur place'));
    await tester.pumpAndSettle();

    expect(find.text('Le Poulet Rôti'), findsOneWidget);

    // Add an item.
    await tester.tap(find.text('Le Poulet Rôti'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Ajouter ·'));
    await tester.pumpAndSettle();

    expect(find.text('Le Poulet Rôti'), findsWidgets); // in the cart panel too

    // Cart -> checkout -> pay at the register (no live Stripe backend in a
    // widget test, so this exercises the non-Stripe path).
    await tester.tap(find.text('Valider ma commande'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Payer en caisse'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Payer en caisse'));
    await tester.pumpAndSettle();

    expect(find.text('Commande enregistrée'), findsOneWidget);
    expect(find.text('1'), findsOneWidget); // first ticket of the day
  });

  testWidgets('Réception shows kiosk orders next to app orders, and opens the calendar', (WidgetTester tester) async {
    await _useKioskScreen(tester);
    final now = DateTime.now();
    final appOrder = IncomingOrder.fromFirestore('a', {
      'id': 'ABC12',
      'date': now.toIso8601String(),
      'mode': 'clickCollect',
      'lines': [
        {'itemName': 'Le Poulet Rôti', 'unitPrice': 20.5, 'quantity': 1},
      ],
      'total': 20.5,
      'status': 'confirmed',
      'source': 'app',
    });
    // Exactement ce qu'écrit la borne (OrdersRepository.submitTicket).
    final kioskOrder = IncomingOrder.fromFirestore('k', {
      'number': 12,
      'id': 'kiosk-12',
      'date': now.toIso8601String(),
      'mode': 'takeaway',
      'lines': [
        {'itemName': 'Tiramisu', 'sizeLabel': null, 'unitPrice': 3.5, 'quantity': 2, 'supplements': []},
      ],
      'total': 7.0,
      'customerPhone': null,
      'paid': false,
      'status': 'confirmed',
      'source': 'kiosk',
    });
    await tester.pumpWidget(
      KioskStateScope(
        state: _testKioskState(),
        child: MaterialApp(
          theme: buildKioskTheme(),
          home: ReceptionScreen(
            ordersStream: Stream.value([appOrder, kioskOrder]),
            calendarLoader: (start, end) async => [appOrder, kioskOrder],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('N° 12'), findsOneWidget); // commande borne
    expect(find.text('BORNE'), findsOneWidget);
    expect(find.text('À emporter · ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}'), findsOneWidget);
    expect(find.text('APPLI'), findsOneWidget);
    expect(find.text('Marquer prête'), findsNWidgets(2));

    await tester.tap(find.text('Commandes'));
    await tester.pumpAndSettle();
    expect(find.text('Historique des commandes'), findsOneWidget);
    expect(find.text('2 cdes'), findsOneWidget); // le jour d'aujourd'hui dans la grille
  });
}
