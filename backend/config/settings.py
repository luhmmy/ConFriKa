import secrets
import logging
from typing import List, Optional
from pydantic_settings import BaseSettings, SettingsConfigDict

logger = logging.getLogger("confrika.settings")


class Settings(BaseSettings):
    APP_NAME: str = "ConFriKa Backend Services"
    APP_VERSION: str = "2.0.0"
    APP_ENV: str = "development"  # 'development' | 'production'
    DEBUG: bool = False

    # Security / JWT. SECRET_KEY must be supplied via environment in production.
    SECRET_KEY: Optional[str] = None
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24 * 7  # 7 days
    BCRYPT_ROUNDS: int = 12

    # Database & Redis
    DATABASE_URL: str = "sqlite+aiosqlite:///./confrika.db"
    REDIS_URL: str = "redis://localhost:6379/0"

    # CORS — comma separated list of allowed origins. Never wildcard in prod.
    ALLOWED_ORIGINS: str = "http://localhost:3000,http://localhost:8080"

    # Request limits
    MAX_TEXT_LENGTH: int = 5000
    MAX_AUDIO_BYTES: int = 20 * 1024 * 1024  # 20 MB

    # Translation engine
    TRANSLATION_PROVIDER: str = "nllb"  # 'nllb' | 'echo' (echo = passthrough, dev only)
    NLLB_MODEL: str = "facebook/nllb-200-distilled-600M"
    NLLB_DEVICE: str = "cpu"  # 'cpu' | 'cuda'
    NLLB_MAX_INPUT_TOKENS: int = 512
    MODEL_CACHE_DIR: str = "/opt/confrika/models"
    TRANSLATION_WARMUP: bool = True

    # Voice / Tonal pitch engine
    PITCH_ANALYSIS_MIN_F0: float = 70.0
    PITCH_ANALYSIS_MAX_F0: float = 350.0

    # WebRTC ICE / TURN (coturn REST ephemeral-credential mechanism)
    STUN_URL: str = "stun:stun.l.google.com:19302"
    TURN_HOST: str = ""  # e.g. turn.confrika.com — empty disables TURN relay
    TURN_PORT: int = 3478
    TURN_SECRET: str = ""  # shared static-auth-secret with coturn
    TURN_TTL_SECONDS: int = 86400

    @property
    def is_production(self) -> bool:
        return self.APP_ENV.lower() == "production"

    @property
    def cors_origins(self) -> List[str]:
        raw = (self.ALLOWED_ORIGINS or "").strip()
        if raw == "*":
            # Wildcard is only honoured outside production.
            return ["*"] if not self.is_production else []
        return [o.strip() for o in raw.split(",") if o.strip()]

    @property
    def resolved_secret_key(self) -> str:
        if self.SECRET_KEY and self.SECRET_KEY.strip():
            return self.SECRET_KEY.strip()
        if self.is_production:
            raise RuntimeError(
                "SECRET_KEY environment variable must be set in production. "
                "Generate one with: python -c 'import secrets; print(secrets.token_urlsafe(48))'"
            )
        # Development fallback: ephemeral per-process key (tokens invalidate on restart).
        logger.warning(
            "SECRET_KEY not set — generating an ephemeral development key. "
            "Tokens will not survive a restart. Set SECRET_KEY for stable auth."
        )
        return _EPHEMERAL_DEV_KEY

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


# Single ephemeral key per process (dev only).
_EPHEMERAL_DEV_KEY = secrets.token_urlsafe(48)

settings = Settings()
