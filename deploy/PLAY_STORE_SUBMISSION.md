# Submitting ConFriKa to the Google Play Store

The release **App Bundle** is built at:
`apps/mobile/build/app/outputs/bundle/release/app-release.aab`

Package: `com.confrika.confrika_mobile` · version `0.1.0+1` (versionName 0.1.0, versionCode 1).

---

## 0. Before you upload — read this about the signing key
The AAB is signed with an **upload key** at `apps/mobile/android/upload-keystore.jks`,
with credentials in `apps/mobile/android/key.properties` (both are gitignored).

**Back up that keystore file and its password somewhere safe and permanent.**
If you lose it you cannot publish updates (you'd have to reset the upload key via
Play support). The password generated for you this session is in `key.properties` —
copy it into your password manager now.

Enroll in **Play App Signing** (default for new apps): Google holds the real app
signing key; your upload key only signs uploads. This makes key loss recoverable.

---

## 1. Google Play Console account
- Create a developer account at https://play.google.com/console ($25 one-time).
- Complete identity/business verification (can take 1-2 days).

## 2. Create the app
- "Create app" → name **ConFriKa**, language, type **App**, Free.
- Accept the declarations.

## 3. Store listing
- **Short description** (≤80 chars): e.g. "Chat, call and translate across African languages — Connect Africa."
- **Full description**: pull from `website/index.html` copy.
- **App icon** 512×512 PNG (use `apps/mobile/assets/images/confrika_app_icon.png`, resized).
- **Feature graphic** 1024×500 PNG.
- **Phone screenshots** (min 2, 1080p+): splash, chat, call UI, communities, tonal coach, translate.
- Category: Communication (or Social). Add contact email + the privacy policy URL
  **https://confrika.online/privacy**.

## 4. App content (required declarations)
- **Privacy policy URL**: https://confrika.online/privacy
- **Data safety**: declare what you collect — account (email, name, country),
  messages (E2E encrypted DMs), audio (voice enrollment/calls), device identifiers
  (FCM token). Mark encryption in transit; declare data types honestly.
- **Content rating**: fill the questionnaire (likely Everyone / Teen depending on UGC).
- **Ads**: YES (AdMob) — declare the app contains ads.
- **Target audience**: 13+ (has user-generated content + comms).
- **Government apps / financial / health**: No.

## 5. Monetization setup (ConFriKa Pro)
- Play Console → Monetize → **Subscriptions** → create:
  - `confrika_pro_monthly` (base plan monthly, auto-renew)
  - `confrika_pro_yearly` (base plan yearly, auto-renew)
  - These IDs must match `PRO_PRODUCT_IDS` on the backend and `BillingService` in the app.
- For server-side verification: Play Console → API access → link a Google Cloud
  project → create a service account with the **Android Publisher** role →
  download its JSON → put it on the Fly volume and set
  `PLAY_SERVICE_ACCOUNT_FILE` (see `DEPLOY_PRODUCTION.md`).

## 6. Upload the release
- Release → Testing → **Internal testing** first (fastest; add your own email as a tester).
- Create a release → upload `app-release.aab` → add release notes → roll out.
- Install via the opt-in link, verify login/chat/calls/translate/paywall end to end.
- When happy, promote the same release to **Production**.

## 7. Pre-production checklist
- [ ] `api.confrika.online` is live and the AAB points to it.
- [ ] Real AdMob app id + unit ids replace the TEST ids.
- [ ] `BILLING_TRUST_UNVERIFIED=false` and Play service account configured.
- [ ] Privacy + terms reachable at confrika.online.
- [ ] Rotate any keys pasted in chat (GitHub, ElevenLabs).
- [ ] Keystore + password backed up off-machine.

> iOS: the Dart code is cross-platform, but the iOS app must be built and
> archived on a Mac with Xcode and submitted via App Store Connect ($99/yr).
> Create matching auto-renewable subscriptions there with the same product IDs.
