# Fonts

Self-hosted so a Calendarr instance makes no third-party request and works
offline. Fetched from Google Fonts; see `LICENSE.txt` for the full licence text.

| File | Font | Version | Weights | Subset |
|---|---|---|---|---|
| `roboto-latin.woff2` | Roboto | v51 | 100–900 (variable) | latin |
| `roboto-latin-ext.woff2` | Roboto | v51 | 100–900 (variable) | latin-ext |
| `roboto-mono-latin.woff2` | Roboto Mono | v31 | 400 | latin |
| `roboto-mono-latin-ext.woff2` | Roboto Mono | v31 | 400 | latin-ext |

Roboto and Roboto Mono are licensed under the **Apache License 2.0**
(https://github.com/googlefonts/roboto). Only the latin and latin-ext subsets
are shipped: every language Calendarr translates into (de, ch, en, fr, it, nl,
da, no, sv, fi) uses Latin script. Glyphs outside those ranges — Cyrillic in an
event title, say — fall back to the system font, which is what `unicode-range`
in `../css/app.css` is for.

Roboto Mono ships as the static 400 instance, not the variable file: it is used
only for hex values and the TOTP secret, never bold, so the variable file would
cost 32 KB for nothing.

`Google Sans` is deliberately **not** used. It is Google-internal and not
licensed for third parties; it was named in the font stack but never loaded.
