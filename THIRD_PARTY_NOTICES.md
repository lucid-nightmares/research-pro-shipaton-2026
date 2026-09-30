# Third-party notices and asset provenance

Research Pro's released project material is licensed under AGPL-3.0-or-later as described in `PUBLIC_RELEASE_LICENSING.md` and `LICENSE`. The components below keep their own licenses and attribution. Their notices are not replaced by the project license.

## citeproc-js 2.4.63

Bundled path: `mobile/research-os-ios/ResearchOSFlightRecorder/PublicationAssets/citeproc-2.4.63.js`.

Copyright (c) 2009–2019 Frank Bennett. citeproc-js implements the Citation Style Language. Project: <https://citationstyles.org/>. Upstream: <https://github.com/Juris-M/citeproc-js>.

The upstream license offers CPAL version 1-or-later or AGPL version 3-or-later. **This release selects AGPL-3.0-or-later for citeproc-js.** Preserve its original notice in the JavaScript header and the accompanying `CITEPROC-LICENSE.txt`, `CITEPROC-AGPLv3.txt`, `CITEPROC-CPAL.txt` and `CITEPROC-README.rst`. Both upstream license texts are retained unchanged; this does not impose both alternatives simultaneously.

The bundled processor is byte-identical to the 2.4.63 package source. Its SHA-256 is `55abba1a8b8b48c14323fd053f9646013b4b7a0c977938064ecf5195a502b9f1`. The asset manifest records the package, upstream revisions and hashes. No processor modification is made by this licensing update.

## Citation Style Language styles and locale data

The following separate data assets retain the **Creative Commons Attribution-ShareAlike 3.0 Unported** license: <https://creativecommons.org/licenses/by-sa/3.0/>.

| Asset in `PublicationAssets` | Attribution retained in its metadata |
|---|---|
| `apa.csl` | Brenton M. Wiernik and Andrew Dunning; APA Style 7th edition |
| `plos.csl` | Sebastian Karcher; contributor Patrick O'Brien; Public Library of Science style |
| `locales-en-US.xml` | Translators Andrew Dunning, Sebastian Karcher, Rintze M. Zelle, Denis Meier and Brenton M. Wiernik |

These assets come from the [Citation Style Language project](https://citationstyles.org/). Preserve all author, contributor and translator metadata, upstream license links, `CSL-STYLES-NOTICE.md` and `CSL-LOCALES-NOTICE.md`. The original bytes and metadata are unchanged in this release. Modifications to these data files must follow their own attribution/share-alike terms; the project's AGPL grant does not replace them.

Pinned source revisions: styles `8947960dc3c5133a873d77342c77c67300a2bc18`; locales `a89adece41013402236e2c9020972d7e931fbab8`. `ASSET-MANIFEST.json` supplies exact file hashes.

## RevenueCat and RevenueCatUI

Swift Package Manager resolves <https://github.com/RevenueCat/purchases-ios-spm> at version 5.84.0, revision `48601a7f742b05abcd9d9c7d3d768b97e800aa2c`. This source repository carries its package reference/lock, not a vendored SDK checkout. The resolved SDK retains the following MIT notice; retain its notices and privacy manifests in distributions that include it.

```text
MIT License

Copyright (c) 2024 RevenueCat, Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Published article used in regression fixtures

Kross E, Verduyn P, Demiralp E, Park J, Lee DS, Lin N, Shablack H, Jonides J, Ybarra O (2013). *Facebook Use Predicts Declines in Subjective Well-Being in Young Adults*. PLOS ONE 8(8): e69841. <https://doi.org/10.1371/journal.pone.0069841>.

Copyright 2013 Kross et al. The article's Creative Commons Attribution notice permits use, distribution and reproduction with original-author/source credit. Its original PDF/XML notice does not specify a license version; the fixture's provenance records that distinction and the separately retrieved metadata. Do not replace the article's terms with the application license or remove its correspondence/attribution metadata.

The original PDF is preserved byte for byte, SHA-256 `7ba9667c23217f8f2571181b40884ce2e3d6342613425b6232ad56ebbcfeea8d`. `ResearchOSFlightRecorderTests/Fixtures/RealSource/PROVENANCE.json` records source, permissions and extraction limits. Extracted text and the legacy archive fixture contain material from this article; artificial claims, annotations and expected results are explicitly QA examples, not the authors' findings or an independent scientific benchmark.

## Platform and development dependencies

SwiftUI, UIKit, Foundation, PDFKit, CoreText, JavaScriptCore, StoreKit and system SF Symbols are supplied by Apple's SDK/operating system and remain subject to Apple's terms. They are not redistributed as separately relicensed SDKs, system fonts or symbol collections here.

Python test/development packages, where referenced by the release, retain their own licenses. The requirements files describe installation dependencies; wheels, environments and those packages' source are not bundled. Distributors who add dependency binaries or source must retain the applicable upstream notices.

The project app icon is included in the project-material grant in `PUBLIC_RELEASE_LICENSING.md`. Existing inherited project credit is preserved there. This release does not grant rights in unrelated private research, historical repositories outside this scope, personal voice recordings, music, school branding or third-party logos.
