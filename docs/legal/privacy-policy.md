# Privio Privacy Policy

**Last updated:** 2026-05-18
**Effective date:** 2026-05-18
**Operator:** Erek Studio (Mustafa Salim Erek, sole proprietor)
**Contact:** mustafasalimerek@gmail.com
**App:** Privio (iOS), bundle id `com.erekstudio.pdfprivio`

This policy describes what data Privio does and does not collect. The short version is at the top.

---

## TL;DR

Privio collects nothing. There is no analytics, no crash reporting, no advertising, no tracking, no account, and no server to send anything to. Every PDF you scan, sign, redact, OCR, or convert stays on your iPhone. The app cannot read your files even if it wanted to — they never leave your device.

The only outbound activity that ever happens is what *you* explicitly tap: the iOS Share Sheet to send a finished PDF to another app, or an in-app purchase to Apple's App Store.

---

## 1. What Privio does not collect

This is the centerpiece of the product. Privio does not collect, transmit, or have any access to:

- **The contents of your PDFs** — text, images, signatures, tables, form fields, anything.
- **OCR text** extracted from your scans.
- **PII Scan results** — SSNs, IBANs, account numbers, credit card numbers, or any other sensitive pattern Privio detects locally in your documents.
- **File names** of the documents you open.
- **Your contacts, calendar, location, microphone, or any other system data** outside of the explicit per-feature permissions described in section 3.
- **Crash reports.** Privio does not include any crash-reporting framework (Firebase Crashlytics, Sentry, Bugsnag, etc.).
- **Analytics.** Privio does not include any analytics framework (Firebase Analytics, Mixpanel, Amplitude, etc.). We do not know how often you open the app, which tools you use, or how long your sessions are.
- **Advertising identifiers.** Privio has no advertising SDK and never accesses your IDFA. iOS does not prompt you with an App Tracking Transparency dialog when you open Privio because we have nothing to track.
- **Account data.** Privio has no account system. You don't sign up, log in, or hand us any identifier.

There are no servers operated by Erek Studio that receive your data, because there are no servers in this product.

---

## 2. What Privio actually does collect

Strictly limited to what is unavoidable for the app to function on Apple's platform:

### 2.1 In-app purchases (Apple StoreKit)

If you upgrade to Privio Pro, the transaction is processed entirely by Apple's App Store. Apple shares a receipt validation token with the app so Privio can unlock paid features locally on your device. We never see your payment method, credit card number, billing address, or Apple ID.

Apple's privacy policy covers any data Apple itself collects during the purchase: <https://www.apple.com/legal/privacy/>.

### 2.2 Optional Apple-level diagnostic sharing (off by default)

iOS offers a global toggle at **Settings → Privacy & Security → Analytics & Improvements → Share with App Developers**. If you have turned this on system-wide, Apple may forward anonymous crash reports for any app — including Privio — to its App Store Connect dashboard, where we can read them in aggregate.

- This is **off by default** on every iPhone.
- We do not control whether you have it on; Apple does.
- The reports never include your file contents, file names, or any identifier we could link back to you personally.
- You can turn it off at any time in iOS Settings without affecting how Privio works.

That is the entire list. There is nothing else.

---

## 3. Permissions you may grant

Privio asks for the following permissions only at the moment you use the relevant feature:

| Permission | When asked | What we do with it |
|---|---|---|
| **Camera** | First time you open the document scanner | Capture pages in memory, hand them to iOS VisionKit for cropping + enhancement, write the finished PDF to your app sandbox. The camera is closed the moment the scan completes. |
| **Photo Library** | First time you pick photos for image-to-PDF | Read only the photos you select. iOS limits us to those specific images. They are processed in memory and the resulting PDF is written to your app sandbox. The originals stay untouched. |

If you decline either permission, the corresponding feature is disabled but the rest of the app works normally.

We do not request location, contacts, microphone, calendar, motion, or any other permission Privio does not need.

---

## 4. Storage on your device

Privio writes the following files inside its iOS sandbox (which only Privio and you, through the Files app, can read):

- Output PDFs you generate — kept until you delete them or uninstall the app.
- Tool preferences (paper size, signature font, display name, theme, etc.) via iOS UserDefaults.
- A small local database (Hive) for things like recent files and the optional audit log.
- A temporary cache of rasterised page images during OCR / redaction, cleared automatically when you leave a tool.

None of these ever leave your device unless you explicitly tap **Share** inside Privio. The iOS Share Sheet then sends the file to whatever app you pick (Mail, Files, AirDrop, etc.). What that destination app does with the file is governed by that app's own privacy policy, not ours.

---

## 5. Children's privacy

Privio is not directed at children under 13. Because we collect no personal information at all, we have nothing to collect from a child either. If you believe a child has used Privio in a way that needs your attention, contact us at mustafasalimerek@gmail.com.

---

## 6. Your rights (GDPR / CCPA / similar regimes)

You have the right to:

- Know what personal data we hold about you. **The answer is: none.**
- Have us delete it. **The answer is: there is nothing to delete.**
- Withdraw consent. **You did not give us any consent because we never asked for any.**
- Lodge a complaint with your local data protection authority if you believe we are mishandling your data.

If you'd still like a written confirmation of "Privio holds no data about you" for your own records, email mustafasalimerek@gmail.com and we will respond in writing within 30 days.

---

## 7. Sale of data

We do not sell personal information. We have no personal information to sell. This satisfies California CCPA's "Do Not Sell My Personal Information" requirement trivially.

---

## 8. International transfers

Not applicable. Privio does not transfer any user data anywhere. Apple's separate handling of App Store purchase data is governed by Apple's privacy policy.

---

## 9. Security

There is no central database, no cloud backup of your PDFs, no server that could be breached, and no third party that holds your data. The standard SaaS data-breach risk does not apply to Privio's design.

Your files live in Privio's iOS app sandbox, which is encrypted by iOS as long as you have a passcode set on your iPhone. Set a passcode.

---

## 10. Changes to this policy

If we ever change Privio's data practices, we will rewrite this policy, post the new version under the same URL, and update the "Last updated" date at the top. Material changes will be noted in the in-app **What's New** of the next update.

---

## 11. Contact

- Email: mustafasalimerek@gmail.com

We respond to all good-faith privacy questions within 30 days.
