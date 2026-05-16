# PDFPrivio Privacy Policy

**Last updated:** 2026-05-15
**Effective date:** 2026-05-15
**Operator:** Erek Studio (Mustafa Salim Erek, sole proprietor)
**Contact:** mustafasalimerek@gmail.com  (← change to your real email before publishing)
**App:** PDFPrivio (iOS / Android), bundle id `com.erekstudio.pdfprivio`

This policy describes what data PDFPrivio does and does not collect, why, and what choices you have. It is written to be readable; the short version is at the top.

---

## TL;DR

- **Your PDFs and the text inside them never leave your device.** All processing — merge, split, scan, OCR, redaction, PII detection, signature, everything — runs locally on your iPhone or Android device. We never upload your documents to our servers, because we don't have servers that receive them.
- We use **Firebase Crashlytics** to learn when the app crashes, and **Firebase Analytics + Google AdMob** for anonymous usage stats and to show ads to users on the Free tier.
- We ask for your consent (GDPR / CCPA / Apple ATT) before turning on Analytics or personalized ads. You can decline; the app works the same.
- We do **not** sell your data, ever.

---

## 1. The data PDFPrivio **does not** collect

We want to be very explicit about this because it's the centerpiece of the product:

- The **contents of your PDFs** — text, images, signatures, tables, form fields, anything. Never transmitted off your device. Never stored on our servers.
- **OCR text** generated from your scans. Stays on your device.
- **PII Scan results** — SSNs, IBANs, account numbers, etc. that PDFPrivio detects in your documents. Detection runs locally; results are not transmitted.
- **File names** of the documents you open in PDFPrivio.
- **Your contacts, photos, calendar, or location.** PDFPrivio has no access to these except as you grant for a specific operation (e.g. the photo picker when you choose images to convert into a PDF), and any photos you pick are processed only in memory and never uploaded.

---

## 2. The data PDFPrivio **does** collect

### 2.1 Crash reports (Firebase Crashlytics)

When the app crashes we send an anonymized stack trace to Firebase Crashlytics so we can fix the bug. This includes:

- The Dart / native stack trace
- The model of your device (e.g. "iPhone 15 Pro")
- OS version
- App version
- A randomly generated install ID

This **does not** include the names of your files, the contents of any PDF, or any identifier that points back to you personally. Legal basis: legitimate interest in keeping the app stable.

You can opt out by not using the app; we do not currently expose a Crashlytics toggle.

### 2.2 Analytics (Firebase Analytics) — **off by default**

If, and only if, you give consent through the in-app prompt, PDFPrivio collects anonymous usage stats:

- Which screens you open and in what order (e.g. "Scan to PDF → Save")
- Which features you use (e.g. "Sign PDF used", "OCR PDF run")
- Approximate session length
- Device and OS version

We do **not** collect what's inside your documents, what you typed in search fields, or what files you operated on. Analytics is gated behind the Google UMP consent flow and disabled by default on every install.

### 2.3 Advertising (Google AdMob) — Free tier only

Free-tier users see banner / interstitial ads provided by Google AdMob. AdMob may use a device-level advertising identifier (IDFA on iOS, AAID on Android) to:

- Show you ads that are more relevant
- Limit ad frequency
- Measure ad performance

On iOS we ask you with the Apple App Tracking Transparency prompt before AdMob receives IDFA. If you decline, you'll still see ads — just non-personalized ones.

Google AdMob's privacy practices are described at <https://policies.google.com/technologies/partner-sites>.

Pro / Business tier users see no ads and we don't share any identifier with AdMob.

### 2.4 In-app purchases (Apple / Google)

If you upgrade to Pro or Business, the transaction is processed entirely by Apple's App Store or Google Play. PDFPrivio receives a receipt validation token from Apple/Google so it can unlock features locally; we don't see your payment method, credit card, or address. Apple's and Google's privacy policies cover that data:
- Apple: <https://www.apple.com/legal/privacy/>
- Google: <https://policies.google.com/privacy>

---

## 3. Consent flow

On first launch, you'll see (in order, where applicable):

1. **GDPR/CCPA consent form** (Google UMP) — shown automatically when your IP is in the EU, UK, Switzerland, certain US states, or other regulated regions. You can accept, reject, or customize what's used.
2. **Apple ATT prompt** (iOS only) — Apple's "Allow PDFPrivio to track your activity across apps and websites?" prompt. iOS shows this regardless of UMP and lets you decline IDFA access.

You can re-open the GDPR consent form any time from **Settings → Privacy → Manage data preferences** inside PDFPrivio. (Coming with the Settings screen in the next update.)

If you decline both, PDFPrivio still works exactly the same — you just see fewer relevant ads and no anonymous usage telemetry flows to us.

---

## 4. Storage on your device

PDFPrivio saves the following files in its sandbox on your device (which only PDFPrivio and you can access):

- Output PDFs you generate (merged, signed, redacted, OCR'd, etc.) — kept until you delete them or uninstall the app.
- Tool preferences (paper size, signature font, etc.) via `shared_preferences`.
- A small Hive database for things like recent files. Tiny, plain.
- Temporary cache of rasterized page images during OCR / redaction. Auto-cleared when you exit a tool.

None of this leaves your device unless you explicitly tap "Share" inside PDFPrivio (which uses the iOS / Android share sheet — sending the file goes to whichever app you pick).

## 5. Children's privacy

PDFPrivio is not directed at children under 13 (or the equivalent minimum age in your country). We do not knowingly collect personal information from children. If you believe a child has used PDFPrivio in a way that needed consent, contact us at mustafasalimerek@gmail.com.

## 6. Your rights

Depending on where you live (EU/UK/Switzerland under GDPR, California under CCPA, etc.) you have the right to:

- Know what data we hold about you (basically: the install-scoped anonymized analytics/crash records, if you consented).
- Ask us to delete it.
- Withdraw consent at any time via the in-app Settings screen.
- Lodge a complaint with your local data protection authority.

To exercise these rights, email mustafasalimerek@gmail.com from the email account you'd like the response sent to. We will respond within 30 days.

## 7. Data sales

We do **not** sell personal information. Not now, not in any planned future version. This applies to "sale" as defined under the California CCPA (broader than the everyday meaning of "sale").

## 8. International transfers

The minimal data we do collect (crash reports if you crash, anonymous events if you consented to analytics) is processed by Google Firebase. Firebase processes data in the United States and other countries. EU/UK Standard Contractual Clauses apply per Google's terms.

## 9. Security

We don't store your documents on our servers, so the typical "data breach" risk for SaaS products doesn't apply to PDFPrivio's design. The data we do receive — Crashlytics stack traces, anonymous analytics events — is held by Google Firebase under their security controls (<https://firebase.google.com/support/privacy>).

## 10. Changes to this policy

If we update this policy in a way that meaningfully changes what we collect or how we use it, we will note the change in the in-app "What's New" of the next update and reset the "Last updated" date at the top. Continued use of the app after the change constitutes acceptance.

## 11. Contact

- Email: mustafasalimerek@gmail.com
- Postal: Erek Studio, [your address — fill in before publishing]

We will respond to all good-faith privacy requests within 30 days.
