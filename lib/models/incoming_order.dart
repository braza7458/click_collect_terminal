import 'cart_line.dart';

/// Où en est une commande — écrit par l'application mobile ou la borne
/// (`status: 'confirmed'` à la création) et avancé depuis ce terminal.
enum IncomingOrderStatus { confirmed, ready, completed, unknown }

IncomingOrderStatus _parseStatus(String? raw) => switch (raw) {
      'confirmed' => IncomingOrderStatus.confirmed,
      'ready' => IncomingOrderStatus.ready,
      'completed' => IncomingOrderStatus.completed,
      _ => IncomingOrderStatus.unknown,
    };

/// D'où vient la commande.
enum OrderSource { app, kiosk }

/// Libellé du mode, quelle que soit la source : l'application écrit
/// clickCollect / delivery / tableService, la borne dineIn / takeaway.
String _modeLabel(String? raw) => switch (raw) {
      'clickCollect' => 'Click & Collect',
      'delivery' => 'Livraison',
      'tableService' => 'Service à table',
      'dineIn' => 'Sur place',
      'takeaway' => 'À emporter',
      _ => raw ?? '',
    };

/// Une ligne de commande relue depuis Firestore. Même forme pour l'app
/// (`CartLine.toJson()`) et la borne (`Ticket.toJson()`).
CartLine _lineFromJson(Map<String, dynamic> json) => CartLine(
      itemName: json['itemName'] as String? ?? json['name'] as String? ?? '?',
      sizeLabel: json['sizeLabel'] as String?,
      unitPrice: ((json['unitPrice'] ?? json['price']) as num?)?.toDouble() ?? 0,
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      supplements: ((json['supplements'] as List<dynamic>?) ?? [])
          .map((s) {
            final map = Map<String, dynamic>.from(s as Map);
            return CartSupplement(
              name: map['name'] as String? ?? '',
              price: (map['price'] as num?)?.toDouble() ?? 0,
            );
          })
          .toList(),
    );

/// Une commande de la collection partagée `orders` — passée sur
/// l'application mobile OU sur une borne — lue en direct par l'écran de
/// réception. Lecture seule, sauf [IncomingOrderStatus] : `firestore.rules`
/// (click_collect_app) ne laisse un terminal "staff" toucher qu'à `status`.
class IncomingOrder {
  IncomingOrder({
    required this.docId,
    required this.orderId,
    required this.date,
    required this.mode,
    required this.modeLabel,
    required this.lines,
    required this.total,
    required this.status,
    required this.paid,
    required this.source,
    this.ticketNumber,
    this.restaurantName,
    this.fulfillmentDetail,
    this.customerPhone,
    this.appliedRewardLabel,
    this.customerName,
    this.pointsEarned = 0,
  });

  /// Identifiant du document Firestore — pour écrire les changements de statut.
  final String docId;
  final String orderId;
  final DateTime date;

  /// Valeur brute du mode (clickCollect, dineIn…).
  final String mode;
  final String modeLabel;
  final List<CartLine> lines;
  final double total;
  final IncomingOrderStatus status;
  final bool paid;
  final OrderSource source;

  /// Numéro de ticket de la borne (affiché au client sur son ticket).
  final int? ticketNumber;
  final String? restaurantName;
  final String? fulfillmentDetail;
  final String? customerPhone;

  /// Récompense fidélité échangée pour cette commande ("Un dessert
  /// offert"…) : à préparer en plus, ce n'est pas une remise.
  final String? appliedRewardLabel;

  /// Pseudo du compte fidélité (app ou borne), si le client en a un — le
  /// même compte sur les 3 applications.
  final String? customerName;
  final int pointsEarned;

  int get itemCount => lines.fold(0, (sum, l) => sum + l.quantity);

  /// Ce que l'équipe annonce au comptoir : "N° 12" pour la borne, "#K3F9…"
  /// (fin de l'identifiant) pour l'application.
  String get displayNumber {
    if (ticketNumber != null) return 'N° $ticketNumber';
    final id = orderId.replaceFirst('kiosk-', '');
    return '#${id.length > 5 ? id.substring(id.length - 5) : id}';
  }

  factory IncomingOrder.fromFirestore(String docId, Map<String, dynamic> json) {
    final rawLines = (json['lines'] as List<dynamic>?) ?? [];
    final source = json['source'] == 'kiosk' ? OrderSource.kiosk : OrderSource.app;
    final mode = json['mode'] as String? ?? '';
    return IncomingOrder(
      docId: docId,
      orderId: json['id'] as String? ?? docId,
      date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      mode: mode,
      modeLabel: _modeLabel(mode),
      lines: rawLines.map((l) => _lineFromJson(Map<String, dynamic>.from(l as Map))).toList(),
      total: (json['total'] as num?)?.toDouble() ?? 0,
      status: _parseStatus(json['status'] as String?),
      paid: json['paid'] as bool? ?? false,
      source: source,
      ticketNumber: (json['number'] as num?)?.toInt(),
      restaurantName: json['restaurantName'] as String?,
      fulfillmentDetail: json['fulfillmentDetail'] as String?,
      customerPhone: json['customerPhone'] as String?,
      appliedRewardLabel: json['appliedRewardLabel'] as String?,
      customerName: json['customerName'] as String?,
      pointsEarned: (json['pointsEarned'] as num?)?.toInt() ?? 0,
    );
  }
}
