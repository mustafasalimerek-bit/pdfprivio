# App Store Privacy "Nutrition Labels" — fill-in checklist

Apple App Store Connect (App → App Privacy) requires every shipping app to declare what data it collects, in 14 categories. Below is exactly how to answer for PDFPrivio. **Verify each line before submitting — Apple Reviewers do not forgive incorrect labels.**

Console URL when ready: <https://appstoreconnect.apple.com/apps/{APPLE_ID}/distribution/privacy>

---

## Question 1: "Do you or your third-party partners collect data from this app?"

**Answer: Yes.**

(We don't collect anything about *the user's content*, but Crashlytics + Analytics + AdMob count as data collection per Apple's definition.)

---

## Question 2: Data types collected

Apple lists 14 top-level categories. For each, we declare:

| Category | Collected? | Notes |
|---|---|---|
| **Contact Info** (name, email, phone, address, other contact info) | **No** | We don't ask for any of these. |
| **Health & Fitness** | **No** | |
| **Financial Info** (payment info, credit info, other financial info) | **No** | Purchases handled by Apple; we never see the payment. |
| **Location** (precise, coarse) | **No** | |
| **Sensitive Info** (religion, sexual orientation, etc.) | **No** | |
| **Contacts** | **No** | |
| **User Content** (emails or text msgs, photos, videos, audio, gameplay, customer support, other content) | **No** ⚠️ | This is the **big one** for a PDF app. Make absolutely sure you select **No**. The user's PDFs are processed entirely on-device and never transmitted to us. Selecting "Yes" here would be incorrect and would also signal to lawyers/CPAs that we DO see their files — kills the wedge. |
| **Browsing History** | **No** | |
| **Search History** | **No** | |
| **Identifiers** (user ID, device ID) | **Yes (one item: Device ID)** | Only when user grants ATT consent → AdMob receives IDFA. See section 3 below. |
| **Purchases** (purchase history) | **No** | Apple handles; we don't store our own purchase records. |
| **Usage Data** (product interaction, advertising data, other usage) | **Yes (two items)** | See section 3 below. |
| **Diagnostics** (crash data, performance data, other diagnostic data) | **Yes (two items)** | See section 3 below. |
| **Other Data** | **No** | |

---

## Question 3: For each collected data type, link details

Apple asks per-data-type: (a) collected? (b) linked to identity? (c) used for tracking? (d) purpose(s)?

### 3.1 Device ID (IDFA, only when user opts in via Apple ATT)

- Linked to user's identity? **No**
- Used for tracking? **Yes**
- Purposes: **Third-Party Advertising**

> Apple defines "tracking" as linking a user's data with third-party data for ads or measurement, OR sharing IDFA with a data broker. AdMob receives IDFA only after the user accepts ATT → check this box honestly. If we set "Used for tracking? = No" we'd be lying to Apple and to users.

### 3.2 Product Interaction (Firebase Analytics, only when user consents via UMP)

- Linked to user's identity? **No**
- Used for tracking? **No**
- Purposes: **Analytics**

### 3.3 Advertising Data (AdMob)

- Linked to user's identity? **No**
- Used for tracking? **Yes**
- Purposes: **Third-Party Advertising**

### 3.4 Crash Data (Firebase Crashlytics)

- Linked to user's identity? **No**
- Used for tracking? **No**
- Purposes: **App Functionality**

### 3.5 Performance Data (Firebase Crashlytics / Firebase Analytics)

- Linked to user's identity? **No**
- Used for tracking? **No**
- Purposes: **App Functionality, Analytics**

---

## Question 4: Privacy Policy URL

Put `https://mustafasalimerek-bit.github.io/pdfprivio/privacy/` (once the page is up at that path).

Same URL goes into:
- App Store Connect → App Privacy → Privacy Policy URL
- App Store Connect → App Information → Privacy Policy URL (yes, two places)
- Google Play Console → Policy → App content → Privacy policy

---

## Question 5: Data not collected — the on-device wedge

There is no Apple field for this, but in marketing copy / App Store description / app's privacy screen we should hammer:

> *"All processing happens on this device. Your PDFs, your scans, your signatures, your redactions — never uploaded, never seen by us, never seen by anyone else. No account required."*

This is the lawyer-wedge headline. Don't bury it.

---

## When to re-check this file

- Before every App Store submission (resubmissions reset the labels for review).
- Whenever you add a new third-party SDK. Each SDK has its own data collection — add it here and to the categories above.
- Whenever Apple changes the categories (rare, but happens). Check the App Privacy Details questions page in App Store Connect for any new questions.

## Common reviewer rejections to pre-empt

- **"We can see your app stores user content."** Often triggered by anything that backs up to iCloud. PDFPrivio's outputs go to the app sandbox and the user's Files via the share sheet — we don't initiate iCloud sync ourselves. If Apple flags this, point to our privacy policy section 4.
- **"Tracking is enabled but ATT prompt is missing."** Make sure `NSUserTrackingUsageDescription` is in Info.plist (already added) and `ConsentService.gather()` runs at app start (already wired). If the reviewer is in a region where UMP returns "not required", they should still see ATT.
- **"Privacy Policy URL inaccessible."** Test the URL from a private browser window 1 hour before submission. Apple Reviewers' IPs are often in California / Singapore / Cork — make sure your hosting doesn't geo-block.
