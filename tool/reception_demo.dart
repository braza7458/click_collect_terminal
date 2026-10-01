// Démo visuelle de l'écran de réception et du calendrier, SANS Firebase :
// commandes fictives (application + borne) injectées en mémoire. Ne touche
// à aucune donnée réelle. Lancer avec :
//
//   flutter run -d chrome -t tool/reception_demo.dart
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'package:click_collect_terminal/models/incoming_order.dart';
import 'package:click_collect_terminal/screens/reception_screen.dart';
import 'package:click_collect_terminal/state/kiosk_state.dart';
import 'package:click_collect_terminal/theme/app_theme.dart';

IncomingOrder _order(int i, DateTime date, String status, {bool kiosk = false}) {
  final rng = Random(i);
  final lines = [
    {'itemName': 'Le Poulet Rôti', 'unitPrice': 20.5, 'quantity': 1},
    {'itemName': 'Crousty Cheddar', 'sizeLabel': 'L', 'unitPrice': 10.0, 'quantity': 2, 'supplements': [{'name': 'Oignons crispy', 'price': 0.5}]},
    {'itemName': 'Barquette grande', 'unitPrice': 5.5, 'quantity': 1},
    {'itemName': 'Tiramisu', 'unitPrice': 3.5, 'quantity': 2},
  ]..shuffle(rng);
  final picked = lines.take(1 + rng.nextInt(3)).toList();
  final total = picked.fold<double>(0, (s, l) => s + (l['unitPrice'] as double) * (l['quantity'] as int));
  return IncomingOrder.fromFirestore('doc$i', {
    'id': kiosk ? 'kiosk-$i' : 'MF${(i * 7919).toRadixString(36).toUpperCase()}',
    'number': kiosk ? i : null,
    'date': date.toIso8601String(),
    'mode': kiosk ? (i.isEven ? 'dineIn' : 'takeaway') : 'clickCollect',
    'lines': picked,
    'total': total,
    'status': status,
    'paid': i % 3 == 0,
    'source': kiosk ? 'kiosk' : 'app',
    'customerPhone': kiosk ? null : '06 12 34 56 7$i',
    'fulfillmentDetail': kiosk ? null : 'Retrait · Aujourd\'hui · 19:${(i * 5 % 60).toString().padLeft(2, '0')}',
    'appliedRewardLabel': i == 2 ? 'Un dessert offert' : null,
  });
}

void main() {
  final now = DateTime.now();
  final live = [
    _order(1, now.subtract(const Duration(minutes: 3)), 'confirmed'),
    _order(2, now.subtract(const Duration(minutes: 14)), 'confirmed'),
    _order(7, now.subtract(const Duration(minutes: 27)), 'confirmed', kiosk: true),
    _order(4, now.subtract(const Duration(minutes: 9)), 'ready', kiosk: true),
    _order(5, now.subtract(const Duration(minutes: 40)), 'completed'),
    _order(6, now.subtract(const Duration(minutes: 55)), 'completed', kiosk: true),
  ];
  final history = <IncomingOrder>[
    for (var d = 1; d <= 28; d++)
      for (var k = 0; k < (d * 7) % 9; k++)
        _order(d * 10 + k, DateTime(now.year, now.month, d, 11 + k % 9, (k * 13) % 60), 'completed', kiosk: k.isOdd),
  ];
  runApp(
    KioskStateScope(
      state: KioskState(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildKioskTheme(),
        scrollBehavior: const KioskScrollBehavior(),
        home: ReceptionScreen(
          ordersStream: Stream.value(live),
          calendarLoader: (start, end) async =>
              history.where((o) => !o.date.isBefore(start) && o.date.isBefore(end)).toList(),
        ),
      ),
    ),
  );
}
