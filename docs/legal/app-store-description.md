# Privio — App Store Connect listing copy

Paste each section into the matching field in App Store Connect → App
Information / App Store / Localization. Character limits are noted next
to every field — Apple enforces them strictly and will reject builds
whose metadata overflows.

Most of these fields were already entered into App Store Connect for
the initial submission (see commit `7794dbd` and follow-up sessions).
This file is the source of truth — keep it in sync with what is live
in App Store Connect.

---

## App Name (max 30 chars)

```
PDF Scanner & Editor: Privio
```

28 characters. Keyword-loaded for App Store search ("PDF Scanner",
"PDF Editor") with the brand at the end, following Sebastian Röhl's
Habit Kit playbook. The home-screen display name on iOS is the shorter
brand-only **"Privio"** via `CFBundleDisplayName` in `Info.plist`.

---

## Subtitle (max 30 chars)

```
Sign, OCR, Redact, Fill Forms
```

29 characters. Pure keyword density — no word repeats anything in the
App Name (Apple indexes name + subtitle as one string, so duplicates
waste your budget). The privacy / on-device wedge moves to Promotional
Text + screenshots, not subtitle.

---

## Promotional Text (max 170 chars)

Shown above the description on the App Store. Can be updated **without
re-submitting** — use it for launch announcements, ProductHunt week, or
seasonal pushes.

```
23 PDF tools that never leave your iPhone - scan, sign, redact, fill forms, OCR. Private by design, works offline. No tracking ever.
```

132 chars. Tightens the wedge in one sentence.

---

## Description (max 4000 chars)

```
Privio is the offline PDF toolkit for lawyers, accountants, real estate professionals, and anyone who handles documents that should not be uploaded to a stranger's server.

Every operation — scan, OCR, redact, sign, summarise with Apple Intelligence, capture receipts — runs locally on your iPhone. Your PDFs never leave this device. The App Privacy Report shows zero outbound traffic for your files.

THE 23 TOOLS

Document intake
• Scan to PDF — Apple VisionKit edge detection, multi-page capture
• OCR PDF — Apple Vision recognizes text on scanned PDFs and adds a searchable text layer
• Image to PDF — photos, receipts, screenshots into one PDF
• Merge PDFs — combine document-level or hand-pick pages
• Compress PDF — shrink for email without visible quality loss
• Split PDF — extract page ranges, every Nth page, or N equal parts

Editing
• Rotate pages — fix sideways scans
• Delete pages — drop what you don't need
• Sign PDF — finger or stylus signature with SHA-256 audit footer
• Fill form (Pro) — IRS, USCIS, court motion forms with flatten-on-save
• Page numbers — four formats, five positions, custom start
• Bates numbering (Pro) — legal discovery standard
• Password protect — AES-256 encrypt or unlock

Review
• Watermark — CONFIDENTIAL, DRAFT, custom text in three layouts
• Extract text — pull clean text out of any born-digital PDF
• Compare PDFs — redline two versions, added and removed text
• Bookmarks / TOC — jump to any chapter in long briefs and depositions
• Find sensitive data — auto-detect SSN, EIN, credit cards (Luhn validated), IBANs, emails, phone numbers
• Redact (Pro) — search words, render-and-flatten removes them from the data stream

AI + receipts + batch (Pro on the last two)
• Summarize PDF — Apple Intelligence on-device summary (iOS 26+)
• Live Text view — Apple Live Text + Visual Look Up + Markup
• Batch operations (Pro) — compress, watermark, or rotate a stack of PDFs in one pass
• Receipt scanner (Pro) — auto-extract date / vendor / total / tax → QuickBooks-friendly CSV

iOS INTEGRATION

Home Screen widget (Small + Medium) plus three Lock Screen accessory families. iOS 18 Control Center / Lock Screen scan control. Action Button binding for iPhone 15 Pro and later. Siri, Shortcuts, Files Provider, Share Sheet, Action Extension. iPad Stage Manager + Split View.

PRIVACY POSITIONING

Other PDF apps upload your file to "process" it in the cloud — meaning their staff, their server logs, and their attackers could all see your documents. Privio was built so the lawyer-client privilege, the accountant-client confidentiality, and your personal data stay where they belong: on your phone.

Privio is built with Apple's own frameworks — VisionKit for scanning, Apple Vision for OCR, Apple Intelligence for summarisation, PDFKit for assembly. There are no third-party analytics, no crash-reporting SDK, no advertising SDK, no tracking, no account. The app shows "Data Not Collected" on its App Store privacy page.

PRICING

18 of 23 tools work for free (15 with daily caps, 3 unlimited). Pro removes the caps and unlocks Fill form, Bates numbering, Redact, Batch operations, and Receipt scanner:

• Monthly — $4.99
• Yearly — $39.99 (best value)
• Lifetime — $79.99 (one-time, no renewal)

There are no ads in any tier — Privio contains zero advertising SDKs.

MADE BY EREK STUDIO

Built by an independent developer in Istanbul. No VC, no growth team, no dark patterns. If a feature is missing or a bug bites you, email mustafasalimerek@gmail.com and you'll hear back from a human within a day.
```

About 3700 chars. Apple counts characters including spaces, line breaks, and bullet symbols.

---

## Keywords (max 100 chars, comma-separated, no spaces between)

```
signature,merge,split,compress,convert,jpg,word,document,receipt,watermark,offline,private,expense
```

98 chars. Live in App Store Connect since the initial metadata pass.

Notes on the choices:

- No word from the App Name ("scanner", "editor") or Subtitle ("sign", "ocr", "redact", "fill", "forms") — Apple treats name + subtitle + keywords as one index, so any duplicate burns characters for zero ranking benefit.
- "convert" + "jpg" + "word" + "document" cover the PDF → other-format searches.
- "signature" is the noun form (not "sign" → already in subtitle).
- "offline" + "private" are the differentiator hooks.
- "receipt" + "expense" lean into the CPA / freelancer wedge.
- "watermark" catches a high-volume specialised search.
- "compress" + "merge" + "split" are core PDF tool searches.

Excluded by Apple's rules: competitor names ("acrobat", "pdfelement", "wondershare") — Guideline 4.7 / 5.6.

---

## Support URL (required)

```
mailto:mustafasalimerek@gmail.com
```

For v1: a single page with the email address `mustafasalimerek@gmail.com` and the Privacy Policy + ToS links. Apple verifies the URL resolves at review time, so the page MUST be live before submission.

---

## Marketing URL (optional but recommended)

```
https://mustafasalimerek-bit.github.io/pdfprivio/
```

The landing page. Drives ProductHunt and Reddit traffic.

---

## Privacy Policy URL (required)

```
https://mustafasalimerek-bit.github.io/pdfprivio/privacy/
```

Maps to `docs/legal/privacy-policy.md` in this repo. Host it as plain HTML before submission.

---

## What's New (per version, max 4000 chars)

For the initial v1.0.0:

```
First release of Privio.

23 PDF tools built for lawyers, accountants, and anyone who handles sensitive documents.

Everything runs on this device — scan, OCR, redact, sign, fill forms, compress, merge, split, compare, summarise, capture receipts. Your PDFs never leave your iPhone.

Highlights:
• Apple VisionKit document scanner with edge detection
• Apple Vision OCR makes scanned PDFs searchable
• Real redaction — text is removed from the PDF, not just covered
• AcroForm filler with flatten-on-save for IRS, USCIS, court forms
• PII auto-detect: SSN, EIN, credit cards, IBAN, email, phone
• Apple Intelligence summary (iOS 26+) — on-device, never uploaded
• Receipt scanner — auto-extract date / vendor / total → QuickBooks CSV
• Batch operations — compress / watermark / rotate stacks of PDFs
• Home Screen widget + iOS 18 Control Center / Lock Screen scan control
• Action Button binding for iPhone 15 Pro+
• On-device privacy — verifiable in Settings > Privacy & Security
• Zero analytics, zero crash reporting, zero advertising, zero tracking

18 of 23 tools free (15 with daily limits + 3 unlimited). Pro unlocks unlimited access plus Fill form, Bates, Redact, Batch, and Receipt scanner.
```

About 1050 chars. Easy to update for each release.

---

## Age Rating

Set to 4+ (no objectionable content). No reasons to flag higher.

---

## Category

- **Primary**: Productivity
- **Secondary**: Business

Both are good fits for the App Store algorithm and the lawyer/CPA
wedge. Productivity gets us featured in "Best Productivity Apps"
roundups; Business reaches the prosumer segment.

---

## Screenshots required (per device type)

App Store Connect needs screenshots for:
- **6.5" iPhone** (iPhone 14 Pro Max or 15 Pro Max) — REQUIRED
- **5.5" iPhone** (iPhone 8 Plus) — REQUIRED for older catalog
- **12.9" iPad Pro** — REQUIRED if listed as iPad-compatible

For v1, target 5 screenshots showing:
1. Privacy banner — big "Never leaves your iPhone" hero with a tiny PDF icon (lead with the differentiator, Sebastian "first screenshot is the most impressive feature")
2. Home screen with Recent files + 23 tool tiles (surface area)
3. Scan to PDF flow — VisionKit capture with auto-edge
4. Redact result ("12 redactions applied · across 4 pages") with green "Real redaction" verified banner
5. PII Scan result with categorised findings

Use Simulator → Device → Erase All Content and Settings → fresh boot, then `cmd + 1` for full screen, then `cmd + s` for screenshot at the right scale.

---

## Localization

For launch: English (U.S.) only.

Turkish localization comes in v1.1 — we have Turkish OCR support, TC Kimlik No PII detection, and Turkish phone-number patterns already in the code. Adding Turkish description + screenshots is a 1-day job.

---

## Review notes (Apple Reviewer sees this, users don't)

```
Privio is an entirely on-device PDF toolkit. No backend, no account, no third-party analytics SDK, no crash-reporting SDK, no advertising SDK, and no data upload of any kind.

How to verify the on-device claim during review:

1. Open Settings → Privacy & Security → App Privacy Report on the test device after running Privio for a few minutes. Privio should show zero outbound network contacts beyond Apple's own StoreKit (for the optional in-app purchase flow).

2. In the app, open any tool, pick a sample PDF, run it. The result stays in the app's sandbox until the user explicitly taps Share, which invokes the standard iOS Share Sheet.

If the reviewer wants a sample PDF: open Safari, search "IRS form 1040 PDF", download — that single PDF exercises Scan, OCR, Form Fill, Sign, and Redact.

The "Find sensitive data" tool detects PII using regex with checksum validation (Luhn for credit cards, IBAN check digits, TC Kimlik algorithm). It does not transmit anything; results are kept in memory for the duration of the screen.

Camera and Photos permissions are requested only when the user explicitly taps Scan or Image to PDF. There is no ATT prompt because Privio has no advertising SDK and never accesses the IDFA — there is nothing to track.

The App Privacy form in App Store Connect is filled with "No, we do not collect data from this app" — this is truthful (see docs/legal/app-store-privacy-labels.md in the source repo for the per-SDK breakdown).

Privacy Policy: https://mustafasalimerek-bit.github.io/pdfprivio/privacy/
Terms of Service: https://mustafasalimerek-bit.github.io/pdfprivio/terms/
```

This pre-empts the most common reasons reviewers ask follow-up questions, which add 24–72 hours to review time.

---

## Submission checklist

Before tapping "Submit for Review":

- [ ] Privacy Policy URL resolves from a private window (Cork / California / Singapore IPs)
- [ ] Terms of Service URL resolves
- [ ] Support URL resolves (or mailto: opens correctly)
- [ ] App Privacy form in ASC matches `docs/legal/app-store-privacy-labels.md` — all "No" on Question 1
- [ ] Bundle ID `com.erekstudio.pdfprivio` registered in Apple Developer
- [ ] Build number incremented (`pubspec.yaml` version field, currently `1.0.0+4`)
- [ ] Screenshots uploaded for 6.5", 5.5", iPad (if listed)
- [ ] App Review notes pasted in (see above)
- [ ] Privacy Manifest (`PrivacyInfo.xcprivacy`) tracking arrays are empty and only required-reason APIs are declared
- [ ] `otool -L Runner.app/Runner | grep -v System` shows no third-party data-collection frameworks (no Firebase, no AdMob, no Sentry, etc.)
- [ ] On-device smoke test: Scan, Sign, OCR, Redact, Merge, Compress, Split each produce a valid output PDF on a real iPhone
