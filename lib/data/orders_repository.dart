import 'package:cloud_firestore/cloud_firestore.dart' hide Order;

import 'kiosk_config.dart';
import '../models/incoming_order.dart';
import '../models/ticket.dart';

/// Lit et écrit la collection partagée `orders` — celle où l'application
/// mobile ET les bornes écrivent, pour que toutes les commandes arrivent au
/// même endroit. Deux sens :
///  - [submitTicket] : ce terminal en mode Borne enregistre sa propre
///    commande libre-service (`source: 'kiosk'`, comme la borne
///    click_collect_kiosk) ;
///  - [watchIncomingOrders] / [updateStatus] / [fetchOrdersBetween] : ce
///    terminal en mode Réception lit TOUTES les commandes (application +
///    bornes) et fait avancer leur statut. Nécessite le claim `staff` sur la
///    session anonyme du terminal — voir `staff_claim_service.dart` et
///    `firestore.rules` dans click_collect_app.
class OrdersRepository {
  const OrdersRepository._();

  static Future<void> submitTicket(Ticket ticket) {
    final data = {
      ...ticket.toJson(),
      'id': 'kiosk-${ticket.number}',
      'restaurantName': KioskConfig.restaurantLocationName,
      'fulfillmentDetail': null,
      'status': 'confirmed',
      'pointsEarned': 0,
      'userId': null,
      'source': 'kiosk',
    };
    return FirebaseFirestore.instance.collection('orders').add(data);
  }

  static List<IncomingOrder> _parse(QuerySnapshot<Map<String, dynamic>> snap) {
    final orders = <IncomingOrder>[];
    for (final d in snap.docs) {
      try {
        orders.add(IncomingOrder.fromFirestore(d.id, d.data()));
      } catch (_) {
        // Un document mal formé ne doit pas faire tomber tout l'écran.
      }
    }
    return orders;
  }

  /// Flux en direct de toutes les commandes (application ET bornes), les
  /// plus récentes d'abord — en cours (confirmed/ready) comme terminées.
  ///
  /// Avant : `where('source', isEqualTo: 'app')` — les commandes passées sur
  /// la borne (`source: 'kiosk'`) n'apparaissaient jamais en réception.
  /// Le tri sur `date` seul ne demande qu'un index simple (automatique).
  static Stream<List<IncomingOrder>> watchIncomingOrders() {
    return FirebaseFirestore.instance
        .collection('orders')
        .orderBy('date', descending: true)
        .limit(300)
        .snapshots()
        .map(_parse);
  }

  /// Toutes les commandes entre [start] (inclus) et [end] (exclu), pour le
  /// calendrier. `date` est une chaîne ISO-8601 : l'ordre alphabétique est
  /// l'ordre chronologique, la comparaison de chaînes suffit.
  static Future<List<IncomingOrder>> fetchOrdersBetween(DateTime start, DateTime end) async {
    final snap = await FirebaseFirestore.instance
        .collection('orders')
        .where('date', isGreaterThanOrEqualTo: start.toIso8601String())
        .where('date', isLessThan: end.toIso8601String())
        .orderBy('date')
        .get();
    return _parse(snap);
  }

  /// Fait avancer le statut d'une commande. `firestore.rules` ne l'autorise
  /// qu'à un terminal "staff", et seulement sur le champ `status`.
  static Future<void> updateStatus(String docId, IncomingOrderStatus status) {
    return FirebaseFirestore.instance.collection('orders').doc(docId).update({'status': status.name});
  }
}
