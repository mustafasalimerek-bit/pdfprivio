# App Store Privacy "Nutrition Labels" — fill-in checklist

Apple App Store Connect (App → App Privacy) requires every shipping app to declare what data it collects across 14 categories. **Privio is unusual: the answer is "nothing" for every category.** Here is how to fill the form.

Console URL: <https://appstoreconnect.apple.com/apps/{APPLE_ID}/distribution/privacy>

---

## Question 1: "Do you or your third-party partners collect data from this app?"

**Answer: No.**

This is the truthful answer because:

- Privio includes **zero analytics SDKs** (no Firebase Analytics, Mixpanel, Amplitude, PostHog, etc.).
- Privio includes **zero crash-reporting SDKs** (no Crashlytics, Sentry, Bugsnag).
- Privio includes **zero advertising SDKs** (no AdMob, AppLovin, Unity Ads).
- Privio has **no account system**. No signup, no login, no user ID.
- Privio has **no backend server**. There is no API call that leaves the device with user content.
- Apple's StoreKit handles in-app purchases — that data sits inside Apple, not us. App Privacy explicitly excludes data Apple collects on Apple's own behalf during the purchase flow.

Once you select **No** here, the rest of the App Privacy form collapses — no further data-type questions, no per-type tracking disclosures, no ATT disclosure. Privio will appear in the App Store with the **"Data Not Collected"** label at the top of its privacy section, which is the single strongest visual signal a privacy-positive app can earn on the Store.

---

## Question 2: Privacy Policy URL

Put `https://mustafasalimerek-bit.github.io/pdfprivio/privacy/` (once the page is live at that path).

Same URL goes into:

- App Store Connect → **App Privacy → Privacy Policy URL**
- App Store Connect → **App Information → Privacy Policy URL** (yes, two places)

---

## When to re-check this file

- **Before every App Store submission.** Apple's privacy labels reset for review on resubmission.
- **The moment you add any third-party SDK.** If you ever wire in analytics, crash reporting, ads, or any framework that phones home, this form must be re-filled with the truthful new answer. Both this file and `privacy-policy.md` must change together — a mismatch between the binary, the App Privacy form, and the published policy is a Guideline 5.1.1 rejection.

---

## Common reviewer rejections to pre-empt

- **"We can see your app stores user content."** Often triggered by anything that backs up to iCloud automatically. Privio's outputs go to the app sandbox and into the user's Files via the iOS share sheet — Privio does not initiate iCloud sync. If Apple flags this, point to `privacy-policy.md` section 4.
- **"Privacy Policy URL inaccessible."** Test the URL from a private browser window 1 hour before submission. Apple Reviewers' IPs are typically in California / Cork / Singapore — make sure GitHub Pages does not geo-block.
- **"Mismatch between stated SDKs and binary scan."** Apple's automated SDK scan can detect bundled third-party frameworks. If a transitive dependency ever pulls one in, the binary will say "uses X" but App Privacy still says "No data collection". Run `otool -L Runner.app/Runner | grep -v System` before submission to see what is actually linked. Currently the only third-party frameworks are Apple's own (Flutter, VisionKit, PDFKit) and Apple-distributed helpers — no data collectors.

---

## Marketing copy reinforcement

Apple gives you the "Data Not Collected" badge automatically once Question 1 is **No**, but you still need to hammer the message in places users look first: app description, screenshots, in-app onboarding.

Suggested headline copy:

> *"All processing happens on this iPhone. Your PDFs, scans, signatures, redactions — never uploaded, never seen by us, never seen by anyone else. No account, no analytics, no ads."*

This is the lawyer-wedge headline. Do not bury it.
