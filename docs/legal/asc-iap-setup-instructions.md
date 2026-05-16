# Chrome Claude talimat: ASC'de 3 IAP product aç

App Store Connect'te PDFPrivio için 3 in-app purchase product yaratacaksın.
Bu doküman komut tarafına yapıştırılacak prompt'tur. **Sıralama
kritik** — Subscription Group önce, ardından Monthly + Yearly aynı
grup içinde, Lifetime ayrı non-consumable olarak.

---

# PROMPT (Claude in Chrome'a yapıştır)

```
Görev: App Store Connect'te PDFPrivio (Apple ID 6769686204) için 3 in-app
purchase product açmak.

Ben Mustafa, ASC'de zaten login durumdayım. Sen browser otomasyonu
yapacaksın. Bu görev geri-dönüşü-zor adımlar içeriyor (IAP product ID
bir kere set edildi mi değiştirilemiyor) — her destructive aksiyon
öncesi bana onay sor.

## Bağlam — memory'den oku
Memory dosyaları:
- `~/.claude/projects/-Users-mse/memory/project_pdfprivio.md`
- `~/.claude/projects/-Users-mse/memory/project_pdfprivio_admob.md`
- `~/.claude/projects/-Users-mse/memory/project_pdfprivio_launch_checklist.md`

Canonical değerler:
- Apple App ID: `6769686204`
- Bundle ID: `com.erekstudio.pdfprivio`
- App adı: PDFPrivio
- Studio: Erek Studio

## Başlangıç URL
https://appstoreconnect.apple.com/apps/6769686204/distribution

Sol menüde "Monetization" başlığı altında "Subscriptions" ve
"In-App Purchases" göreceksin.

## ADIM 1 — Subscription Group "Pro" oluştur

URL: https://appstoreconnect.apple.com/apps/6769686204/distribution/subscriptions

1. "Create a Subscription Group" tıkla
2. Reference Name: `Pro`
3. Create

**Çıktı**: Group ID (Apple verir) screenshot'la, bana raporla.

## ADIM 2 — Monthly subscription ekle (Pro group içinde)

1. Pro group sayfasında "Create" / "Subscription" → "Auto-Renewable Subscription"
2. Form:
   - Reference Name: `PDFPrivio Pro Monthly`
   - Product ID: `com.erekstudio.pdfprivio.pro_monthly` ⚠️ aynen bu, değiştirme
3. Create (henüz Submit değil — review için ekstra info ister)
4. Açılan sayfada:
   - **Subscription Duration**: 1 Month
   - **Subscription Prices**: "Add Subscription Price" → seçilen base country
     "United States" → Price tier: `USD 4.99` (Tier 5 — Apple günceller)
     → Add → Save
   - **App Store Localization** (en-US):
     - Subscription Display Name: `PDFPrivio Pro Monthly`
     - Description: `Unlock the full toolkit — no daily limits, Form Fill,
       Bates numbering, Redact, and no ads. Auto-renews monthly until
       cancelled. Manage in Apple ID settings.`
   - **Review Information**:
     - Screenshot: SKIP for now (uploads later)
     - Review Notes: `Single-product subscription unlocking Pro features.
       Restoring on this Apple ID after a previous purchase grants the
       same entitlement. Test card: any sandbox tester. Verify by going
       to Settings → Subscription. The paywall is reachable via the Pro
       tab on the bottom nav or by tapping a Pro-only tool like
       "Find sensitive data → Redact all".`
5. **ONAY BEKLE**: "Save / Submit for Review yapayım mı?" diye sor. Onay
   olunca Save'e bas. (Submit for Review v1.0.0 binary uploaded'dan sonra
   yapılır — şimdi sadece Save.)

**Çıktı**: Monthly product status = "Missing Metadata" veya
"Ready to Submit" durumunu screenshot'la, bana raporla.

## ADIM 3 — Yearly subscription ekle (aynı Pro group)

1. Aynı Pro group sayfasında "Create Subscription"
2. Form:
   - Reference Name: `PDFPrivio Pro Yearly`
   - Product ID: `com.erekstudio.pdfprivio.pro_yearly` ⚠️ aynen
3. Create
4. Açılan sayfada:
   - **Subscription Duration**: 1 Year
   - **Subscription Prices**: US base → `USD 39.99` (Apple tier'ını seç)
   - **Localization**:
     - Display Name: `PDFPrivio Pro Yearly`
     - Description: `Best value — unlock the full toolkit for a year and
       save vs monthly. No daily limits, Form Fill, Bates, Redact, no ads.
       Auto-renews yearly until cancelled. Manage in Apple ID settings.`
   - **Review Information**: aynı yukarıdaki gibi
5. **ONAY BEKLE**: Save yap.

**Çıktı**: Yearly product status screenshot'la, raporla.

## ADIM 4 — Lifetime non-consumable ekle (ayrı, group değil)

URL: https://appstoreconnect.apple.com/apps/6769686204/distribution/iap

1. "Create" / "Non-Consumable" seç
2. Form:
   - Reference Name: `PDFPrivio Pro Lifetime`
   - Product ID: `com.erekstudio.pdfprivio.pro_lifetime` ⚠️ aynen
3. Create
4. Açılan sayfada:
   - **Pricing**: US base → `USD 79.99` (Tier 80)
   - **App Store Localization** (en-US):
     - Display Name: `PDFPrivio Pro Lifetime`
     - Description: `Pay once, own it forever. Unlocks the full PDFPrivio
       toolkit on this Apple ID — no daily limits, Form Fill, Bates,
       Redact, no ads. No subscription, no renewal email, no surprise
       charge in a year. Restoring on this Apple ID after purchase
       grants access on any device.`
   - **Review Information**: aynı (sample test instructions)
5. **ONAY BEKLE**: Save.

**Çıktı**: Lifetime product status screenshot'la, raporla.

## Sandbox tester (opsiyonel — sen söylersen geç)

Eğer sandbox tester yoksa şimdi açabiliriz:
URL: https://appstoreconnect.apple.com/access/users-and-access/sandbox

- "+" → Tester ekle
- Email: yeni bir email (gerçek değil, ama Apple sahte mail kabul etmez —
  test-pdfprivio@erekstudio.com gibi alias kullan)
- Password: güçlü bir test password
- Country: United States

Bana sor: "Sandbox tester açayım mı, yoksa atla?"

## OUTPUT — final rapor

Tüm 3 product oluştuktan sonra şu tabloyu bana ver:

| Product ID | Type | Price | Status |
|---|---|---|---|
| com.erekstudio.pdfprivio.pro_monthly | Auto-Renewable Subscription (1 month) | $4.99 | Missing Metadata / Ready to Submit |
| com.erekstudio.pdfprivio.pro_yearly | Auto-Renewable Subscription (1 year) | $39.99 | Missing Metadata / Ready to Submit |
| com.erekstudio.pdfprivio.pro_lifetime | Non-Consumable | $79.99 | Missing Metadata / Ready to Submit |

Sandbox tester yarattıysan:
- Email: ...
- Sonraki adım: Settings > Developer > Sandbox Account ile teste başla

## Hata durumunda

- "Product ID already exists" → durmadan beni uyar, bir önceki kuruluştan kalmış olabilir
- 2FA / captcha → bana bırak
- Screenshot upload required → "şimdi atla, sonra elle yükleyeceğim" diye not
- Pricing tier yoksa → en yakın olanı seç (4.99 ~= Tier 5, 39.99 ~= Tier 50,
  79.99 ~= Tier 80; Apple tarifeleri ülkeden ülkeye değiştirir — base
  country US olarak set et, gerisini Apple otomatik handle eder)

Hadi başla. Memory'i oku, sonra Adım 1'den başla.
```

---

# Sonraki adımlar (Mustafa, sen Chrome bittikten sonra)

1. **App Store screenshot al** — paywall + home + Pro screen — 6.5"
   iPhone simulator'da (1290×2796), Apple ASC review için her 3 IAP'a
   1242×2208 minimum upload gerekir
2. **Localization** ekle — TR + ES + DE + FR (memory'de Tier 1 dilleri)
3. **Submit for Review** — ASC'de v1.0.0 binary upload + IAP'leri ekle

ASC'de 3 IAP "Missing Metadata" durumda kaldığı sürece kullanıcı Buy
butonuna basınca PaywallSheet "This pricing option isn't available
yet" snackbar gösterir — kod zaten bu durumu gracefully handle ediyor.
