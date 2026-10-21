# ConFriKa

**Many languages. One connection. One Africa.**

ConFriKa is a pan-African communication platform: real-time neural translation across
African languages, direct messaging and Global Spaces, in-app WebRTC voice calling, and
a self-learning tonal coach for tone languages.

This repository contains:

- `backend/` — FastAPI service (auth, translation, chat, contacts, calls, tone coach).
- `apps/mobile/` — Flutter app (Android/iOS).
- `deploy/` — Docker Compose stack (PostgreSQL, Redis, backend, Nginx, Coturn).
- `docs/` — architecture, privacy policy, terms.

---

## What is real (no mocks)

| Area | Implementation |
|------|----------------|
| **Translation** | Self-hosted **NLLB-200** (`facebook/nllb-200-distilled-600M`) neural MT running in the backend. No API keys. Covers Yorùbá, Igbo, Hausa, Swahili, Zulu, Xhosa, Amharic, Twi/Akan, Shona, Wolof, Somali, Kinyarwanda, Lingala, and more. Confidence is derived from the model's own token scores. |
| **Auth** | Email + password with **bcrypt** hashing, JWT access tokens. No passwordless/auto-create. Uniform error messages (no user enumeration). |
| **Messaging** | DMs and Global Spaces persisted in PostgreSQL; outgoing messages auto-translated into the recipient's dialect. Live presence + delivery over WebSockets. |
| **Contacts** | Backed by the real user directory; you can only add registered users. Flags are computed from ISO country codes. |
| **Calls** | WebRTC peer-to-peer audio; backend issues STUN + **time-limited TURN credentials** (coturn REST mechanism). Signaling over WebSockets. |
| **Tonal coach** | Real F0 autocorrelation pitch analysis (NumPy) + semitone RMSE scoring. |
| **Presence** | Live count of connected users (no fabricated numbers). |

**Not yet available (honestly surfaced in the UI):** No-App (PSTN) telecom calling; live
in-call speech translation. These are roadmap items, not fake features.

---

## Run the backend (Docker)

```bash
cd deploy
# deploy/.env must define SECRET_KEY, POSTGRES_PASSWORD, REDIS_PASSWORD, TURN_SECRET
#   python -c "import secrets; print(secrets.token_urlsafe(48))"
./deploy.sh
```

The backend listens on `http://localhost:8088` (host) and behind Nginx on `http://localhost/`.
The NLLB model (~2.4 GB) downloads on first boot into the `model_cache` volume; `/health`
reports `translation_model_loaded: true` once ready.

Health: `curl http://localhost:8088/health` · API docs: `http://localhost:8088/docs`

## Run the app

```bash
cd apps/mobile
flutter pub get
# Android emulator reaches the host backend at 10.0.2.2:
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8088
# Production build:
flutter build apk --release --dart-define=API_BASE_URL=https://api.confrika.com
```

## Tests

```bash
cd backend && python -m pytest tests -q      # backend unit tests
cd apps/mobile && flutter analyze            # static analysis
```

---

## Security posture

- `SECRET_KEY` is **required** in production (the app refuses to start without it); dev uses
  an ephemeral per-process key.
- Passwords hashed with bcrypt (cost 12). JWTs signed HS256, 7-day expiry (configurable).
- CORS is an explicit allow-list — never `*` with credentials; the mobile client uses bearer
  tokens, so cookie credentials are disabled.
- Security headers (`X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`, HSTS in
  prod) on every response. Request size limits on text and audio.
- Secrets are injected from `deploy/.env` (git-ignored), not committed. Postgres/Redis are
  not published to the host — only reachable on the internal Docker network.
- Android app enforces HTTPS except for the emulator loopback (`10.0.2.2`), via a
  network-security config.

Before any public launch: rotate all secrets in `deploy/.env`, terminate TLS at Nginx with a
real certificate, set `ALLOWED_ORIGINS` to your real domains, and point the app at HTTPS.
