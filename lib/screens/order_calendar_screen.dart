import 'package:flutter/material.dart';

import '../data/menu_data.dart';
import '../data/orders_repository.dart';
import '../models/incoming_order.dart';
import '../theme/app_theme.dart';
import '../widgets/order_card.dart';
import '../widgets/ui.dart';

const _monthNames = [
  'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin',
  'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre',
];
const _weekdayNames = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Charge les commandes entre deux dates (début inclus, fin exclue).
typedef OrdersLoader = Future<List<IncomingOrder>> Function(DateTime start, DateTime end);

/// Historique des commandes en calendrier : on choisit l'année et le mois,
/// chaque jour affiche son nombre de commandes, et un appui sur un jour
/// détaille ses commandes (heure, numéro, source, contenu, total).
class OrderCalendarScreen extends StatefulWidget {
  const OrderCalendarScreen({super.key, this.initialMonth, this.loader});

  final DateTime? initialMonth;

  /// Par défaut [OrdersRepository.fetchOrdersBetween] ; injectable pour les
  /// tests et la démo.
  final OrdersLoader? loader;

  @override
  State<OrderCalendarScreen> createState() => _OrderCalendarScreenState();
}

class _OrderCalendarScreenState extends State<OrderCalendarScreen> {
  late DateTime _month;
  late DateTime _selectedDay;
  List<IncomingOrder> _monthOrders = [];
  bool _loading = true;
  String? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final start = widget.initialMonth ?? now;
    _month = DateTime(start.year, start.month);
    _selectedDay = DateTime(now.year, now.month, now.day);
    _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final load = widget.loader ?? OrdersRepository.fetchOrdersBetween;
      final orders = await load(_month, DateTime(_month.year, _month.month + 1));
      if (!mounted || request != _request) return;
      setState(() {
        _monthOrders = orders;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _monthOrders = [];
        _loading = false;
        _error = 'Impossible de charger les commandes — vérifiez la connexion.';
      });
    }
  }

  void _goToMonth(DateTime month) {
    _month = DateTime(month.year, month.month);
    final now = DateTime.now();
    // Garde le jour sélectionné dans le mois affiché.
    _selectedDay = (_month.year == now.year && _month.month == now.month)
        ? DateTime(now.year, now.month, now.day)
        : DateTime(_month.year, _month.month, 1);
    _load();
  }

  Future<void> _pickMonth() async {
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (_) => _MonthPickerDialog(initial: _month),
    );
    if (picked != null) _goToMonth(picked);
  }

  List<IncomingOrder> _ordersOn(DateTime day) => _monthOrders.where((o) => _sameDay(o.date, day)).toList();

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 980;
    final calendar = _CalendarPanel(
      month: _month,
      selectedDay: _selectedDay,
      orders: _monthOrders,
      loading: _loading,
      onPrev: () => _goToMonth(DateTime(_month.year, _month.month - 1)),
      onNext: () => _goToMonth(DateTime(_month.year, _month.month + 1)),
      onPickMonth: _pickMonth,
      onToday: () => _goToMonth(DateTime.now()),
      onSelect: (d) => setState(() => _selectedDay = d),
    );
    final details = _DayDetails(day: _selectedDay, orders: _ordersOn(_selectedDay), error: _error, loading: _loading);

    return Scaffold(
      appBar: AppBar(title: const Text('Historique des commandes')),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 500, child: SingleChildScrollView(child: calendar)),
                    const SizedBox(width: 20),
                    Expanded(child: details),
                  ],
                )
              : ListView(
                  children: [
                    calendar,
                    const SizedBox(height: 16),
                    SizedBox(height: 640, child: details),
                  ],
                ),
        ),
      ),
    );
  }
}

class _CalendarPanel extends StatelessWidget {
  const _CalendarPanel({
    required this.month,
    required this.selectedDay,
    required this.orders,
    required this.loading,
    required this.onPrev,
    required this.onNext,
    required this.onPickMonth,
    required this.onToday,
    required this.onSelect,
  });

  final DateTime month;
  final DateTime selectedDay;
  final List<IncomingOrder> orders;
  final bool loading;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onPickMonth;
  final VoidCallback onToday;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = DateTime(month.year, month.month, 1).weekday - 1; // lundi = 0
    final counts = <int, int>{};
    for (final o in orders) {
      counts[o.date.day] = (counts[o.date.day] ?? 0) + 1;
    }
    final maxCount = counts.values.fold(0, (a, b) => a > b ? a : b);
    final monthTotal = orders.fold(0.0, (sum, o) => sum + o.total);
    final today = DateTime.now();

    return GlassCard(
      radius: AppRadius.xl,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton.filledTonal(onPressed: onPrev, icon: const Icon(Icons.chevron_left_rounded), tooltip: 'Mois précédent'),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  onTap: onPickMonth,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('${_monthNames[month.month - 1]} ${month.year}', style: textTheme.titleLarge),
                        const SizedBox(width: 6),
                        const Icon(Icons.expand_more_rounded, color: AppColors.orange),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton.filledTonal(onPressed: onNext, icon: const Icon(Icons.chevron_right_rounded), tooltip: 'Mois suivant'),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final d in ['L', 'M', 'M', 'J', 'V', 'S', 'D'])
                Expanded(child: Text(d, textAlign: TextAlign.center, style: textTheme.labelSmall)),
            ],
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 0.92,
            ),
            itemCount: leading + daysInMonth,
            itemBuilder: (context, i) {
              if (i < leading) return const SizedBox.shrink();
              final dayNumber = i - leading + 1;
              final day = DateTime(month.year, month.month, dayNumber);
              final count = counts[dayNumber] ?? 0;
              final selected = _sameDay(day, selectedDay);
              final isToday = _sameDay(day, today);
              // Plus il y a de commandes, plus la case "chauffe".
              final heat = maxCount == 0 ? 0.0 : count / maxCount;
              return Material(
                color: selected
                    ? AppColors.orange
                    : count > 0
                        ? AppColors.orange.withValues(alpha: 0.08 + 0.22 * heat)
                        : Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  side: BorderSide(color: isToday && !selected ? AppColors.orange : AppColors.glassBorder, width: isToday ? 1.5 : 1),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  onTap: () => onSelect(day),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$dayNumber',
                          style: textTheme.titleMedium?.copyWith(color: selected ? AppColors.charcoal : AppColors.cream),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          count == 0 ? ' ' : '$count cde${count > 1 ? 's' : ''}',
                          style: textTheme.labelSmall?.copyWith(
                            letterSpacing: 0,
                            fontSize: 11,
                            color: selected ? AppColors.charcoal : AppColors.orange,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          const Divider(),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: loading
                    ? Text('Chargement…', style: textTheme.bodyMedium)
                    : Text(
                        '${orders.length} commande${orders.length > 1 ? 's' : ''} ce mois-ci · ${formatPrice(monthTotal)}',
                        style: textTheme.bodyMedium?.copyWith(color: AppColors.cream),
                      ),
              ),
              TextButton.icon(
                onPressed: onToday,
                icon: const Icon(Icons.today_rounded, size: 18),
                label: const Text('Aujourd\'hui'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayDetails extends StatelessWidget {
  const _DayDetails({required this.day, required this.orders, required this.error, required this.loading});

  final DateTime day;
  final List<IncomingOrder> orders;
  final String? error;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final total = orders.fold(0.0, (sum, o) => sum + o.total);
    final fromApp = orders.where((o) => o.source == OrderSource.app).length;
    final paid = orders.where((o) => o.paid).fold(0.0, (sum, o) => sum + o.total);
    final sorted = [...orders]..sort((a, b) => b.date.compareTo(a.date));

    return GlassCard(
      radius: AppRadius.xl,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Eyebrow(_weekdayNames[day.weekday - 1]),
          const SizedBox(height: 4),
          Text('${day.day} ${_monthNames[day.month - 1].toLowerCase()} ${day.year}', style: textTheme.headlineMedium),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Kpi(label: 'Commandes', value: '${orders.length}'),
              _Kpi(label: 'Chiffre', value: formatPrice(total)),
              _Kpi(label: 'Appli / Borne', value: '$fromApp / ${orders.length - fromApp}'),
              _Kpi(label: 'Payé en ligne', value: formatPrice(paid)),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(),
          const SizedBox(height: 12),
          Expanded(
            child: error != null
                ? Center(child: EmptyState(icon: Icons.cloud_off_rounded, title: error!))
                : loading
                    ? const Center(child: CircularProgressIndicator())
                    : sorted.isEmpty
                        ? const Center(
                            child: EmptyState(
                              icon: Icons.event_busy_rounded,
                              title: 'Aucune commande ce jour-là',
                              message: 'Choisissez un autre jour dans le calendrier.',
                            ),
                          )
                        : ListView.separated(
                            itemCount: sorted.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 10),
                            itemBuilder: (context, i) => OrderCard(
                              order: sorted[i],
                              compact: true,
                              accent: switch (sorted[i].status) {
                                IncomingOrderStatus.confirmed => AppColors.orange,
                                IncomingOrderStatus.ready => AppColors.green,
                                _ => AppColors.creamMuted,
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: 170,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.charcoal.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: textTheme.headlineSmall?.copyWith(color: AppColors.orange)),
          const SizedBox(height: 2),
          Text(label, style: textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Choix rapide de l'année et du mois.
class _MonthPickerDialog extends StatefulWidget {
  const _MonthPickerDialog({required this.initial});

  final DateTime initial;

  @override
  State<_MonthPickerDialog> createState() => _MonthPickerDialogState();
}

class _MonthPickerDialogState extends State<_MonthPickerDialog> {
  late int _year = widget.initial.year;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(onPressed: () => setState(() => _year--), icon: const Icon(Icons.chevron_left_rounded)),
                  Expanded(child: Text('$_year', textAlign: TextAlign.center, style: textTheme.headlineSmall)),
                  IconButton(onPressed: () => setState(() => _year++), icon: const Icon(Icons.chevron_right_rounded)),
                ],
              ),
              const SizedBox(height: 14),
              GridView.count(
                shrinkWrap: true,
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 2.4,
                children: [
                  for (var m = 1; m <= 12; m++)
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(DateTime(_year, m)),
                      style: FilledButton.styleFrom(
                        backgroundColor: (_year == widget.initial.year && m == widget.initial.month)
                            ? AppColors.orange
                            : AppColors.glass,
                        foregroundColor: (_year == widget.initial.year && m == widget.initial.month)
                            ? AppColors.charcoal
                            : AppColors.cream,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                      ),
                      child: FittedBox(child: Text(_monthNames[m - 1])),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
