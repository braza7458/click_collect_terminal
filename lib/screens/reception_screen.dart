import 'dart:async';

import 'package:flutter/material.dart';

import '../data/kiosk_config.dart';
import '../data/menu_data.dart';
import '../data/orders_repository.dart';
import '../models/incoming_order.dart';
import '../services/alert_service.dart';
import '../state/terminal_mode.dart';
import '../theme/app_theme.dart';
import 'staff/staff_panel_screen.dart';
import 'staff/staff_pin_dialog.dart';

/// The screen a reception terminal shows all day: every order placed
/// through the mobile app, live, grouped by status, with a beep + flash
/// when a new one arrives. Staff advance an order confirmed → ready →
/// completed with a tap; completed orders move to the read-only
/// "Terminées" column rather than disappearing, so the day's full order
/// history stays visible (up to the last 300 app orders — see
/// [OrdersRepository.watchIncomingOrders]).
class ReceptionScreen extends StatefulWidget {
  const ReceptionScreen({super.key});

  @override
  State<ReceptionScreen> createState() => _ReceptionScreenState();
}

class _ReceptionScreenState extends State<ReceptionScreen> {
  StreamSubscription<List<IncomingOrder>>? _sub;
  List<IncomingOrder> _orders = [];
  Set<String> _knownDocIds = {};
  bool _sawFirstSnapshot = false;
  bool _alarmActive = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    try {
      _sub = OrdersRepository.watchIncomingOrders().listen(
        _handleSnapshot,
        onError: (_) => setState(() => _error = 'Connexion au serveur impossible.'),
      );
    } catch (_) {
      // Firestore unreachable at all (offline on first launch, Firebase not
      // yet initialized) — surface the same fallback rather than crash.
      _error = 'Connexion au serveur impossible.';
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    unawaited(AlertService.stopAlarm());
    super.dispose();
  }

  void _handleSnapshot(List<IncomingOrder> orders) {
    final ids = orders.map((o) => o.docId).toSet();
    if (_sawFirstSnapshot) {
      final arrived = ids.difference(_knownDocIds);
      if (arrived.isNotEmpty) _onNewOrders();
    }
    _sawFirstSnapshot = true;
    _knownDocIds = ids;
    setState(() {
      _orders = orders;
      _error = null;
    });
  }

  void _onNewOrders() {
    setState(() => _alarmActive = true);
    unawaited(AlertService.startAlarm(
      onAutoStop: () {
        if (mounted) setState(() => _alarmActive = false);
      },
    ));
  }

  void _dismissAlarm() {
    unawaited(AlertService.stopAlarm());
    setState(() => _alarmActive = false);
  }

  Future<void> _advance(IncomingOrder order, IncomingOrderStatus next) async {
    try {
      await OrdersRepository.updateStatus(order.docId, next);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Échec de la mise à jour — vérifiez la connexion.')),
        );
      }
    }
  }

  Future<void> _openStaffAccess(BuildContext context) async {
    final ok = await showStaffPinDialog(context);
    if (ok == true && context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const StaffPanelScreen(currentMode: TerminalMode.reception)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final confirmed = _orders.where((o) => o.status == IncomingOrderStatus.confirmed).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final ready = _orders.where((o) => o.status == IncomingOrderStatus.ready).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final completed = _orders.where((o) => o.status == IncomingOrderStatus.completed).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Flexible(child: Text('Commandes en direct', overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 12),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  KioskConfig.restaurantLocationName,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(color: AppColors.orange),
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Espace équipe',
            onPressed: () => _openStaffAccess(context),
            icon: const Icon(Icons.admin_panel_settings_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          SafeArea(
            child: _error != null
                ? Center(child: Text(_error!, style: textTheme.bodyLarge))
                : _orders.isEmpty
                    ? Center(
                        child: Text(
                          'Aucune commande pour le moment.\nElles apparaîtront ici dès qu\'un client commande sur l\'application.',
                          textAlign: TextAlign.center,
                          style: textTheme.bodyLarge,
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _OrderColumn(
                                title: 'Nouvelles (${confirmed.length})',
                                accent: AppColors.orange,
                                orders: confirmed,
                                actionLabel: 'Marquer prête',
                                onAction: (o) => _advance(o, IncomingOrderStatus.ready),
                              ),
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              child: _OrderColumn(
                                title: 'Prêtes (${ready.length})',
                                accent: AppColors.green,
                                orders: ready,
                                actionLabel: 'Récupérée',
                                onAction: (o) => _advance(o, IncomingOrderStatus.completed),
                              ),
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              child: _OrderColumn(
                                title: 'Terminées (${completed.length})',
                                accent: AppColors.creamMuted,
                                orders: completed,
                              ),
                            ),
                          ],
                        ),
                      ),
          ),
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: _alarmActive ? 1 : 0,
              duration: const Duration(milliseconds: 250),
              child: Container(color: AppColors.orange.withValues(alpha: 0.12)),
            ),
          ),
          if (_alarmActive)
            Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.orange,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    boxShadow: [BoxShadow(color: AppColors.orangeDark.withValues(alpha: 0.4), blurRadius: 20)],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.notifications_active, color: AppColors.charcoal),
                      const SizedBox(width: 10),
                      Text(
                        'Nouvelle commande !',
                        style: textTheme.titleMedium?.copyWith(color: AppColors.charcoal),
                      ),
                      const SizedBox(width: 14),
                      OutlinedButton(
                        onPressed: _dismissAlarm,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.charcoal,
                          side: const BorderSide(color: AppColors.charcoal),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        ),
                        child: const Text('Désactiver'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OrderColumn extends StatelessWidget {
  const _OrderColumn({
    required this.title,
    required this.accent,
    required this.orders,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final Color accent;
  final List<IncomingOrder> orders;
  final String? actionLabel;
  final void Function(IncomingOrder)? onAction;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: textTheme.titleLarge?.copyWith(color: accent)),
        const SizedBox(height: 12),
        Expanded(
          child: orders.isEmpty
              ? Center(child: Text('—', style: textTheme.bodyMedium))
              : ListView.separated(
                  itemCount: orders.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => _OrderCard(
                    order: orders[i],
                    accent: accent,
                    actionLabel: actionLabel,
                    onAction: onAction == null ? null : () => onAction!(orders[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.accent,
    this.actionLabel,
    this.onAction,
  });

  final IncomingOrder order;
  final Color accent;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hh = order.date.hour.toString().padLeft(2, '0');
    final mm = order.date.minute.toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.charcoalSoft,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${order.modeLabel} · $hh:$mm', style: textTheme.titleMedium),
              ),
              Text(formatPrice(order.total), style: textTheme.titleMedium?.copyWith(color: accent)),
            ],
          ),
          if (order.fulfillmentDetail != null && order.fulfillmentDetail!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(order.fulfillmentDetail!, style: textTheme.bodySmall),
          ],
          const SizedBox(height: 10),
          ...order.lines.map(
            (l) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${l.quantity} × ${l.itemName}${l.sizeLabel != null ? ' (${l.sizeLabel})' : ''}',
                style: textTheme.bodyMedium,
              ),
            ),
          ),
          if (order.appliedRewardLabel != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.card_giftcard, size: 15, color: AppColors.orange),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '+ ${order.appliedRewardLabel} (récompense fidélité)',
                      style: textTheme.bodySmall?.copyWith(color: AppColors.orange),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (order.customerPhone != null && order.customerPhone!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.phone_outlined, size: 16, color: AppColors.creamMuted),
                const SizedBox(width: 6),
                Text(order.customerPhone!, style: textTheme.bodySmall),
              ],
            ),
          ],
          if (onAction != null && actionLabel != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onAction,
                style: OutlinedButton.styleFrom(side: BorderSide(color: accent), foregroundColor: accent),
                child: Text(actionLabel!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
