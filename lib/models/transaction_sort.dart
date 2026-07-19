import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'transaction.dart';

/// How a transaction list should be ordered.
///
/// Shared across every screen that renders a list of transactions so the
/// control and behaviour stay consistent. Date sorts keep the day-grouped
/// layout; amount sorts collapse into a single flat, date-labelled list.
enum TransactionSort {
  dateDesc,
  dateAsc,
  amountDesc,
  amountAsc;

  /// Default order for transaction lists (newest activity first).
  static const TransactionSort defaultSort = TransactionSort.dateDesc;

  bool get isDate => this == dateDesc || this == dateAsc;
  bool get isAmount => this == amountDesc || this == amountAsc;
  bool get isAscending => this == dateAsc || this == amountAsc;

  /// Full label shown inside the sort menu.
  String get label => switch (this) {
        TransactionSort.dateDesc => 'Newest first',
        TransactionSort.dateAsc => 'Oldest first',
        TransactionSort.amountDesc => 'Amount: high to low',
        TransactionSort.amountAsc => 'Amount: low to high',
      };

  /// Compact label shown on the collapsed control.
  String get shortLabel => switch (this) {
        TransactionSort.dateDesc => 'Newest',
        TransactionSort.dateAsc => 'Oldest',
        TransactionSort.amountDesc => 'High → low',
        TransactionSort.amountAsc => 'Low → high',
      };

  IconData get icon => switch (this) {
        TransactionSort.dateDesc => Icons.south_rounded,
        TransactionSort.dateAsc => Icons.north_rounded,
        TransactionSort.amountDesc => Icons.trending_down_rounded,
        TransactionSort.amountAsc => Icons.trending_up_rounded,
      };
}

/// Returns a new list ordered by [sort]. Amount sorts fall back to newest-first
/// for equal amounts so ordering stays stable and predictable.
List<Transaction> sortTransactions(
  List<Transaction> list,
  TransactionSort sort,
) {
  final copy = List<Transaction>.from(list);
  switch (sort) {
    case TransactionSort.dateDesc:
      copy.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    case TransactionSort.dateAsc:
      copy.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    case TransactionSort.amountDesc:
      copy.sort((a, b) {
        final c = b.amount.compareTo(a.amount);
        return c != 0 ? c : b.timestamp.compareTo(a.timestamp);
      });
    case TransactionSort.amountAsc:
      copy.sort((a, b) {
        final c = a.amount.compareTo(b.amount);
        return c != 0 ? c : b.timestamp.compareTo(a.timestamp);
      });
  }
  return copy;
}

/// A block of transactions rendered together. Date sorts produce one section
/// per day (with a [header]); amount sorts produce a single header-less flat
/// section covering all matching transactions.
class TransactionListSection {
  const TransactionListSection({required this.header, required this.items});

  /// Day label (e.g. `TODAY · 7 JUL`) or null for a flat amount-sorted section.
  final String? header;
  final List<Transaction> items;
}

/// Splits [list] into ordered render sections for the given [sort].
///
/// Every transaction-list screen uses this so grouping, ordering, and the
/// date-vs-amount layout switch behave identically everywhere.
List<TransactionListSection> buildTransactionSections(
  List<Transaction> list,
  TransactionSort sort,
) {
  final sorted = sortTransactions(list, sort);
  if (!sort.isDate) {
    if (sorted.isEmpty) return const [];
    return [TransactionListSection(header: null, items: sorted)];
  }

  final groups = <String, List<Transaction>>{};
  for (final t in sorted) {
    final key = DateFormat('yyyy-MM-dd').format(t.timestamp);
    groups.putIfAbsent(key, () => []).add(t);
  }
  // Insertion order already reflects the sort direction (sorted is ordered).
  return groups.entries
      .map((e) => TransactionListSection(
            header: dayGroupLabel(e.key),
            items: e.value,
          ))
      .toList();
}

/// Human-friendly label for a `yyyy-MM-dd` day key.
///
/// Relative labels (Today/Yesterday) are kept for recent days, but the
/// absolute date always includes the year, e.g. `TODAY · 12 JUL 2025`.
String dayGroupLabel(String key) {
  final date = DateTime.parse(key);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final absolute = DateFormat('d MMM yyyy').format(date).toUpperCase();
  if (day == today) {
    return 'TODAY · $absolute';
  }
  if (day == yesterday) {
    return 'YESTERDAY · $absolute';
  }
  return DateFormat('EEE · d MMM yyyy').format(date).toUpperCase();
}
