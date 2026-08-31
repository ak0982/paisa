import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/category_info.dart';
import '../models/manual_transaction.dart';
import '../providers/finance_store.dart';
import '../theme/paisa_colors.dart';
import '../theme/paisa_theme.dart';
import 'neo_surface.dart';
import 'paisa_coin.dart';
import 'pulse_calendar_sheet.dart';

/// Opens the Neo-Vault mint sheet to add a manual cash move.
///
/// [initialDay] seeds the date (Day Strip empty-day CTA passes the selected
/// day). Returns the new transaction id on save, or null if dismissed.
Future<String?> showMintTransactionSheet(
  BuildContext context, {
  DateTime? initialDay,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.72),
    builder: (_) => MintTransactionSheet(initialDay: initialDay),
  );
}

class MintTransactionSheet extends StatefulWidget {
  const MintTransactionSheet({super.key, this.initialDay});

  final DateTime? initialDay;

  @override
  State<MintTransactionSheet> createState() => _MintTransactionSheetState();
}

class _MintTransactionSheetState extends State<MintTransactionSheet> {
  late DateTime _day;
  SpendCategory _category = SpendCategory.food;
  late bool _isCredit;
  late TextEditingController _amountCtrl;
  late TextEditingController _messageCtrl;
  bool _messageEdited = false;
  bool _saving = false;
  String? _amountError;
  bool _futureClamped = false;

  static final _amountFmt = NumberFormat('#0.##', 'en_IN');

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final seed = widget.initialDay ?? now;
    final clamped = clampManualDay(seed, now: now);
    _futureClamped = DateTime(seed.year, seed.month, seed.day).isAfter(
      DateTime(now.year, now.month, now.day),
    );
    _day = clamped;
    _isCredit = defaultManualIsCredit(_category);
    _amountCtrl = TextEditingController();
    _messageCtrl = TextEditingController(text: defaultManualMessage(_category));
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  void _onCategory(SpendCategory c) {
    HapticFeedback.selectionClick();
    setState(() {
      _category = c;
      _isCredit = defaultManualIsCredit(c);
      if (!_messageEdited) {
        _messageCtrl.text = defaultManualMessage(c);
      }
    });
  }

  void _onDirection(bool credit) {
    if (_isCredit == credit) return;
    HapticFeedback.selectionClick();
    setState(() => _isCredit = credit);
  }

  Future<void> _pickDate() async {
    final result = await showPulseCalendarSheet(
      context,
      initialStart: _day,
      initialMode: PulseCalendarMode.day,
    );
    if (result == null || !mounted) return;
    final now = DateTime.now();
    final clamped = clampManualDay(result.startDay, now: now);
    final wasFuture = result.startDay.isAfter(
      DateTime(now.year, now.month, now.day),
    );
        setState(() {
          _day = clamped;
          _futureClamped = wasFuture;
        });
  }

  double? _parseAmount() {
    final raw = _amountCtrl.text.trim().replaceAll(',', '');
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  Future<void> _save() async {
    if (_saving) return;
    final amount = _parseAmount();
    final err = validateManualAmount(amount);
    if (err != null) {
      setState(() => _amountError = err);
      return;
    }
    setState(() {
      _saving = true;
      _amountError = null;
    });
    try {
      final store = context.read<FinanceStore>();
      final tx = await store.addManualTransaction(
        amount: amount!,
        date: _day,
        category: _category,
        message: _messageCtrl.text,
        isCredit: _isCredit,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(tx.id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _amountError = e is ArgumentError ? e.message?.toString() : 'Could not save';
      });
    }
  }

  String get _dayLabel {
    const months = [
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
    ];
    return '${_day.day} ${months[_day.month - 1]} ${_day.year}';
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: PaisaCoinRise(
          offsetY: 14,
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 18, 16),
            constraints: BoxConstraints(
              maxHeight: media.size.height * 0.92,
            ),
            decoration: BoxDecoration(
              color: PaisaColors.card,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: PaisaColors.border, width: 2),
              boxShadow: PaisaColors.hardShadow(offset: 6),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _MintRim(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 2, 12, 8),
                  child: Row(
                    children: [
                      const PaisaCoinWordmark(suffix: 'ADD'),
                      const Spacer(),
                      PaisaChromeIconButton(
                        icon: Icons.close_rounded,
                        tooltip: 'Close',
                        onTap: () {
                          if (_saving) return;
                          Navigator.of(context).maybePop();
                        },
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Mint a move',
                          style: PaisaTheme.sora(
                            size: 18,
                            weight: FontWeight.w800,
                            color: PaisaColors.ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Cash entry · labeled Manually added',
                          style: PaisaTheme.manrope(
                            size: 12.5,
                            weight: FontWeight.w600,
                            color: PaisaColors.mutedCaption,
                          ),
                        ),
                        const SizedBox(height: 18),
                        _FieldLabel('AMOUNT'),
                        const SizedBox(height: 8),
                        NeoSurface(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 4,
                          ),
                          radius: 14,
                          borderWidth: 1.5,
                          child: TextField(
                            controller: _amountCtrl,
                            enabled: !_saving,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.,]'),
                              ),
                            ],
                            style: PaisaTheme.sora(
                              size: 22,
                              weight: FontWeight.w800,
                              color: PaisaColors.ink,
                            ),
                            decoration: InputDecoration(
                              prefixText: '₹ ',
                              prefixStyle: PaisaTheme.sora(
                                size: 22,
                                weight: FontWeight.w800,
                                color: PaisaColors.primary,
                              ),
                              hintText: _amountFmt.format(0),
                              hintStyle: PaisaTheme.sora(
                                size: 22,
                                weight: FontWeight.w700,
                                color: PaisaColors.muted,
                              ),
                              border: InputBorder.none,
                            ),
                            onChanged: (_) {
                              if (_amountError != null) {
                                setState(() => _amountError = null);
                              }
                            },
                          ),
                        ),
                        if (_amountError != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            _amountError!,
                            style: PaisaTheme.manrope(
                              size: 12,
                              weight: FontWeight.w600,
                              color: PaisaColors.overBudget,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        _FieldLabel('DATE'),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: _saving ? null : _pickDate,
                          child: NeoSurface(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            radius: 14,
                            borderWidth: 1.5,
                            child: Row(
                              children: [
                                Text(
                                  _dayLabel,
                                  style: PaisaTheme.sora(
                                    size: 14,
                                    weight: FontWeight.w700,
                                    color: PaisaColors.ink,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                                const Spacer(),
                                const Icon(
                                  Icons.calendar_today_outlined,
                                  size: 16,
                                  color: PaisaColors.mutedCaption,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_futureClamped) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Future dates are clamped to today.',
                            style: PaisaTheme.manrope(
                              size: 11.5,
                              weight: FontWeight.w600,
                              color: PaisaColors.warning,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        _FieldLabel('TYPE'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final info in CategoryInfo.all)
                              _TypeChip(
                                info: info,
                                active: _category == info.category,
                                onTap: _saving
                                    ? null
                                    : () => _onCategory(info.category),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _FieldLabel('DIRECTION'),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _DirectionChip(
                                label: 'OUT',
                                active: !_isCredit,
                                onTap: _saving
                                    ? null
                                    : () => _onDirection(false),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _DirectionChip(
                                label: 'IN',
                                active: _isCredit,
                                onTap: _saving
                                    ? null
                                    : () => _onDirection(true),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _FieldLabel('MESSAGE'),
                        const SizedBox(height: 8),
                        NeoSurface(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 4,
                          ),
                          radius: 14,
                          borderWidth: 1.5,
                          child: TextField(
                            controller: _messageCtrl,
                            enabled: !_saving,
                            maxLines: 2,
                            style: PaisaTheme.manrope(
                              size: 14,
                              weight: FontWeight.w600,
                              color: PaisaColors.ink,
                            ),
                            decoration: InputDecoration(
                              hintText: defaultManualMessage(_category),
                              hintStyle: PaisaTheme.manrope(
                                size: 14,
                                color: PaisaColors.muted,
                              ),
                              border: InputBorder.none,
                            ),
                            onChanged: (_) {
                              _messageEdited = true;
                            },
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: _saving
                              ? null
                              : () => Navigator.of(context).maybePop(),
                          child: NeoSurface(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            radius: 14,
                            borderWidth: 1.5,
                            child: Text(
                              'CANCEL',
                              textAlign: TextAlign.center,
                              style: PaisaTheme.label(
                                size: 12,
                                color: PaisaColors.mutedCaption,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: GestureDetector(
                          onTap: _saving ? null : _save,
                          child: NeoSurface(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            radius: 14,
                            borderWidth: 2,
                            borderColor: PaisaColors.inkOnAccent,
                            color: PaisaColors.primary,
                            shadow: true,
                            shadowOffset: 4,
                            child: _saving
                                ? const SizedBox(
                                    height: 16,
                                    child: Center(
                                      child: SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: PaisaColors.inkOnAccent,
                                        ),
                                      ),
                                    ),
                                  )
                                : Text(
                                    'SAVE',
                                    textAlign: TextAlign.center,
                                    style: PaisaTheme.label(
                                      size: 13,
                                      color: PaisaColors.inkOnAccent,
                                      letterSpacing: 1.4,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MintRim extends StatelessWidget {
  const _MintRim();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 18,
      child: Center(
        child: Container(
          width: 42,
          height: 4,
          decoration: BoxDecoration(
            color: PaisaColors.border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: PaisaTheme.label(
        size: 10,
        color: PaisaColors.primary,
        letterSpacing: 2.2,
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.info,
    required this.active,
    required this.onTap,
  });

  final CategoryInfo info;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: active ? info.tintBg.withOpacity(0.35) : PaisaColors.cardElevated,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? PaisaColors.primary : PaisaColors.border,
            width: active ? 2 : 1.5,
          ),
        ),
        child: Text(
          '${info.emoji} ${info.label}',
          style: PaisaTheme.manrope(
            size: 12,
            weight: FontWeight.w700,
            color: active ? PaisaColors.ink : PaisaColors.mutedCaption,
          ),
        ),
      ),
    );
  }
}

class _DirectionChip extends StatelessWidget {
  const _DirectionChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: NeoSurface(
        padding: const EdgeInsets.symmetric(vertical: 12),
        radius: 12,
        borderWidth: active ? 2 : 1.5,
        borderColor: active ? PaisaColors.inkOnAccent : PaisaColors.border,
        color: active ? PaisaColors.primary : PaisaColors.cardElevated,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: PaisaTheme.label(
            size: 13,
            color: active ? PaisaColors.inkOnAccent : PaisaColors.mutedCaption,
            letterSpacing: 1.6,
          ),
        ),
      ),
    );
  }
}
