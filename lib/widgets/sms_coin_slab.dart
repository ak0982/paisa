import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/transaction.dart';
import '../providers/app_settings.dart';
import '../providers/finance_store.dart';
import '../services/sms/original_sms_lookup.dart';
import '../services/sms/sms_reader_service.dart';
import '../theme/paisa_colors.dart';
import '../theme/paisa_theme.dart';
import '../utils/formatters.dart';
import 'neo_surface.dart';
import 'paisa_coin.dart';

/// Transaction detail as a struck coin that flips inside a mint slab.
///
/// The face is the Paisa Coin the rest of the app already speaks: milled rim,
/// a gauge struck fully OUT (white) or IN (lime), amount + merchant + account
/// in the recessed centre field. Flipping the coin turns the disc over into
/// the **mint slab** — the reverse — which carries the full original bank SMS
/// in a recessed, scrollable field.
///
/// The SMS body is never stored with the transaction; it is fetched from the
/// inbox by `Transaction.smsId` when the sheet opens (see
/// [SmsReaderService.loadOriginalSms]), so a deleted message or a revoked
/// permission renders as struck empty-state copy rather than an error.

final _reader = SmsReaderService();

Future<OriginalSmsLookup> _deviceLoader(String smsId) =>
    _reader.loadOriginalSms(smsId);

/// Opens the coin-flip detail for [transaction]. [isMove] marks internal
/// movement (CC bill payment, self-transfer leg) so the gauge stays unstruck.
Future<void> showTransactionCoinSlab(
  BuildContext context,
  Transaction transaction, {
  bool isMove = false,
  OriginalSmsLoader? loader,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.78),
    builder: (_) => TransactionCoinSlab(
      transaction: transaction,
      isMove: isMove,
      loader: loader,
    ),
  );
}

class TransactionCoinSlab extends StatefulWidget {
  const TransactionCoinSlab({
    super.key,
    required this.transaction,
    this.isMove = false,
    this.loader,
  });

  final Transaction transaction;
  final bool isMove;

  /// Injectable inbox lookup; defaults to the on-device reader.
  final OriginalSmsLoader? loader;

  @override
  State<TransactionCoinSlab> createState() => _TransactionCoinSlabState();
}

class _TransactionCoinSlabState extends State<TransactionCoinSlab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flip = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  final ScrollController _bodyScroll = ScrollController();

  /// Null while the inbox read is still in flight.
  OriginalSmsLookup? _lookup;

  @override
  void initState() {
    super.initState();
    final smsId = widget.transaction.smsId;
    if (smsId == null || smsId.isEmpty) {
      _lookup = const OriginalSmsLookup.miss(OriginalSmsStatus.noSmsId);
    } else {
      _load(smsId);
    }
  }

  Future<void> _load(String smsId) async {
    OriginalSmsLookup result;
    try {
      result = await (widget.loader ?? _deviceLoader)(smsId);
    } catch (_) {
      // A throwing read must still resolve the reverse — otherwise the user is
      // left staring at the reading bar forever.
      result = const OriginalSmsLookup.miss(OriginalSmsStatus.lookupFailed);
    }
    if (!mounted) return;
    setState(() => _lookup = result);
  }

  @override
  void dispose() {
    _flip.dispose();
    _bodyScroll.dispose();
    super.dispose();
  }

  bool get _showingBack => _flip.value >= 0.5;

  void _toggleFlip() {
    HapticFeedback.selectionClick();
    if (_showingBack) {
      _flip.reverse();
    } else {
      _flip.forward();
    }
  }

  Future<void> _copySms() async {
    final body = _lookup?.sms?.body;
    if (body == null || body.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: body));
    if (!mounted) return;
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Original SMS copied')),
    );
  }

  Future<void> _deleteManual() async {
    final t = widget.transaction;
    if (!t.isManual) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PaisaColors.card,
        title: Text(
          'Delete this mint?',
          style: PaisaTheme.sora(size: 17, weight: FontWeight.w700),
        ),
        content: Text(
          'Remove this manually added move from My Paisa. This cannot be undone.',
          style: PaisaTheme.manrope(size: 13.5, color: PaisaColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Delete',
              style: PaisaTheme.manrope(
                weight: FontWeight.w600,
                color: PaisaColors.overBudget,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok =
        await context.read<FinanceStore>().deleteManualTransaction(t.id);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).maybePop();
    }
  }

  bool get _isManual => widget.transaction.isManual;

  @override
  Widget build(BuildContext context) {
    final t = widget.transaction;
    final maskMerchants =
        context.watch<AppSettings?>()?.maskMerchantNames ?? false;
    final merchant = maskedMerchantLabel(t.merchant, maskMerchants);
    final media = MediaQuery.of(context);
    final stageHeight = (media.size.height * 0.40).clamp(228.0, 318.0);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: PaisaCoinRise(
          offsetY: 18,
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 18, 16),
            decoration: BoxDecoration(
              color: PaisaColors.card,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: PaisaColors.border, width: 2),
              boxShadow: PaisaColors.hardShadow(offset: 6),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _SlabRim(),
                _header(),
                GestureDetector(
                  onHorizontalDragEnd: (details) {
                    if ((details.primaryVelocity ?? 0).abs() > 180) {
                      _toggleFlip();
                    }
                  },
                  child: SizedBox(
                    height: stageHeight,
                    child: _stage(stageHeight, merchant),
                  ),
                ),
                _meta(),
                _actions(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 2, 12, 4),
      child: Row(
        children: [
          const PaisaCoinWordmark(suffix: 'MINT'),
          const Spacer(),
          if (widget.isMove) ...[
            const _MoveChip(),
            const SizedBox(width: 8),
          ],
          PaisaChromeIconButton(
            icon: Icons.close_rounded,
            tooltip: 'Close',
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }

  /// The flipping disc. Below the halfway point the face is shown; past it the
  /// slab, counter-rotated so its text is not mirrored.
  Widget _stage(double stageHeight, String merchant) {
    return AnimatedBuilder(
      animation: _flip,
      builder: (context, _) {
        final v = _flip.value;
        final child = v >= 0.5
            ? Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()..rotateY(math.pi),
                child: _slabFace(),
              )
            : _coinFace(stageHeight, merchant);

        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateY(v * math.pi),
          child: child,
        );
      },
    );
  }

  // ── Face: the struck coin ─────────────────────────────────────────────────

  Widget _coinFace(double stageHeight, String merchant) {
    final t = widget.transaction;
    final amountColor = widget.isMove
        ? PaisaColors.mutedCaption
        : (t.isCredit ? PaisaColors.credit : PaisaColors.debit);
    final accountLine =
        t.hasValidMask ? '${t.bank} · ${t.maskedAccount}' : t.bank;

    return Center(
      child: GestureDetector(
        onTap: _toggleFlip,
        child: PaisaCoinFace(
          maxDiameter: math.min(262, stageHeight - 6),
          fieldWidthFactor: 0.62,
          outShare: t.isCredit ? 0.0 : 1.0,
          hasFlow: !widget.isMove,
          topLegend: t.flowLabel.toUpperCase(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                t.isCredit ? 'IN' : 'OUT',
                style: PaisaTheme.label(
                  size: 9.5,
                  color: t.isCredit
                      ? PaisaColors.primary
                      : PaisaColors.mutedCaption,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 7),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  formatInr(t.amount),
                  style: PaisaTheme.sora(
                    size: 26,
                    weight: FontWeight.w800,
                    color: amountColor,
                    letterSpacing: -0.6,
                    height: 1.0,
                  ),
                ),
              ),
              const SizedBox(height: 9),
              Container(
                width: 34,
                height: 1.5,
                color: PaisaColors.muted.withOpacity(0.55),
              ),
              const SizedBox(height: 9),
              Text(
                merchant,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: PaisaTheme.sora(
                  size: 13,
                  weight: FontWeight.w800,
                  color: PaisaColors.ink,
                  letterSpacing: -0.1,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                accountLine,
                maxLines: 1,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: PaisaTheme.manrope(
                  size: 10.5,
                  weight: FontWeight.w600,
                  color: PaisaColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Reverse: the mint slab ────────────────────────────────────────────────

  Widget _slabFace() {
    final sms = _lookup?.sms;
    final sender = sms?.sender.trim();
    final reverseTitle = _isManual ? 'MINT NOTE' : 'ORIGINAL SMS';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: NeoSurface(
        color: PaisaColors.cardElevated,
        borderColor: PaisaColors.border,
        borderWidth: 2,
        radius: 18,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  reverseTitle,
                  style: PaisaTheme.label(
                    size: 10,
                    color: PaisaColors.primary,
                    letterSpacing: 2.8,
                  ),
                ),
                const Spacer(),
                if (sender != null && sender.isNotEmpty)
                  _SenderStamp(sender: sender),
              ],
            ),
            // A missing/zero date column would otherwise be struck as
            // "RECEIVED 1 JAN 1970"; no line is better than a wrong one.
            if (sms != null && sms.timestamp.millisecondsSinceEpoch > 0) ...[
              const SizedBox(height: 5),
              Text(
                'RECEIVED ${formatTxnDate(sms.timestamp).toUpperCase()}'
                ' · ${formatTxnTime(sms.timestamp)}',
                style: PaisaTheme.manrope(
                  size: 10,
                  weight: FontWeight.w600,
                  color: PaisaColors.muted,
                  letterSpacing: 0.4,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Expanded(child: _recessedField()),
          ],
        ),
      ),
    );
  }

  Widget _recessedField() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: PaisaColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PaisaColors.border, width: 1.5),
      ),
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      child: _fieldContent(),
    );
  }

  Widget _fieldContent() {
    final lookup = _lookup;
    if (lookup == null) return const _ReadingInbox();

    if (lookup.hasBody) {
      return Scrollbar(
        controller: _bodyScroll,
        child: SingleChildScrollView(
          controller: _bodyScroll,
          child: SelectableText(
            lookup.sms!.body,
            style: PaisaTheme.manrope(
              size: 13,
              weight: FontWeight.w500,
              color: PaisaColors.ink,
              height: 1.5,
            ),
          ),
        ),
      );
    }

    final copy = originalSmsEmptyCopy(lookup.displayStatus);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 34, height: 2, color: PaisaColors.border),
          const SizedBox(height: 14),
          Text(
            copy.title,
            textAlign: TextAlign.center,
            style: PaisaTheme.sora(
              size: 14,
              weight: FontWeight.w800,
              color: PaisaColors.ink,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            copy.body,
            textAlign: TextAlign.center,
            style: PaisaTheme.manrope(
              size: 12,
              weight: FontWeight.w500,
              color: PaisaColors.mutedCaption,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  // ── Chrome below the disc ─────────────────────────────────────────────────

  Widget _meta() {
    final t = widget.transaction;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
      child: Column(
        children: [
          Text(
            '${formatTxnDate(t.timestamp)} · ${formatTxnTime(t.timestamp)}',
            style: PaisaTheme.manrope(
              size: 12.5,
              weight: FontWeight.w700,
              color: PaisaColors.mutedCaption,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${t.flowLabel} · ${t.categoryInfo.label}',
            textAlign: TextAlign.center,
            style: PaisaTheme.manrope(
              size: 11.5,
              weight: FontWeight.w500,
              color: PaisaColors.muted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: AnimatedBuilder(
        animation: _flip,
        builder: (context, _) {
          final back = _showingBack;
          final flipLabel = back
              ? 'FLIP TO COIN'
              : (_isManual ? 'FLIP TO NOTE' : 'FLIP TO SMS');
          final flipIcon = back
              ? Icons.monetization_on_outlined
              : (_isManual ? Icons.edit_note_rounded : Icons.sms_outlined);
          return Row(
            children: [
              Expanded(
                child: _SlabAction(
                  label: flipLabel,
                  icon: flipIcon,
                  accent: true,
                  onTap: _toggleFlip,
                ),
              ),
              const SizedBox(width: 10),
              if (_isManual)
                _SlabAction(
                  label: 'DELETE',
                  icon: Icons.delete_outline_rounded,
                  onTap: _deleteManual,
                )
              else
                _SlabAction(
                  label: 'COPY SMS',
                  icon: Icons.copy_rounded,
                  onTap: (_lookup?.hasBody ?? false) ? _copySms : null,
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Wraps a list row so tapping it opens the Coin Flip / Mint Slab detail.
///
/// Internal movement is inferred from the transaction alone (CC bill payment /
/// CC payment received); screens that already know about self-transfer pairing
/// pass their own handler instead.
class TransactionCoinTap extends StatelessWidget {
  const TransactionCoinTap({
    super.key,
    required this.transaction,
    required this.child,
    this.onTap,
  });

  final Transaction transaction;
  final Widget child;
  final ValueChanged<Transaction>? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${transaction.merchant} transaction details',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            if (onTap != null) {
              onTap!(transaction);
              return;
            }
            showTransactionCoinSlab(
              context,
              transaction,
              isMove: transaction.isCreditCardBillPayment ||
                  transaction.isCreditCardPaymentReceived,
            );
          },
          child: child,
        ),
      ),
    );
  }
}

// ── Parts ───────────────────────────────────────────────────────────────────

/// Milled top edge, so the sheet reads as a slab rising out of the press.
class _SlabRim extends StatelessWidget {
  const _SlabRim();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 18,
      width: double.infinity,
      child: CustomPaint(painter: _MilledRimPainter()),
    );
  }
}

class _MilledRimPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final tick = Paint()
      ..color = PaisaColors.muted.withOpacity(0.42)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    const spacing = 7.0;
    const inset = 18.0;
    for (var x = inset; x < size.width - inset; x += spacing) {
      canvas.drawLine(Offset(x, 6), Offset(x, size.height - 6), tick);
    }

    canvas.drawLine(
      Offset(14, size.height - 0.5),
      Offset(size.width - 14, size.height - 0.5),
      Paint()
        ..color = PaisaColors.border
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _MilledRimPainter oldDelegate) => false;
}

/// Sender of the alert, struck onto the slab rim.
class _SenderStamp extends StatelessWidget {
  const _SenderStamp({required this.sender});

  final String sender;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: PaisaColors.card,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: PaisaColors.border, width: 1.5),
      ),
      child: Text(
        sender.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: PaisaTheme.sora(
          size: 10,
          weight: FontWeight.w800,
          color: PaisaColors.mutedCaption,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _MoveChip extends StatelessWidget {
  const _MoveChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: PaisaColors.cardElevated,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: PaisaColors.muted, width: 1.5),
      ),
      child: Text(
        'MOVE',
        style: PaisaTheme.sora(
          size: 9.5,
          weight: FontWeight.w800,
          color: PaisaColors.mutedCaption,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _ReadingInbox extends StatelessWidget {
  const _ReadingInbox();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'READING THE INBOX',
            style: PaisaTheme.label(
              size: 10,
              color: PaisaColors.mutedCaption,
              letterSpacing: 2.6,
            ),
          ),
          const SizedBox(height: 12),
          const SizedBox(
            width: 120,
            height: 3,
            child: LinearProgressIndicator(
              backgroundColor: PaisaColors.border,
              color: PaisaColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Hard-shadow chrome button used under the disc.
class _SlabAction extends StatelessWidget {
  const _SlabAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.accent = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final fg = !enabled
        ? PaisaColors.muted
        : (accent ? PaisaColors.inkOnAccent : PaisaColors.ink);

    return GestureDetector(
      onTap: onTap,
      child: NeoSurface(
        color: accent && enabled
            ? PaisaColors.primary
            : PaisaColors.cardElevated,
        borderColor: accent && enabled
            ? PaisaColors.primary
            : PaisaColors.border,
        borderWidth: 2,
        radius: 12,
        shadow: enabled,
        shadowOffset: 3,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PaisaTheme.sora(
                  size: 11,
                  weight: FontWeight.w800,
                  color: fg,
                  letterSpacing: 1.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
