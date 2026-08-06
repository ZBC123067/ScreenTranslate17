# v0.2 → v0.4.1 audit record

## Fixed before packaging

| Area | v0.2 finding | v0.4 correction |
| --- | --- | --- |
| Compile integrity | Many CJK strings were mojibake; several Objective-C string literals and the settings XML were not syntactically valid. | Rewrote all source, plist, settings and README text as valid UTF-8; added static UTF-8, XML and quote-balance checks. |
| Architecture | `arm64 arm64e` build setting conflicted with `iphoneos-arm64e` package metadata. | Targets the actual iPhone 15 Pro architecture (`arm64e`) consistently. |
| RootHide | RootHide scheme was present but required base entitlements were absent. | Added RootHide entitlements to the tweak and preference bundle; all jailbreak data uses `jbroot()` under jbroot `/var`. |
| Injection | The UIKit-wide injection model did not sufficiently guard helper processes. | Keeps the intended UIKit filter for Bootstrap-selected apps but rejects SpringBoard, WebKit child processes, extensions and AuthKit UI before startup. |
| OCR | Crop ownership could be released twice; OCR did not sort reading order and fixed unsupported language codes could invalidate a Vision request. | Single ownership release, sorted observations, pixel-bound crop clamping, supported-language filtering and fast OCR with re-entry guards. |
| Overlay/UI | Separate overlay did not recreate on scene changes, used an excessive alert level, and input translation overwrote text immediately. | Rebuilds per active scene, uses normal+1 level, clamps labels, and asks for explicit confirmation before input replacement. |
| Privacy | Sensitive text could be cached; token placeholders could be matched again by the broad identifier rule; settings only obscured the API Key visually. | Sensitive values are masked in one non-recursive pass, never cached, sensitive fields/screens are blocked, and the settings/README disclose the remaining API-key storage risk. |
| Networking | Defaulted to an unofficial Google endpoint, allowed invalid URLs, did not consistently validate HTTP errors, and could fan out excessive work. | Default is offline/unconfigured; supported services require HTTPS, validate HTTP/JSON responses, coalesce identical requests, and limit active network translations to two. |
| Glossary | Global `space` replacement could change normal English sentences before translation. | Offline glossary applies only to a complete exact phrase; OpenAI-compatible translation receives non-binding shipping guidance. |
| Cache | Used a 64-bit FNV value under a SHA-256 name, stored sensitive output, had no expiry, and grew to 2,500 entries. | Uses SHA-256, expiry preference, maximum 750 entries, serialized writes, and offline cache hits when the configured provider is unchanged. |
| CI | The workflow built without source preflight validation. | Adds a static audit before the official RootHide-Theos build and verifies that a `.deb` artifact exists. |
| Translation layout | Fixed black labels could overlap one another, the floating ball and the screen edge. | Sparse pages use measured collision-aware cards; dense or unsatisfied layouts automatically move into one ordered, scrollable glass panel. |
| Interaction state | Region OCR, subtitles and chat could fail silently; the control menu always displayed both background modes as off. | Adds non-modal island-style state feedback, live menu state, delayed selector presentation after the action sheet, small-selection guidance and surfaced OCR/provider errors. |
| Continuous/chat intelligence | Subtitles required two identical frames and chat only inspected native UIKit labels. | Subtitles OCR every changed frame with duplicate/in-flight suppression; chat scans bottom-up and periodically falls back to on-device OCR when native text is absent or unchanged. |

## Verification completed here

- Every text source and configuration file decodes as UTF-8 with no replacement characters.
- `entitlements.plist`, `Preferences/Info.plist` and `Preferences/Resources/Root.plist` parse as XML plists.
- Source quote- and delimiter-balance scan passes; it caught and repaired a missing Microsoft request bracket before packaging.
- Static audit passes and is wired into the GitHub workflow.
- The source archive manifest was generated from the revised tree.

## Not reproducible in this Windows workspace

- Real RootHide Theos/iOS SDK arm64e compilation.
- Injection on the target iPhone; Bootstrap App List behavior on its current version.
- Vision OCR language availability, protected-video/Metal capture behavior and layout in individual UIKit/SwiftUI apps.
- Real API credentials, service policies, rate limits and translation quality.

These are not cosmetic caveats: a GitHub Actions arm64e build and one-App-at-a-time test on the phone remain necessary before daily use. Do not begin with banking, wallet, password or other sensitive apps.
