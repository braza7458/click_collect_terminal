import 'package:cloud_firestore/cloud_firestore.dart' hide Order;

import 'kiosk_config.dart';
import '../models/incoming_order.dart';
import '../models/ticket.dart';

/// Reads and writes the shared `orders` collection — the same one the
/// mobile app writes to, so every order placed anywhere ends up in one
/// place. Two directions:
///  - [submitTicket]: this terminal, in Borne mode, writing its own
///    self-service order (`source: 'kiosk'`).
///  - [watchIncomingOrders] / [updateStatus]: this terminal, in Réception
///    mode, reading orders placed through the app (`source: 'app'`) and
///    advancing their status. Requires the terminal's anonymous session to
///    hold the `staff` custom claim — see `staff_claim_service.dart` and
///    `firestore.rules` in click_collect_app.
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

  /// Live feed of orders placed through the mobile app, most recent first —
  /// covers active orders (confirmed/ready) as well as history (completed);
  /// see [IncomingOrderStatus] and ReceptionScreen's three columns.
  static Stream<List<IncomingOrder>> watchIncomingOrders() {
    return FirebaseFirestore.instance
        .collection('orders')
        .where('source', isEqualTo: 'app')
        .orderBy('date', descending: true)
        .limit(300)
        .snapshots()
        .map((snap) => snap.docs.map((d) => IncomingOrder.fromFirestore(d.id, d.data())).toList());
  }

  /// Advances an app order's status. `firestore.rules` only allows this for
  /// a claimed staff terminal, and only touches the `status` field.
  static Future<void> updateStatus(String docId, IncomingOrderStatus status) {
    return FirebaseFirestore.instance.collection('orders').doc(docId).update({'status': status.name});
  }
}
