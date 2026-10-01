import 'dart:async';

import 'package:flutter/material.dart';

import '../data/kiosk_config.dart';
import '../data/menu_data.dart';
import '../data/orders_repository.dart';
import '../models/incoming_order.dart';
import '../services/alert_service.dart';
import '../state/terminal_mode.dart';
import '../theme/app_theme.dart';
import '../widgets/order_card.dart';
import '../widgets/ui.dart';
import 'order_calendar_screen.dart';
import 'staff/staff_panel_screen.dart';
import 'staff/staff_pin_dialog.dart';

/// L'écran que le terminal affiche toute la journée en cuisine : TOUTES les
/// commandes (application mobile ET bornes), en direct, rangées par statut,
/// avec une alarme quand une nouvelle arrive. L'équipe fait avancer une
/// commande Nouvelle → Prête → Terminée d'un geste ; les terminées restent
/// visibles dans leur colonne (300 dernières commandes, voir
/// [OrdersRepository.watchIncomingOrders]). Le bouton "Commandes" ouvre le
/// calendrier de l'historique.
class ReceptionScreen extends StatefulWidget {
  const ReceptionScreen({super.key, this.ordersStream, this.calendarLoader});

  /// Flux de commandes à afficher — par défaut le flux Firestore en direct.
  /// Injectable pour les tests et la démo (tool/reception_demo.dart).
  final Stream<List<IncomingOrder>>? ordersStream;

  /// Transmis au calendrier (voir [OrderCalendarScreen.loader]).
  final OrdersLoader? calendarLoader;

  @override
  State<ReceptionScreen> createState() => _ReceptionScreenState();
}

class _ReceptionScreenState extends State<ReceptionScreen> {
  StreamSubscription<List<IncomingOrder>>? _sub;
  Timer? _clock;
  DateTime _now = DateTime.now();
  List<IncomingOrder> _orders = [];
  Set<String> _knownDocIds = {};
  bool _sawFirstSnapshot = false;

  /// Ouverture de l'écran : seules les commandes passées APRÈS sonnent. Le
  /// premier lot vient souvent du cache local, puis le serveur ajoute les
  /// commandes manquées — sans ce filtre, ça déclenchait une fausse alarme
  /// à chaque démarrage.
  final DateTime _openedAt = DateTime.now();
  bool _alarmActive = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Rafraîchit l'horloge et les chronos des commandes.
    _clock = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    try {
      _sub = (widget.ordersStream ?? OrdersRepository.watchIncomingOrders()).listen(
        _handleSnapshot,
        onError: (_) => setState(() {
          _loading = false;
          _error = 'Connexion au serveur impossible.';
        }),
      );
    } catch (_) {
      // Firestore injoignable (hors ligne au premier lancement, Firebase pas
      // initialisé) — même repli plutôt qu'un plantage.
      _loading = false;
      _error = 'Connexion au serveur impossible.';
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _clock?.cancel();
    unawaited(AlertService.stopAlarm());
    super.dispose();
  }

  void _handleSnapshot(List<IncomingOrder> orders) {
    final ids = orders.map((o) => o.docId).toSet();
    if (_sawFirstSnapshot) {
      final arrived = ids.difference(_knownDocIds);
      // Pendant les 2 premières minutes (le temps que le serveur complète le
      // cache), seules les commandes récentes sonnent ; ensuite TOUTE
      // nouvelle commande sonne, même si l'horloge du téléphone du client
      // est décalée.
      final settling = DateTime.now().difference(_openedAt) < const Duration(minutes: 2);
      final recent = _openedAt.subtract(const Duration(minutes: 10));
      final reallyNew = orders.any(
        (o) =>
            arrived.contains(o.docId) &&
            o.status == IncomingOrderStatus.confirmed &&
            (!settling || o.date.isAfter(recent)),
      );
      if (reallyNew) _onNewOrders();
    }
    _sawFirstSnapshot = true;
    _knownDocIds = ids;
    setState(() {
      _orders = orders;
      _now = DateTime.now();
      _loading = false;
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
    if (widget.ordersStream != null) return; // démo / test : rien à écrire
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

  void _openCalendar() => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => OrderCalendarScreen(loader: widget.calendarLoader)),
      );

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final confirmed = _orders.where((o) => o.status == IncomingOrderStatus.confirmed).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final ready = _orders.where((o) => o.status == IncomingOrderStatus.ready).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final completed = _orders.where((o) => o.status == IncomingOrderStatus.completed).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final today = _orders.where((o) => o.date.year == _now.year && o.date.month == _now.month && o.date.day == _now.day);
    final todayTotal = today.fold(0.0, (sum, o) => sum + o.total);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Row(
          children: [
            const BrandSeal(size: 46),
            const SizedBox(width: 14),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Commandes en direct', overflow: TextOverflow.ellipsis),
                  Row(
                    children: [
                      _LiveDot(active: _error == null && !_loading),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '${KioskConfig.restaurantLocationName} · application + bornes',
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(formatHourMinute(_now), style: textTheme.headlineSmall?.copyWith(color: AppColors.creamMuted)),
          ),
          FilledButton.icon(
            onPressed: _openCalendar,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.glassStrong,
              foregroundColor: AppColors.cream,
              minimumSize: const Size(0, 52),
              side: const BorderSide(color: AppColors.glassBorder),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
            ),
            icon: const Icon(Icons.calendar_month_rounded, color: AppColors.orange),
            label: const Text('Commandes'),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Espace équipe',
            onPressed: () => _openStaffAccess(context),
            icon: const Icon(Icons.admin_panel_settings_outlined),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Stack(
        children: [
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      _StatChip(icon: Icons.receipt_long_rounded, label: 'Aujourd\'hui', value: '${today.length}'),
                      _StatChip(icon: Icons.euro_rounded, label: 'Chiffre du jour', value: formatPrice(todayTotal)),
                      _StatChip(
                        icon: Icons.smartphone_rounded,
                        label: 'Appli',
                        value: '${today.where((o) => o.source == OrderSource.app).length}',
                      ),
                      _StatChip(
                        icon: Icons.point_of_sale_rounded,
                        label: 'Borne',
                        value: '${today.where((o) => o.source == OrderSource.kiosk).length}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: _error != null
                        ? Center(
                            child: EmptyState(
                              icon: Icons.cloud_off_rounded,
                              title: _error!,
                              message: 'Les commandes réapparaîtront dès que la connexion sera rétablie.',
                            ),
                          )
                        : _loading
                            ? const Center(child: CircularProgressIndicator())
                            : Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: _OrderColumn(
                                      title: 'Nouvelles',
                                      icon: Icons.local_fire_department_rounded,
                                      accent: AppColors.orange,
                                      orders: confirmed,
                                      now: _now,
                                      emptyText: 'Aucune commande en attente',
                                      actionLabel: 'Marquer prête',
                                      actionIcon: Icons.notifications_active_rounded,
                                      onAction: (o) => _advance(o, IncomingOrderStatus.ready),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _OrderColumn(
                                      title: 'Prêtes',
                                      icon: Icons.room_service_rounded,
                                      accent: AppColors.green,
                                      orders: ready,
                                      now: _now,
                                      emptyText: 'Rien à remettre pour l\'instant',
                                      actionLabel: 'Récupérée',
                                      actionIcon: Icons.check_rounded,
                                      onAction: (o) => _advance(o, IncomingOrderStatus.completed),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _OrderColumn(
                                      title: 'Terminées',
                                      icon: Icons.task_alt_rounded,
                                      accent: AppColors.creamMuted,
                                      orders: completed,
                                      emptyText: 'Pas encore de commande terminée',
                                      compact: true,
                                    ),
                                  ),
                                ],
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
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.orange, width: 6),
                  color: AppColors.orange.withValues(alpha: 0.08),
                ),
              ),
            ),
          ),
          if (_alarmActive)
            Positioned(
              top: 8,
              left: 0,
              right: 0,
              child: Center(
                child: FadeSlideIn(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(22, 12, 12, 12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFFFFAD5C), AppColors.orange]),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      boxShadow: [BoxShadow(color: AppColors.orange.withValues(alpha: 0.55), blurRadius: 36)],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.notifications_active_rounded, color: AppColors.charcoal, size: 28),
                        const SizedBox(width: 12),
                        Text('Nouvelle commande !', style: textTheme.titleLarge?.copyWith(color: AppColors.charcoal)),
                        const SizedBox(width: 18),
                        FilledButton(
                          onPressed: _dismissAlarm,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.charcoal,
                            foregroundColor: AppColors.cream,
                            minimumSize: const Size(0, 48),
                            shape: const StadiumBorder(),
                          ),
                          child: const Text('Désactiver'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LiveDot extends StatefulWidget {
  const _LiveDot({required this.active});

  final bool active;

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _LiveDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  // Ne pulse que quand le flux est réellement en direct (et jamais pendant
  // les tests, où il n'y a pas de connexion — pas d'animation infinie).
  void _sync() {
    if (widget.active && KioskConfig.ambientAnimations && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.active) {
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.active ? AppColors.green : AppColors.red;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) => Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3 + 0.5 * _pulse.value), blurRadius: 4 + 8 * _pulse.value)],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.glass,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppColors.orange),
          const SizedBox(width: 8),
          Text(label, style: textTheme.bodySmall),
          const SizedBox(width: 10),
          Text(value, style: textTheme.titleMedium),
        ],
      ),
    );
  }
}

/// Une colonne (Nouvelles / Prêtes / Terminées). Toutes défilent de la même
/// façon : liste avec barre de défilement toujours visible, défilement au
/// doigt ET à la souris (voir [KioskScrollBehavior]).
class _OrderColumn extends StatefulWidget {
  const _OrderColumn({
    required this.title,
    required this.icon,
    required this.accent,
    required this.orders,
    required this.emptyText,
    this.now,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.compact = false,
  });

  final String title;
  final IconData icon;
  final Color accent;
  final List<IncomingOrder> orders;
  final String emptyText;
  final DateTime? now;
  final String? actionLabel;
  final IconData? actionIcon;
  final void Function(IncomingOrder)? onAction;
  final bool compact;

  @override
  State<_OrderColumn> createState() => _OrderColumnState();
}

class _OrderColumnState extends State<_OrderColumn> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.glass,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: widget.accent.withValues(alpha: 0.35), width: 2)),
            ),
            child: Row(
              children: [
                Icon(widget.icon, color: widget.accent),
                const SizedBox(width: 10),
                Expanded(child: Text(widget.title, style: textTheme.titleLarge)),
                Container(
                  constraints: const BoxConstraints(minWidth: 36),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: widget.orders.isEmpty ? AppColors.glassBorder : widget.accent,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    '${widget.orders.length}',
                    textAlign: TextAlign.center,
                    style: textTheme.titleMedium?.copyWith(
                      color: widget.orders.isEmpty ? AppColors.creamMuted : AppColors.charcoal,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: widget.orders.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(widget.emptyText, textAlign: TextAlign.center, style: textTheme.bodyMedium),
                    ),
                  )
                : Scrollbar(
                    controller: _controller,
                    thumbVisibility: true,
                    interactive: true,
                    child: ListView.separated(
                      controller: _controller,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
                      itemCount: widget.orders.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final order = widget.orders[i];
                        return FadeSlideIn(
                          key: ValueKey(order.docId),
                          child: OrderCard(
                            order: order,
                            accent: widget.accent,
                            now: widget.now,
                            compact: widget.compact,
                            actionLabel: widget.actionLabel,
                            actionIcon: widget.actionIcon,
                            onAction: widget.onAction == null ? null : () => widget.onAction!(order),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
