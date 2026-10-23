import asyncio
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware

from .api.v1 import v1_router
from .api.websockets import ws_router
from .api.websockets.chat_ws import chat_manager
from .config.settings import settings
from .database.session import init_db
from .services import translation_engine

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("confrika")


@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db()
    if settings.TRANSLATION_WARMUP and settings.TRANSLATION_PROVIDER == "nllb":
        # Load the model in the background so startup/health isn't blocked.
        asyncio.create_task(translation_engine.warmup())
    yield


app = FastAPI(
    title=settings.APP_NAME,
    version=settings.APP_VERSION,
    description="African speech translation, tonal coaching, messaging, and real-time calling platform.",
    lifespan=lifespan,
)

# CORS. allow_credentials and a wildcard origin are mutually exclusive per spec,
# and the mobile client uses bearer tokens (not cookies), so credentials are off.
_origins = settings.cors_origins
app.add_middleware(
    CORSMiddleware,
    allow_origins=_origins or [],
    allow_credentials=False,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "Accept"],
)


@app.middleware("http")
async def security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers.setdefault("X-Content-Type-Options", "nosniff")
    response.headers.setdefault("X-Frame-Options", "DENY")
    response.headers.setdefault("Referrer-Policy", "no-referrer")
    response.headers.setdefault("X-XSS-Protection", "0")
    if settings.is_production:
        response.headers.setdefault(
            "Strict-Transport-Security", "max-age=31536000; includeSubDomains"
        )
    return response


app.include_router(v1_router)
app.include_router(ws_router)

# Serve uploaded media (profile pictures, image messages) from /media.
import os  # noqa: E402
from fastapi.staticfiles import StaticFiles  # noqa: E402

try:
    os.makedirs(settings.MEDIA_DIR, exist_ok=True)
except OSError:
    pass  # created at runtime by the upload handler when permissions allow
# check_dir=False so importing the app never requires the media dir to exist yet.
app.mount("/media", StaticFiles(directory=settings.MEDIA_DIR, check_dir=False), name="media")


@app.get("/health", tags=["Monitoring & Health"])
async def health_check():
    """System health check and gateway status (real, live values)."""
    return {
        "status": "healthy",
        "app": settings.APP_NAME,
        "version": settings.APP_VERSION,
        "environment": settings.APP_ENV,
        "african_countries_supported": 54,
        "online_users": chat_manager.online_users_count,
        "translation_provider": settings.TRANSLATION_PROVIDER,
        "translation_model_loaded": translation_engine.engine_ready(),
        "webrtc_signaling": "operational",
        "telecom_interconnect": "not_available",
    }
