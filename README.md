# Privio

23 on-device PDF tools for iOS. Scan, OCR, sign, redact, fill IRS / USCIS forms, compare versions, summarise with Apple Intelligence, capture receipts to a QuickBooks-friendly CSV — all on the iPhone, none of it in the cloud.

## Stack

- **Flutter** (Dart 3.11+)
- **Riverpod** for state
- **PDFKit / pdfx / syncfusion_flutter_pdf** for PDF operations
- **Apple Vision** for on-device OCR (iOS)
- **VisionKit** for the document scanner
- **FoundationModels** (iOS 26+) for on-device summarisation
- **WidgetKit** for the Home Screen widget + iOS 18 Control Center / Lock Screen control
- **AppIntents** for Siri, Shortcuts, and Action Button binding
- **Hive** for the audit log + expense ledger
- **in_app_purchase** for Pro tier (monthly / yearly / lifetime)

## Positioning

- **On-device only** — files never leave the phone
- **Honest free tier** — 18 of 23 tools work without Pro (15 metered with daily caps, 3 unlimited: Bookmarks, Summarize, Live Text view)
- **Pro unlocks** — Form Fill, Bates numbering, Redact, Batch operations, Receipt scanner, removes daily caps on the other 15
- **One-time purchase option** — $79.99 Lifetime ends subscription fatigue
- **Built for the wedge** — lawyers, CPAs, prosumers who can't upload client/tax data to a SaaS

## Bundle

- iOS: `com.erekstudio.pdfprivio`
- Android: `com.erekstudio.pdfprivio` (Android target is v1.1; iOS-first ships v1.0)

## iOS integrations

- Home Screen widget (Small + Medium) with three Lock Screen accessory families
- Control Center / Lock Screen scan control (iOS 18+)
- Action Button binding via AppIntents (iPhone 15 Pro+)
- Share Extension + Action Extension (Quick Sign in any app's share sheet)
- Files Provider Extension (Privio surface in the Files app)
- iPad Stage Manager / Split View / Slide Over

## Development

```sh
flutter pub get
flutter run
```

## License

Proprietary. © Erek Studio.
