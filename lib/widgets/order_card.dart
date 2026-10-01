import 'package:flutter/material.dart';

import '../data/menu_data.dart';
import '../models/incoming_order.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

String formatHourMinute(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Badge "APPLI" / "BORNE" : d'où vient la commande.
class SourceBadge extends StatelessWidget {
  const SourceBadge({super.key, required this.source});

  final OrderSource source;

  @override
  Widget build(BuildContext context) {
    final isKiosk = source == OrderSource.kiosk;
    return StatusPill(
      label: isKiosk ? 'BORNE' : 'APPLI',
      color: isKiosk ? AppColors.honey : const Color(0xFF8FB8FF),
      icon: isKiosk ? Icons.point_of_sale_rounded : Icons.smartphone_rounded,
    );
  }
}

/// Temps écoulé depuis la commande, qui vire à l'orange puis au rouge :
/// la cuisine voit d'un coup d'œil ce qui attend depuis trop longtemps.
class ElapsedChip extends StatelessWidget {
  const ElapsedChip({super.key, required this.since, required this.now});

  final DateTime since;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final minutes = now.difference(since).inMinutes.clamp(0, 9999);
    final color = minutes >= 25
        ? AppColors.red
        : minutes >= 12
            ? AppColors.orange
            : AppColors.green;
    final label = minutes < 1
        ? 'à l\'instant'
        : minutes < 60
            ? '$minutes min'
            : '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')}';
    return StatusPill(label: label, color: color, icon: Icons.timer_outlined);
  }
}

/// Carte d'une commande sur l'écran de réception et dans le calendrier.
class OrderCard extends StatelessWidget {
  const OrderCard({
    super.key,
    required this.order,
    required this.accent,
    this.now,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.compact = false,
  });

  final IncomingOrder order;
  final Color accent;

  /// Pour le chrono — null = pas de chrono (commandes terminées, calendrier).
  final DateTime? now;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  /// Version resserrée (colonne "Terminées", calendrier).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.glassStrong,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: accent.withValues(alpha: compact ? 0.18 : 0.45)),
        boxShadow: compact
            ? null
            : [BoxShadow(color: accent.withValues(alpha: 0.10), blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 5, color: accent.withValues(alpha: compact ? 0.4 : 1)),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(compact ? 14 : 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              order.displayNumber,
                              overflow: TextOverflow.ellipsis,
                              style: (compact ? textTheme.titleLarge : textTheme.headlineSmall)?.copyWith(color: accent),
                            ),
                          ),
                          const SizedBox(width: 10),
                          SourceBadge(source: order.source),
                          const Spacer(),
                          if (now != null) ElapsedChip(since: order.date, now: now!),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${order.modeLabel} · ${formatHourMinute(order.date)}',
                        style: textTheme.bodyMedium?.copyWith(color: AppColors.cream, fontWeight: FontWeight.w600),
                      ),
                      if (order.customerName != null) ...[
                        const SizedBox(height: 6),
                        StatusPill(
                          label: '${order.customerName} · fidélité'
                              '${order.pointsEarned > 0 ? ' (+${order.pointsEarned} pts)' : ''}',
                          color: AppColors.honey,
                          icon: Icons.person_rounded,
                        ),
                      ],
                      if (order.fulfillmentDetail != null && order.fulfillmentDetail!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(order.fulfillmentDetail!, style: textTheme.bodySmall),
                      ],
                      const SizedBox(height: 10),
                      for (final l in order.lines)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                constraints: const BoxConstraints(minWidth: 30),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(AppRadius.xs),
                                ),
                                child: Text(
                                  '${l.quantity}×',
                                  textAlign: TextAlign.center,
                                  style: textTheme.labelLarge?.copyWith(color: accent),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${l.itemName}${l.sizeLabel != null ? ' · ${l.sizeLabel}' : ''}',
                                      style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                                    ),
                                    if (l.supplements.isNotEmpty)
                                      Text(
                                        '+ ${l.supplements.map((s) => s.name).join(', ')}',
                                        style: textTheme.bodySmall?.copyWith(color: AppColors.honey),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (order.appliedRewardLabel != null) ...[
                        const SizedBox(height: 4),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.honey.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            border: Border.all(color: AppColors.honey.withValues(alpha: 0.35)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.card_giftcard_rounded, size: 17, color: AppColors.honey),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'À AJOUTER : ${order.appliedRewardLabel} (fidélité)',
                                  style: textTheme.labelMedium?.copyWith(color: AppColors.honey, fontWeight: FontWeight.w800),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Wrap(
                              spacing: 10,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                StatusPill(
                                  label: order.paid ? 'Payée' : 'À encaisser',
                                  color: order.paid ? AppColors.green : AppColors.honey,
                                  icon: order.paid ? Icons.check_rounded : Icons.payments_outlined,
                                ),
                                if (order.customerPhone != null && order.customerPhone!.isNotEmpty)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.phone_outlined, size: 15, color: AppColors.creamMuted),
                                      const SizedBox(width: 4),
                                      Text(order.customerPhone!, style: textTheme.bodySmall),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(formatPrice(order.total), style: textTheme.titleLarge?.copyWith(color: AppColors.cream)),
                        ],
                      ),
                      if (onAction != null && actionLabel != null) ...[
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: FilledButton.icon(
                            onPressed: onAction,
                            style: FilledButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: AppColors.charcoal,
                              textStyle: textTheme.labelLarge?.copyWith(fontSize: 17, fontWeight: FontWeight.w800),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                            ),
                            icon: Icon(actionIcon ?? Icons.arrow_forward_rounded),
                            label: Text(actionLabel!),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
