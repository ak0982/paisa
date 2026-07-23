import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/transaction.dart';
import '../providers/app_settings.dart';
import '../theme/paisa_colors.dart';
import '../theme/paisa_theme.dart';
import '../utils/formatters.dart';

class TransactionRow extends StatelessWidget {
  const TransactionRow({
    super.key,
    required this.transaction,
    this.showCategoryChip = false,
    this.showSmsLabel = true,
    this.showTime = false,
    this.showDate = false,
    this.compact = false,
  });

  final Transaction transaction;
  final bool showCategoryChip;
  final bool showSmsLabel;
  final bool showTime;
  final bool showDate;
  final bool compact;

  static String _displayMerchant(String merchant, bool mask) {
    if (!mask || merchant.length <= 2) return merchant;
    if (merchant.length <= 4) {
      return '${merchant[0]}••${merchant[merchant.length - 1]}';
    }
    return '${merchant.substring(0, 2)}••••${merchant.substring(merchant.length - 2)}';
  }

  @override
  Widget build(BuildContext context) {
    final maskMerchants =
        context.watch<AppSettings?>()?.maskMerchantNames ?? false;
    final info = transaction.categoryInfo;
    final amountColor =
        transaction.isCredit ? PaisaColors.credit : PaisaColors.debit;
    final merchantLabel =
        _displayMerchant(transaction.merchant, maskMerchants);
    final timeLabel = formatTxnTime(transaction.timestamp);
    final dateLabel = formatTxnDate(transaction.timestamp);
    final flowColor =
        transaction.isCredit ? PaisaColors.credit : PaisaColors.mutedCaption;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 10 : 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: compact ? 42 : 44,
            height: compact ? 42 : 44,
            decoration: BoxDecoration(
              color: info.tintBg,
              borderRadius: BorderRadius.circular(compact ? 12 : 13),
              border: Border.all(color: PaisaColors.inkOnAccent, width: 2),
            ),
            alignment: Alignment.center,
            child: Text(info.emoji, style: TextStyle(fontSize: compact ? 18 : 19)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  merchantLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PaisaTheme.manrope(
                    size: compact ? 13.5 : 14,
                    weight: FontWeight.w600,
                    color: PaisaColors.ink,
                  ),
                ),
                const SizedBox(height: 3),
                if (showCategoryChip)
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: PaisaColors.cardElevated,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: flowColor.withOpacity(0.5),
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          transaction.flowLabel,
                          style: PaisaTheme.manrope(
                            size: 9.5,
                            weight: FontWeight.w700,
                            color: flowColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          transaction.accountLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PaisaTheme.manrope(
                            size: 11,
                            color: PaisaColors.mutedCaption,
                          ),
                        ),
                      ),
                      if (showDate || showTime) ...[
                        const SizedBox(width: 6),
                        Text(
                          showDate ? dateLabel : timeLabel,
                          style: PaisaTheme.manrope(
                            size: 10.5,
                            weight: FontWeight.w600,
                            color: PaisaColors.muted,
                          ),
                        ),
                      ],
                    ],
                  )
                else
                  Text(
                    showDate
                        ? '$dateLabel · ${transaction.flowLabel} · ${transaction.metaLine}'
                        : '${transaction.flowLabel} · ${transaction.metaLine}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PaisaTheme.manrope(
                      size: 11.5,
                      color: PaisaColors.mutedCaption,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatAmount(
                  transaction.amount,
                  isCredit: transaction.isCredit,
                ),
                style: PaisaTheme.sora(
                  size: 14,
                  weight: FontWeight.w700,
                  color: amountColor,
                ),
              ),
              if (showSmsLabel && transaction.source == 'SMS') ...[
                const SizedBox(height: 3),
                Text(
                  '⚡ From SMS',
                  style: PaisaTheme.manrope(
                    size: 9.5,
                    weight: FontWeight.w600,
                    color: PaisaColors.muted,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
