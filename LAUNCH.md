# ConFriKa — Commercial launch checklist

What's built vs. what you still need to do before going live. See `SETUP.md` for
the integration steps (Resend, Firebase, ElevenLabs, iOS build).

## ✅ Built and verified
- Auth (OTP signup, password reset, OTP-gated change-password), E2E-encrypted DMs,
  separate Chats + Communities, images + avatars + emoji, WhatsApp-style calls,
  tonal coach (42 languages incl Atyap, native crowdsourcing), translation across
  all NLLB languages, privacy/reachability controls.
- Email live on confrika.online; push notifications (FCM) live.
- Live call translation pipeline (voice enrollment + in-call translate) — client
  wired; verify on two real phones.
- Security pass 1: rate limiting, signup-race fix, OTP row-lock, prod docs off.
- Admin dashboard at `/admin`; account deletion (store requirement).
- Marketing site + Privacy Policy + Terms (`website/`).

## 🔴 Do before launch

### 1. Rotate all dev secrets (`deploy/.env`)
The auto-generated dev values are known / were pasted in chat. Generate fresh:
```
python -c "import secrets; print(secrets.token_urlsafe(48))"   # SECRET_KEY
python -c "import secrets; print(secrets.token_urlsafe(24))"   # POSTGRES_PASSWORD, REDIS_PASSWORD
openssl rand -hex 32                                            # TURN_SECRET
```
Rotating `SECRET_KEY` logs everyone out (expected). Changing `POSTGRES_PASSWORD`
on an existing DB also needs `ALTER USER confrika_admin WITH PASSWORD '…';`.
Also **revoke the GitHub and ElevenLabs tokens** pasted during development.

### 2. Production config
- `ADMIN_EMAILS` = your real admin account email (not amara@gmail.com).
- `ALLOWED_ORIGINS=https://confrika.online` (and the admin host).
- Serve over **HTTPS** (TLS at nginx / your host) for the domain.
- `EMAIL_FROM` already on confrika.online; keep the live Resend key.

### 3. Calls behind mobile networks
- Stand up a **TURN server** (coturn) and set `TURN_HOST` / `TURN_SECRET` so calls
  connect through carrier-grade NAT. (A compose `coturn` service already exists.)

### 4. Live call translation
- Verify end-to-end on **two real phones**: enroll a voice, start a call, use
  Translate. Budget ElevenLabs minutes; upgrade from Starter before real traffic.

### 5. Store submission
- **Android:** Play Console listing, screenshots, Data Safety form (declare
  encryption, data collected, account-deletion URL), content rating, signed AAB.
- **iOS:** build on a Mac (see SETUP.md), App Store Connect listing, App Privacy
  questionnaire, APNs key, TestFlight → review.
- Link **Privacy Policy** (`website/privacy.html`) and **account-deletion** in both
  listings. Host `website/` at confrika.online.

### 6. Legal & ops
- Have `website/privacy.html` and `website/terms.html` reviewed by a lawyer.
- Add crash reporting + analytics (e.g. Sentry) if you want production telemetry.
- Database backups for the Postgres volume; monitoring/alerts on the backend.
