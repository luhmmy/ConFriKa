"""One-time email verification codes (signup + password reset)."""
from __future__ import annotations

import hashlib
import hmac
import secrets
from datetime import datetime, timedelta, timezone

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from ..config.settings import settings
from ..database.models import EmailVerification


def _utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def _hash_code(code: str) -> str:
    # HMAC-SHA256 with the app secret as the key (codes are low-entropy).
    return hmac.new(
        settings.resolved_secret_key.encode(), code.encode(), hashlib.sha256
    ).hexdigest()


def generate_code() -> str:
    n = settings.OTP_LENGTH
    return "".join(secrets.choice("0123456789") for _ in range(n))


class OtpService:
    @classmethod
    async def create(cls, db: AsyncSession, email: str, purpose: str) -> str:
        """Invalidate prior codes for (email, purpose) and issue a fresh one."""
        email = email.strip().lower()
        await db.execute(
            update(EmailVerification)
            .where(
                (EmailVerification.email == email)
                & (EmailVerification.purpose == purpose)
                & (EmailVerification.consumed == False)  # noqa: E712
            )
            .values(consumed=True)
        )
        code = generate_code()
        db.add(
            EmailVerification(
                email=email,
                code_hash=_hash_code(code),
                purpose=purpose,
                expires_at=_utcnow() + timedelta(minutes=settings.OTP_TTL_MINUTES),
            )
        )
        await db.commit()
        return code

    @classmethod
    async def verify(cls, db: AsyncSession, email: str, purpose: str, code: str) -> bool:
        email = email.strip().lower()
        stmt = (
            select(EmailVerification)
            .where(
                (EmailVerification.email == email)
                & (EmailVerification.purpose == purpose)
                & (EmailVerification.consumed == False)  # noqa: E712
            )
            .order_by(EmailVerification.created_at.desc())
        )
        # Lock the row so concurrent verifies can't race past OTP_MAX_ATTEMPTS
        # or double-consume a code (Postgres only; SQLite ignores it in tests).
        if db.bind and db.bind.dialect.name == "postgresql":
            stmt = stmt.with_for_update()
        rec = await db.scalar(stmt)
        if rec is None:
            return False
        if rec.expires_at < _utcnow():
            return False
        if (rec.attempts or 0) >= settings.OTP_MAX_ATTEMPTS:
            return False

        if hmac.compare_digest(rec.code_hash, _hash_code(code.strip())):
            rec.consumed = True
            await db.commit()
            return True

        rec.attempts = (rec.attempts or 0) + 1
        await db.commit()
        return False
