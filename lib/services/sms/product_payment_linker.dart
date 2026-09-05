import 'package:flutter/foundation.dart';

import '../../models/category_info.dart';
import '../../models/transaction.dart';
import 'account_discovery.dart';

/// Links funding-account CCBP payments onto the **credit-card** product for
/// You-section drilldown — without rewriting identity via the funding bank.
///
/// Loan EMI/NACH stays on the funding account for listing/balance (same idea
/// as CCBP). Use `TransactionEnrichment.resolveAssociatedLoanProduct` for
/// product context; do not attach loan funding rows onto loan buckets.
///
/// Confidence order (cards):
/// 1. Funding row already stored on the product mask (caller handles)
/// 2. Amount + time pairing with a product-side SMS on that mask: if a
///    product ack already covers the same amount within [pairingWindow],
///    **do not** attach the funding row (one economic bill → one drilldown
///    row; funding debit stays on savings only)
/// 3. Orphan funding (no covering product SMS): attach only when this
///    product is the unique CC among [discoveries]
/// 4. (Ingest) destination last-4 / NACH beneficiary — see [TransactionEnrichment]
///
/// Ambiguous: same amount/time matches two different products → link neither.
/// Loan linking helpers remain for tests / association queries.
abstract final class ProductPaymentLinker {
  /// Max gap between funding debit and product acknowledgment SMS.
  static const Duration pairingWindow = Duration(hours: 48);

  static bool amountsClose(double a, double b) => (a - b).abs() < 0.015;

  static bool withinPairingWindow(DateTime a, DateTime b) =>
      a.difference(b).abs() <= pairingWindow;

  static final _loanFundingHint = RegExp(
    r'\b(?:emi|nach|loan)\b',
    caseSensitive: false,
  );

  /// True when [t] looks like a payment toward a loan/EMI product.
  static bool looksLikeLoanFundingPayment(Transaction t) {
    if (t.isCredit) return false;
    if (t.accountKind == AccountKind.loan) return true;
    if (t.category == SpendCategory.emi) return true;
    final m = t.merchant.toLowerCase();
    if (m.contains('mbk emi')) return true;
    // Word-bound: "Premium" / "Chemist" / "Panache" are not EMI (R2-3).
    return _loanFundingHint.hasMatch(m);
  }

  /// True when [t] looks like a payment toward a credit-card product (CCBP etc.).
  static bool looksLikeCardFundingPayment(Transaction t) {
    if (t.isCredit) return false;
    if (t.isCreditCardBillPayment) return true;
    if (t.accountKind == AccountKind.creditCard) return true;
    final m = t.merchant.toLowerCase();
    return m.contains('ccbp') || m.contains('credit card bill');
  }

  static bool _isOnProduct(Transaction t, String bank, String mask) {
    return t.maskedAccount == mask &&
        t.bank.toLowerCase() == bank.toLowerCase();
  }

  /// Whether [productBank]|[productMask] already has a ledger row covering
  /// [funding]'s amount inside [pairingWindow].
  static bool productSideCoversFunding({
    required Transaction funding,
    required String productBank,
    required String productMask,
    required Iterable<Transaction> all,
    ProductPairingIndex? index,
  }) {
    final idx = index ?? ProductPairingIndex(all);
    return idx.productSideCoversFunding(
      funding: funding,
      productBank: productBank,
      productMask: productMask,
    );
  }

  /// Nested-scan reference used only to prove the amount+time index matches
  /// the original `all.any` semantics.
  @visibleForTesting
  static bool productSideCoversFundingScan({
    required Transaction funding,
    required String productBank,
    required String productMask,
    required Iterable<Transaction> all,
  }) {
    return all.any(
      (a) =>
          _isOnProduct(a, productBank, productMask) &&
          amountsClose(a.amount, funding.amount) &&
          withinPairingWindow(a.timestamp, funding.timestamp),
    );
  }

  static bool _isUniqueProductOfKind({
    required String productBank,
    required String productMask,
    required AccountKind productKind,
    required Iterable<DiscoveredAccount> products,
  }) {
    final sameKind = products.where((d) => d.kind == productKind).toList();
    return sameKind.length == 1 &&
        sameKind.first.mask == productMask &&
        sameKind.first.bank.toLowerCase() == productBank.toLowerCase();
  }

  /// Funding transactions that should also appear under product [bank]|[mask].
  ///
  /// Returns funding rows **only** when no product-side SMS already covers
  /// that amount+window (orphan EMI/CCBP). Paired product acks stay solo.
  static List<Transaction> linkedFundingTransactions({
    required String productBank,
    required String productMask,
    required AccountKind productKind,
    required List<Transaction> all,
    required Iterable<DiscoveredAccount> discoveries,
    ProductPairingIndex? index,
  }) {
    return _linkedFundingTransactions(
      productBank: productBank,
      productMask: productMask,
      productKind: productKind,
      all: all,
      discoveries: discoveries,
      covers: (index ?? ProductPairingIndex(all)).productSideCoversFunding,
    );
  }

  /// Nested-scan twin of [linkedFundingTransactions] for index parity tests.
  @visibleForTesting
  static List<Transaction> linkedFundingTransactionsScan({
    required String productBank,
    required String productMask,
    required AccountKind productKind,
    required List<Transaction> all,
    required Iterable<DiscoveredAccount> discoveries,
  }) {
    return _linkedFundingTransactions(
      productBank: productBank,
      productMask: productMask,
      productKind: productKind,
      all: all,
      discoveries: discoveries,
      covers: ({
        required Transaction funding,
        required String productBank,
        required String productMask,
      }) =>
          productSideCoversFundingScan(
            funding: funding,
            productBank: productBank,
            productMask: productMask,
            all: all,
          ),
    );
  }

  static List<Transaction> _linkedFundingTransactions({
    required String productBank,
    required String productMask,
    required AccountKind productKind,
    required List<Transaction> all,
    required Iterable<DiscoveredAccount> discoveries,
    required bool Function({
      required Transaction funding,
      required String productBank,
      required String productMask,
    }) covers,
  }) {
    if (productMask.isEmpty) return const [];
    if (productKind != AccountKind.loan &&
        productKind != AccountKind.creditCard) {
      return const [];
    }

    final products = discoveries
        .where(
          (d) =>
              d.mask.isNotEmpty &&
              (d.kind == AccountKind.loan || d.kind == AccountKind.creditCard),
        )
        .toList();

    final uniqueProduct = _isUniqueProductOfKind(
      productBank: productBank,
      productMask: productMask,
      productKind: productKind,
      products: products,
    );

    final out = <Transaction>[];
    final seen = <String>{};

    for (final t in all) {
      if (seen.contains(t.id)) continue;
      if (_isOnProduct(t, productBank, productMask)) continue;

      final isCandidate = productKind == AccountKind.loan
          ? looksLikeLoanFundingPayment(t)
          : looksLikeCardFundingPayment(t);
      if (!isCandidate) continue;

      // Product-side SMS already represents this EMI/bill → savings only.
      if (covers(
        funding: t,
        productBank: productBank,
        productMask: productMask,
      )) {
        continue;
      }

      // Ambiguity: another product of the same kind has an anchor with the
      // same amount in the window → do not guess.
      final ambiguous = products.any((d) {
        if (d.kind != productKind) return false;
        if (d.mask == productMask &&
            d.bank.toLowerCase() == productBank.toLowerCase()) {
          return false;
        }
        return covers(
          funding: t,
          productBank: d.bank,
          productMask: d.mask,
        );
      });
      if (ambiguous) continue;

      // Orphan funding: no covering product ack. Only attach when this is
      // the unique loan/CC — never guess via funding bank among many.
      if (!uniqueProduct) continue;

      seen.add(t.id);
      out.add(t);
    }

    return out;
  }
}

/// Amount (±0.015) + 48h window index for product↔funding pairing.
///
/// Lookups are equivalent to scanning every row with
/// [ProductPaymentLinker.productSideCoversFundingScan].
class ProductPairingIndex {
  ProductPairingIndex(Iterable<Transaction> all) {
    for (final t in all) {
      if (t.maskedAccount.isEmpty) continue;
      final cents = _cents(t.amount);
      final key = _key(t.bank, t.maskedAccount, cents);
      _byProductCents.putIfAbsent(key, () => []).add(t);
    }
  }

  final Map<String, List<Transaction>> _byProductCents = {};

  static int _cents(double amount) => (amount * 100).round();

  static String _key(String bank, String mask, int cents) =>
      '${bank.toLowerCase()}|$mask|$cents';

  /// Cents buckets that can contain an amount within ±0.015 of [amount].
  static Iterable<int> nearbyCents(double amount) {
    final lo = ((amount - 0.015) * 100).floor() - 1;
    final hi = ((amount + 0.015) * 100).ceil() + 1;
    return [for (var c = lo; c <= hi; c++) c];
  }

  bool productSideCoversFunding({
    required Transaction funding,
    required String productBank,
    required String productMask,
  }) {
    if (productMask.isEmpty) return false;
    for (final cents in nearbyCents(funding.amount)) {
      final hits = _byProductCents[_key(productBank, productMask, cents)];
      if (hits == null) continue;
      for (final a in hits) {
        if (ProductPaymentLinker.amountsClose(a.amount, funding.amount) &&
            ProductPaymentLinker.withinPairingWindow(
              a.timestamp,
              funding.timestamp,
            )) {
          return true;
        }
      }
    }
    return false;
  }
}
