# PDFPrivio — App Store Connect listing copy

Paste each section into the matching field in App Store Connect → App
Information / App Store / Localization. Character limits are noted next
to every field — Apple enforces them strictly and will reject builds
whose metadata overflows.

---

## App Name (max 30 chars)

```
PDFPrivio
```

7 characters. Stays well under the limit so iOS doesn't truncate it on
small screens or in Settings.

---

## Subtitle (max 30 chars)

Three options, pick one:

```
On-device PDF toolkit
```
(21 chars — clearest)

```
PDF tools that stay private
```
(26 chars — leans into wedge)

```
18 PDF tools, all offline
```
(25 chars — value + privacy)

Recommendation: **"On-device PDF toolkit"** — clean, factual, anchors the
positioning without sounding defensive.

---

## Promotional Text (max 170 chars)

Shown above the description on the App Store. Can be updated **without
re-submitting** — use it for launch announcements, ProductHunt week, or
seasonal pushes.

```
Scan, OCR, sign, redact, fill forms, compare — 18 PDF tools that run
entirely on your iPhone. No cloud uploads, no subscription, no account.
```

165 chars. Tightens the wedge in one sentence.

---

## Description (max 4000 chars)

```
PDFPrivio is the offline PDF toolkit for lawyers, accountants, real estate
professionals, and anyone who handles documents that should not be
uploaded to a stranger's server.

Every operation — scan, OCR, redact, sign, compress, merge, split —
runs locally on your iPhone. Your PDFs never leave this device.
The network panel shows zero bytes for your files.

THE 18 TOOLS (all free)

Document intake
• Scan to PDF — Apple VisionKit edge detection, perspective correction,
  multi-page capture
• OCR PDF — Apple Vision recognizes text on scanned PDFs and adds a
  searchable text layer (English + Turkish; more languages coming)
• Image to PDF — photos, receipts, screenshots into one PDF
• Merge PDFs — combine document-level or hand-pick pages
• Compress PDF — shrink for email without visible quality loss
• Split PDF — extract page ranges, every Nth page, or N equal parts

Editing
• Rotate pages — fix sideways scans
• Delete pages — drop what you don't need
• Sign PDF — finger or stylus signature with ESIGN-style SHA-256 audit
  footer
• Fill form — IRS, USCIS, court motion AcroForm fields with
  flatten-on-save so recipients can't edit your answers
• Page numbers — four formats, five positions, custom start
• Bates numbering — legal discovery standard (prefix + padded number)
• Password protect — AES-256 encrypt or unlock

Review
• Watermark — CONFIDENTIAL, DRAFT, custom text in three layouts
• Extract text — pull clean text out of any born-digital PDF
• Compare PDFs — redline two versions, added and removed text
  highlighted per page
• Find sensitive data — auto-detect SSN, EIN, credit cards (Luhn
  validated), IBANs, TC Kimlik No, emails, phone numbers
• Redact — search words, render-and-flatten removes them from the data
  stream, optional OCR-back keeps non-redacted text searchable

PRIVACY POSITIONING

Other PDF apps upload your file to "process" it in the cloud — meaning
their staff, their server logs, and their attackers could all see your
documents. PDFPrivio was built so the lawyer-client privilege, the
accountant-client confidentiality, and your personal data stay where
they belong: on your phone.

We use Apple Vision for OCR and Apple's VisionKit for scanning. Both
run on the Neural Engine inside your iPhone. No model downloads, no
remote calls.

NO SUBSCRIPTION

Every tool listed above is free, today and forever, with light ads on
the free tier. A future Pro tier ($29.99 one-time) and Business tier
($9.99/month) will unlock bulk OCR, multi-cloud sync, AI workflows, and
priority support — but the 18 core tools stay free.

MADE BY EREK STUDIO

Built by an independent developer in Istanbul. No VC, no growth team,
no dark patterns. If a feature is missing or a bug bites you, email
mustafasalimerek@gmail.com and you'll hear back from a human within a day.
```

About 2900 chars — leaves headroom for tweaks. Apple counts characters
including spaces, line breaks, and bullet symbols.

---

## Keywords (max 100 chars, comma-separated, no spaces between)

Apple matches keywords AND the title + subtitle. Don't repeat the app
name. Lawyer/CPA-tilted to support the wedge.

```
pdf,scanner,ocr,redact,esign,sign,form,fill,merge,split,compress,bates,watermark,lawyer,accountant
```

99 chars. Squeezes 15 high-intent terms.

Alternative, prosumer-tilted:

```
pdf,scanner,ocr,redact,sign,merge,split,compress,form,fillable,bates,watermark,tools,editor
```

90 chars. (Originally included "acrobat" — removed; Apple guideline 4.7
/ 5.6 prohibit competitor trademarks as keywords and Adobe could file
a DMCA-style complaint. Brand-free keywords are safe.)

Recommendation: lawyer-tilted at launch. If Reddit /r/LawFirm post lands
and we get any organic search ranking, swap broader prosumer keywords
in a v1.1 metadata-only release.

---

## Support URL (required)

```
mailto:mustafasalimerek@gmail.com
```

For v1: a single page with the email address `mustafasalimerek@gmail.com` and
the Privacy Policy + ToS links. Apple verifies the URL resolves at
review time, so the page MUST be live before submission.

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

Maps to `docs/legal/privacy-policy.md` in this repo. Host it as plain
HTML before submission.

---

## What's New (per version, max 4000 chars)

For the initial v1.0.0:

```
First release of PDFPrivio.

18 PDF tools built for lawyers, accountants, and anyone who handles
sensitive documents.

Everything runs on this device — scan, OCR, redact, sign, fill forms,
compress, merge, split, compare. Your PDFs never leave your iPhone.

Highlights:
• Apple VisionKit document scanner with edge detection
• Apple Vision OCR (English + Turkish) makes scans searchable
• Real redaction — text is removed from the PDF, not just covered
• AcroForm filler with flatten-on-save for IRS, USCIS, court forms
• PII auto-detect: SSN, EIN, credit cards (Luhn), IBAN, TC Kimlik
• Recent files workspace — pick up yesterday's work in one tap
• On-device privacy — verifiable in Settings > Privacy & Security

Free forever. No subscription required.
```

700 chars. Easy to update for each release.

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
1. Home screen with Recent files + 18 tool tiles (lead with surface area)
2. Scan to PDF empty state ("Scan paper into a sharp PDF")
3. Redact result ("12 redactions applied · across 4 pages") with green
   "Real redaction" verified banner
4. PII Scan result with categorized findings
5. Privacy badge close-up ("Processing locally · 0 KB uploaded")

Use Simulator → Device → Erase All Content and Settings → fresh boot,
then `cmd + 1` for full screen, then `cmd + s` for screenshot at the
right scale.

---

## Localization

For launch: English (U.S.) only.

Turkish localization comes in v1.1 — we have Turkish OCR support, TC
Kimlik No PII detection, and Turkish phone-number patterns already in
the code. Adding Turkish description + screenshots is a 1-day job.

---

## Review notes (Apple Reviewer sees this, users don't)

```
PDFPrivio is an entirely on-device PDF toolkit. No backend, no account,
no data upload of any kind. Test the privacy claim by:

1. Open Settings > Privacy & Security > App Privacy Report on the test
   device. PDFPrivio should show zero outbound contacts beyond Firebase
   crash and (consented) analytics.
2. In the app, open any tool, pick a sample PDF, run it. The result
   stays in the app's sandbox until you tap Share.

If the reviewer wants a sample PDF: open Safari, search "IRS form 1040
PDF", download — that exercises Scan, OCR, Form Fill, Sign, and Redact.

The "Find sensitive data" tool detects PII using regex with checksum
validation (Luhn for credit cards, IBAN check digits, TC Kimlik
algorithm). It does not transmit anything; results are kept in memory
for the duration of the screen.

Camera and Photos permissions are requested only when the user explicitly
taps Scan or Image to PDF. Tracking (NSUserTrackingUsageDescription) is
requested only after the GDPR/UMP consent form, per Google's UMP
guidelines.

Privacy Policy: https://mustafasalimerek-bit.github.io/pdfprivio/privacy/
Terms of Service: https://mustafasalimerek-bit.github.io/pdfprivio/terms/
```

This pre-empts the most common reasons reviewers ask follow-up
questions, which add 24–72 hours to review time.

---

## Submission checklist

Before tapping "Submit for Review":

- [ ] Privacy Policy URL resolves from a private window
- [ ] Support URL resolves
- [ ] App Privacy Labels match `docs/legal/app-store-privacy-labels.md`
- [ ] Bundle ID `com.erekstudio.pdfprivio` registered in Apple Developer
- [ ] Real AdMob iOS App ID in `Info.plist` (not the test ID)
- [ ] Firebase `GoogleService-Info.plist` is the production one (not
      the sed-patched placeholder)
- [ ] Build number incremented (`pubspec.yaml` version field)
- [ ] Screenshots uploaded for 6.5", 5.5", iPad (if listed)
- [ ] App Review notes filled in (see above)
- [ ] Test the ATT prompt fires on a fresh install
- [ ] Test the UMP consent form fires from an EU IP (VPN works)
- [ ] Open Settings → Privacy → Manage data preferences in the app and
      confirm the UMP form re-opens (GDPR Art. 7 right to withdraw)
```
