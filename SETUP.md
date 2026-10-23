# ConFriKa — Production integrations setup

Everything below is wired in the code and runs in **stub mode** until you supply
the credentials. Put secrets in `deploy/.env` (already has labelled placeholders);
never commit real keys.

Domain: **confrika.online**

---

## 1. Email (Resend) — so OTP/reset/verify reach all users

1. **resend.com → Domains → Add Domain** → `confrika.online`.
2. Resend shows DNS records unique to your account (MX, SPF/TXT, DKIM, optional
   DMARC). Add each **at confrika.online's DNS host** (your registrar), exactly as
   shown. If it auto-appends the domain, enter just the host part (e.g. `send`,
   `resend._domainkey`).
3. Click **Verify** in Resend (propagation: minutes–hours).
4. **API Keys → Create API Key** → copy the `re_...` value.
5. In `deploy/.env`: set `EMAIL_API_KEY=re_...` and switch
   `EMAIL_FROM` to the `noreply@confrika.online` line (uncomment it).
6. Restart backend: `docker compose -f deploy/docker-compose.yml up -d --build backend`.

## 2. Push notifications (Firebase Cloud Messaging)

Backend is ready (`device_tokens` table, `POST /api/v1/auth/me/devices`,
`PushService`). To go live:

1. **console.firebase.google.com → Add project** (ConFriKa).
2. **Add Android app**, package name **`com.confrika.confrika_mobile`** →
   download **`google-services.json`** → place in `apps/mobile/android/app/`.
3. **Project settings → Service accounts → Generate new private key** → save the
   JSON and mount it into the backend container; point `FCM_CREDENTIALS_FILE` at
   it and set `FCM_PROJECT_ID` in `deploy/.env`.
4. (Client step, after `google-services.json` exists) add `firebase_messaging` to
   the app and call `POST /auth/me/devices` with the FCM token on login. *(Held
   until the json is present, since the app can't build Firebase without it.)*

## 3. Live in-call speech-to-speech translation (your voice)

Backend is ready (`VoiceService`, `POST /api/v1/calls/translate-utterance`).
Pipeline: **STT → NLLB translate → voice-clone TTS**, so the listener hears the
translation in the speaker's own voice (~1.5–3s behind — unavoidable latency).

1. **elevenlabs.io** → sign up (paid plan for real-time + instant voice cloning).
2. **API Keys → Create** → copy the `sk_...` value.
3. In `deploy/.env`: set `VOICE_API_KEY=sk_...` (provider already `elevenlabs`).
4. Restart backend. The call screen's **Translate** button then streams utterances
   through the endpoint and plays back the translated, voice-matched audio.
   *(Per-user voice cloning: a short enrollment sample creates the `voice_id`.)*

> Prefer a different provider (Azure Speech, Google, Cartesia)? Say so and the
> `VoiceService` provider block adapts — the rest of the pipeline is unchanged.

---

## iOS build (needs a Mac + Xcode + Apple Developer account)

The Dart code and every package are iOS-compatible; permissions are declared in
`ios/Runner/Info.plist` (mic, camera, photo library, Bluetooth, background audio/
voip/remote-notification). To produce an iOS build on a Mac:

1. `cd apps/mobile && flutter create --platforms=ios .` (regenerates the Xcode
   project/Podfile if missing — keeps your `Info.plist`/`Runner` changes).
2. Set the iOS **deployment target to 13.0+** (Firebase requires it): in Xcode,
   Runner target → General → Minimum Deployments, or add `platform :ios, '13.0'`
   at the top of `ios/Podfile`.
3. Add the Firebase iOS app in the console (your iOS bundle id) and drop
   **`GoogleService-Info.plist`** into `ios/Runner/` (add it to the target).
4. For push: enable **Push Notifications** + **Background Modes** capabilities in
   Xcode, and upload an **APNs key** to Firebase (Project settings → Cloud
   Messaging → Apple app configuration).
5. `cd ios && pod install`, then `flutter build ios` (or run from Xcode). Sign
   with your Apple Developer team to run on a device / submit to App Store.

## Launch hardening checklist (separate from the above)
- [ ] Rotate `SECRET_KEY`, `POSTGRES_PASSWORD`, `REDIS_PASSWORD`, `TURN_SECRET`
      in `deploy/.env` (the auto-generated dev values).
- [ ] Set `APP_ENV=production` and a real `ALLOWED_ORIGINS`.
- [ ] Configure a TURN server (`TURN_HOST`/`TURN_SECRET`) for calls behind CGNAT.
- [ ] Rotate any tokens/keys that were ever pasted into a chat.
- [ ] Play Store / App Store listing, privacy policy, data-deletion flow.
