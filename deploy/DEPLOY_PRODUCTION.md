# ConFriKa production deployment

Two pieces: the **website** on Vercel and the **backend** on Fly.io.

```
confrika.online            -> Vercel (marketing site: website/)
api.confrika.online        -> Fly.io  (FastAPI backend + NLLB model)
turn.confrika.online       -> coturn  (TURN relay for calls)
```

The mobile app is built with `--dart-define=API_BASE_URL=https://api.confrika.online`,
so point that hostname at the Fly app once deployed.

---

## 1. Website → Vercel

The site is static (`website/index.html`, `privacy.html`, `terms.html`).

```bash
npm i -g vercel
cd website
vercel            # first run: links/creates the project
vercel --prod     # deploys to production
```

Then in the Vercel dashboard add the domain **confrika.online** (and `www`)
under Project → Settings → Domains, and set the DNS records Vercel shows at your
registrar. `vercel.json` already enables clean URLs and the privacy/terms
redirects.

> Vercel **cannot** host the backend (serverless 250MB/short-timeout limits; the
> backend needs a 2.4GB model in memory, Postgres, Redis and a TURN server). It
> only serves the website.

---

## 2. Backend → Fly.io

Config lives in `backend/fly.toml` (region `jnb` = Johannesburg, closest to Africa).

```bash
# install + login
curl -L https://fly.io/install.sh | sh
fly auth login

cd backend
fly apps create confrika-backend          # or: fly launch --no-deploy (reuses fly.toml)

# managed Postgres + Redis
fly postgres create --name confrika-db --region jnb
fly postgres attach confrika-db --app confrika-backend   # sets DATABASE_URL secret
fly redis create                                          # gives you a REDIS_URL

# persistent volume for the NLLB model (sized for ~2.4GB + HF cache)
fly volumes create confrika_models --region jnb --size 5 --app confrika-backend
```

### Secrets (never commit these)
```bash
fly secrets set \
  REDIS_URL="redis://default:<password>@<host>:6379" \
  SECRET_KEY="$(openssl rand -hex 32)" \
  RESEND_API_KEY="..." \
  ADMIN_EMAILS="jopelumi141@gmail.com" \
  VOICE_API_KEY="..." \
  FCM_PROJECT_ID="..." \
  TURN_HOST="turn.confrika.online" TURN_SECRET="$(openssl rand -hex 24)" \
  --app confrika-backend
# Optional: Google Translate fallback + Play billing verification
fly secrets set GOOGLE_TRANSLATE_API_KEY="..." PLAY_SERVICE_ACCOUNT_FILE="/opt/confrika/play-sa.json" --app confrika-backend
```
`DATABASE_URL` is set automatically by `fly postgres attach`. Convert it to the
asyncpg form the app expects: `postgresql+asyncpg://...` (set it explicitly with
`fly secrets set DATABASE_URL=postgresql+asyncpg://...` if attach used `postgres://`).

### Deploy + load the model onto the volume
```bash
fly deploy --app confrika-backend          # builds backend/Dockerfile

# Upload the pre-downloaded NLLB model to the volume (see
# confrika_nllb_local_model notes; the full pytorch_model.bin is 2,460,457,927 bytes):
fly ssh console --app confrika-backend -C "mkdir -p /opt/confrika/nllb-local"
fly sftp shell --app confrika-backend      # then: put <local model files> /opt/confrika/nllb-local/
fly apps restart confrika-backend
```

Confirm: `curl https://confrika-backend.fly.dev/health` → `translation_model_loaded: true`.

### Custom domain + TLS
```bash
fly certs add api.confrika.online --app confrika-backend
```
Add the shown A/AAAA/CNAME records at your registrar.

### TURN (calls)
coturn is a separate service (it is not an HTTP app). Run it on a small Fly app
or a cheap VPS with UDP, point `turn.confrika.online` at it, and set `TURN_HOST`
/ `TURN_SECRET` secrets above to match. Until then calls work over STUN on the
same network but may fail across strict NATs.

---

## 3. After the backend is live
- Rebuild/submit the app only after `api.confrika.online` resolves (the AAB is
  already built against that URL).
- Set the real AdMob app id + ad unit ids (currently Google TEST ids) in
  `android/app/src/main/AndroidManifest.xml` and `ads_service.dart`.
- Replace `BILLING_TRUST_UNVERIFIED` usage: keep it **false** in production and
  configure `PLAY_SERVICE_ACCOUNT_FILE` so purchases are verified for real.
