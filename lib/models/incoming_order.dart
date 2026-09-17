import 'cart_line.dart';

/// The status progression for an order placed through the mobile app, as
/// written by `click_collect_app`'s `Order.toJson()` and advanced from here.
enum IncomingOrderStatus { confirmed, ready, completed, unknown }

IncomingOrderStatus _parseStatus(String? raw) => switch (raw) {
      'confirmed' => IncomingOrderStatus.confirmed,
      'ready' => IncomingOrderStatus.ready,
      'completed' => IncomingOrderStatus.completed,
      _ => IncomingOrderStatus.unknown,
    };

/// The app's own `OrderMode` has 3 values (click & collect / delivery /
/// table service) — the terminal only needs to display the label, so it's
/// read as free text rather than importing the app's enum.
String _appModeLabel(String? raw) => switch (raw) {
      'clickCollect' => 'Click & Collect',
      'delivery' => 'Livraison',
      'tableService' => 'Service à table',
      _ => raw ?? '',
    };

/// One line of an incoming order, read back from Firestore. Shaped like the
/// app's `CartLine.toJson()`, reusing the terminal's own [CartLine] model
/// for display.
CartLine _lineFromAppJson(Map<String, dynamic> json) => CartLine(
      itemName: json['itemName'] as String? ?? json['name'] as String? ?? '?',
      sizeLabel: json['sizeLabel'] as String?,
      unitPrice: ((json['unitPrice'] ?? json['price']) as num?)?.toDouble() ?? 0,
      quantity: json['quantity'] as int? ?? 1,
      supplements: ((json['supplements'] as List<dynamic>?) ?? [])
          .map((s) => CartSupplement(
                name: (s as Map<String, dynamic>)['name'] as String? ?? '',
                price: (s['price'] as num?)?.toDouble() ?? 0,
              ))
          .toList(),
    );

/// An order placed through the mobile app, read live from the shared
/// Firestore `orders` collection by the reception screen. Read-only except
/// for [IncomingOrderStatus] — see `firestore.rules` in click_collect_app,
/// which only lets a claimed staff terminal touch the `status` field.
class IncomingOrder {
  IncomingOrder({
    required this.docId,
    required this.orderId,
    required this.date,
    required this.modeLabel,
    required this.lines,
    required this.total,
    required this.status,
    required this.paid,
    this.restaurantName,
    this.fulfillmentDetail,
    this.customerPhone,
    this.appliedRewardLabel,
  });

  /// The Firestore document id — needed to write status updates back.
  final String docId;
  final String orderId;
  final DateTime date;
  final String modeLabel;
  final List<CartLine> lines;
  final double total;
  final IncomingOrderStatus status;
  final bool paid;
  final String? restaurantName;
  final String? fulfillmentDetail;
  final String? customerPhone;

  /// Loyalty reward the customer redeemed for this order (e.g. "Un dessert
  /// offert"), if any — a free add-on to prepare alongside the order, not a
  /// discount already reflected in [total].
  final String? appliedRewardLabel;

  int get itemCount => lines.fold(0, (sum, l) => sum + l.quantity);

  factory IncomingOrder.fromFirestore(String docId, Map<String, dynamic> json) {
    final rawLines = (json['lines'] as List<dynamic>?) ?? [];
    return IncomingOrder(
      docId: docId,
      orderId: json['id'] as String? ?? docId,
      date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      modeLabel: _appModeLabel(json['mode'] as String?),
      lines: rawLines.map((l) => _lineFromAppJson(l as Map<String, dynamic>)).toList(),
      total: (json['total'] as num?)?.toDouble() ?? 0,
      status: _parseStatus(json['status'] as String?),
      paid: json['paid'] as bool? ?? false,
      restaurantName: json['restaurantName'] as String?,
      fulfillmentDetail: json['fulfillmentDetail'] as String?,
      customerPhone: json['customerPhone'] as String?,
      appliedRewardLabel: json['appliedRewardLabel'] as String?,
    );
  }
}
