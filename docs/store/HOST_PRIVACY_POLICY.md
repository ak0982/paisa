# Host the privacy policy (GitHub Pages)

The in-app and Play Console URL defaults to:

`https://ak0982.github.io/paisa/privacy`

Source markdown: [`../privacy_policy.md`](../privacy_policy.md).  
Rendered static page: [`../privacy/index.html`](../privacy/index.html) (also published on the `gh-pages` branch).

## Option A — GitHub Pages from this repo (recommended)

1. Keep `docs/privacy/index.html` in sync with `docs/privacy_policy.md` when the policy changes.
2. Publish the site from the **`gh-pages`** branch (root), which contains only the public site files (`index.html`, `privacy/index.html`, `.nojekyll`) — not store/research docs.
3. Enable Pages on `github.com/ak0982/paisa`:
   - **Settings → Pages → Build and deployment → Source:** Deploy from a branch
   - **Branch:** `gh-pages` / `/ (root)` → Save
   - Or via CLI: `gh api -X POST repos/ak0982/paisa/pages -f build_type=legacy -f source[branch]=gh-pages -f source[path]=/`
4. **Private repo note:** GitHub Pages on a private repo requires GitHub Pro (or make the repo public). The published site URL itself must load **without login** for Play Console.
5. Open `https://ak0982.github.io/paisa/privacy` (and `/privacy/`) in Incognito and confirm HTTP 200.
6. If the final URL differs, update `LegalUrls.privacyPolicyUrl` in `lib/constants/legal.dart` and rebuild the AAB.

## Option B — Any static host

Upload the rendered HTML of `privacy_policy.md` to any HTTPS host you control, then point `LegalUrls.privacyPolicyUrl` and the Play Console privacy field at that URL.

## Play Console

Paste the **live** URL into **App content → Privacy policy** before submitting for review.
