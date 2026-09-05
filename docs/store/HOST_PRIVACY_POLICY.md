# Host the privacy policy (GitHub Pages)

The in-app and Play Console URL defaults to:

`https://ak0982.github.io/paisa/privacy`

That address is a **placeholder until you publish**. Source markdown: [`../privacy_policy.md`](../privacy_policy.md).

## Option A — GitHub Pages from this repo

1. Enable Pages on `github.com/ak0982/paisa` (Settings → Pages).
2. Publish `docs/privacy_policy.md` as a site page at `/privacy` (or `/privacy/`):
   - Either use a `docs/` site with a `privacy.md` / `privacy/index.md`, or
   - Use a simple `gh-pages` branch that contains `privacy/index.html` converted from the markdown.
3. Open the URL in an Incognito window and confirm it loads **without login**.
4. If the final URL differs, update `LegalUrls.privacyPolicyUrl` in `lib/constants/legal.dart` and rebuild the AAB.

## Option B — Any static host

Upload the rendered HTML of `privacy_policy.md` to any HTTPS host you control, then point `LegalUrls.privacyPolicyUrl` and the Play Console privacy field at that URL.

## Play Console

Paste the **live** URL into **App content → Privacy policy** before submitting for review.
