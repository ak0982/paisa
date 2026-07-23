/// Maps FinanceStore / SMS bank display names to bundled logo assets.
///
/// Bank strings match what [SmsParser] / discovery emit (e.g. `SBI`, `Yes Bank`,
/// `Bank of Baroda`, `Federal` for Fi/Jupiter). Matching is case-insensitive and
/// accepts aliases plus account titles like `SBI Savings`.
library;

abstract final class BankAssets {
  static const _assetPrefix = 'assets/banks/';

  /// Canonical asset file names under [assets/banks/].
  static const Map<String, String> _slugToFile = {
    'sbi': 'sbi.svg',
    'hdfc': 'hdfc.svg',
    'icici': 'icici.svg',
    'axis': 'axis.svg',
    'kotak': 'kotak.svg',
    'idfc': 'idfc.svg',
    'pnb': 'pnb.svg',
    'federal': 'federal.svg',
    'yes': 'yes.svg',
    'indusind': 'indusind.svg',
    'bob': 'bob.svg',
    'canara': 'canara.svg',
  };

  /// Alias → canonical slug. Longer aliases are matched first.
  static const Map<String, String> _aliases = {
    'bank of baroda': 'bob',
    'bobcard': 'bob',
    'yes bank': 'yes',
    'idfc first': 'idfc',
    'idfc first bank': 'idfc',
    'punjab national': 'pnb',
    'punjab national bank': 'pnb',
    'state bank': 'sbi',
    'state bank of india': 'sbi',
    'federal bank': 'federal',
    'fi': 'federal',
    'jupiter': 'federal',
    'indusind bank': 'indusind',
    'canara bank': 'canara',
    'hdfc bank': 'hdfc',
    'icici bank': 'icici',
    'axis bank': 'axis',
    'kotak mahindra': 'kotak',
    'kotak mahindra bank': 'kotak',
    'bob': 'bob',
    'sbi': 'sbi',
    'hdfc': 'hdfc',
    'icici': 'icici',
    'axis': 'axis',
    'kotak': 'kotak',
    'idfc': 'idfc',
    'pnb': 'pnb',
    'federal': 'federal',
    'yes': 'yes',
    'indusind': 'indusind',
    'canara': 'canara',
  };

  static List<MapEntry<String, String>>? _sortedAliases;

  static List<MapEntry<String, String>> get _aliasesLongestFirst {
    return _sortedAliases ??= (_aliases.entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length)));
  }

  /// Asset path for [bankOrName], or `null` when no logo is bundled.
  ///
  /// Accepts raw bank codes (`SBI`), account titles (`SBI Savings`), and
  /// aliases (`BOB`, `Yes Bank`, `Fi`).
  static String? assetPathFor(String bankOrName) {
    final slug = resolveSlug(bankOrName);
    if (slug == null) return null;
    final file = _slugToFile[slug];
    if (file == null) return null;
    return '$_assetPrefix$file';
  }

  /// Canonical slug (`sbi`, `bob`, …) or `null`.
  static String? resolveSlug(String bankOrName) {
    final normalized = _normalize(bankOrName);
    if (normalized.isEmpty) return null;

    for (final entry in _aliasesLongestFirst) {
      final alias = entry.key;
      if (normalized == alias ||
          normalized.startsWith('$alias ') ||
          normalized.endsWith(' $alias') ||
          normalized.contains(' $alias ')) {
        return entry.value;
      }
    }
    return null;
  }

  /// Whether a bundled logo exists for [bankOrName].
  static bool hasLogo(String bankOrName) => assetPathFor(bankOrName) != null;

  /// Letter used when falling back (first alphanumeric of the bank name).
  static String fallbackLetter(String bankOrName, {String orElse = '?'}) {
    final trimmed = bankOrName.trim();
    if (trimmed.isEmpty) return orElse;
    final match = RegExp(r'[A-Za-z0-9]').firstMatch(trimmed);
    if (match == null) return orElse;
    return match.group(0)!.toUpperCase();
  }

  static String _normalize(String raw) {
    return raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[•·]+'), ' ')
        .trim();
  }
}
