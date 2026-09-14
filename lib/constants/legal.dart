/// Play Store / legal URLs used by Privacy and Help screens.
///
/// Host [privacyPolicyUrl] before submission (GitHub Pages works well). The
/// markdown source lives at `docs/privacy_policy.md` — publish it to this URL
/// (or change the constant to match wherever you host it).
class LegalUrls {
  LegalUrls._();

  /// Hosted on GitHub Pages from the `gh-pages` branch (`docs/privacy/index.html`).
  /// Source markdown: `docs/privacy_policy.md`.
  static const privacyPolicyUrl = 'https://ak0982.github.io/paisa/privacy';

  /// Support contact shown in Help (copy-to-clipboard).
  static const supportEmail = 'support@paisa.app';
}
