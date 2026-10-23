import re
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, Optional

import bcrypt
import jwt
from fastapi import HTTPException, status
from jwt import PyJWTError
from pydantic import BaseModel, EmailStr, Field, field_validator
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..config.settings import settings
from ..database.models import User
from .email_service import send_otp_email
from .otp_service import OtpService

# All 54 African ISO 3166-1 alpha-2 country codes.
VALID_AFRICAN_COUNTRY_CODES = {
    "DZ", "AO", "BJ", "BW", "BF", "BI", "CV", "CM", "CF", "TD",
    "KM", "CG", "CD", "DJ", "EG", "GQ", "ER", "SZ", "ET", "GA",
    "GM", "GH", "GN", "GW", "CI", "KE", "LS", "LR", "LY", "MG",
    "MW", "ML", "MR", "MU", "MA", "MZ", "NA", "NE", "NG", "RW",
    "ST", "SN", "SC", "SL", "SO", "ZA", "SS", "SD", "TZ", "TG",
    "TN", "UG", "ZM", "ZW",
}

USERNAME_RE = re.compile(r"^@[a-z0-9_]{3,38}$")


def hash_password(plain: str) -> str:
    # bcrypt operates on at most 72 bytes; encode then hash.
    pw = plain.encode("utf-8")[:72]
    return bcrypt.hashpw(pw, bcrypt.gensalt(rounds=settings.BCRYPT_ROUNDS)).decode("utf-8")


def verify_password(plain: str, hashed: Optional[str]) -> bool:
    if not hashed:
        return False
    try:
        return bcrypt.checkpw(plain.encode("utf-8")[:72], hashed.encode("utf-8"))
    except (ValueError, TypeError):
        return False


def normalize_username(raw: str) -> str:
    clean = raw.strip().lower()
    if not clean.startswith("@"):
        clean = "@" + clean
    return clean


def ensure_strong_password(v: str) -> str:
    """Shared password policy (also enforced in the Pydantic validator)."""
    if len(v) < 8:
        raise ValueError("Password must be at least 8 characters.")
    if not any(c.isupper() for c in v):
        raise ValueError("Password must include at least one uppercase letter.")
    if not any(c.islower() for c in v):
        raise ValueError("Password must include at least one lowercase letter.")
    if not any(c.isdigit() for c in v):
        raise ValueError("Password must include at least one number.")
    return v


class SignUpRequest(BaseModel):
    email: EmailStr
    password: str = Field(..., min_length=8, max_length=128)
    full_name: str = Field(..., min_length=2, max_length=120)
    username: str = Field(..., min_length=3, max_length=40)
    country_code: str = Field(..., min_length=2, max_length=2)
    origin_region: str = Field(..., min_length=2, max_length=120)
    primary_dialect: str = Field(..., min_length=2, max_length=100)

    @field_validator("email")
    @classmethod
    def normalize_email(cls, v: str) -> str:
        return str(v).strip().lower()

    @field_validator("password")
    @classmethod
    def validate_password_strength(cls, v: str) -> str:
        # Enforced server-side too (not just in the app): mix of character types.
        return ensure_strong_password(v)

    @field_validator("username")
    @classmethod
    def validate_username(cls, v: str) -> str:
        clean = normalize_username(v)
        if not USERNAME_RE.match(clean):
            raise ValueError(
                "Username must start with @ and contain 3-38 lowercase letters, "
                "digits, or underscores."
            )
        return clean

    @field_validator("country_code")
    @classmethod
    def validate_country(cls, v: str) -> str:
        code = v.strip().upper()
        if code not in VALID_AFRICAN_COUNTRY_CODES:
            raise ValueError(f"Country code '{code}' must be one of the 54 African states.")
        return code


class LoginRequest(BaseModel):
    email_or_username: str = Field(..., min_length=3, max_length=255)
    password: str = Field(..., min_length=1, max_length=128)


class VerifyEmailRequest(BaseModel):
    email: EmailStr
    code: str = Field(..., min_length=4, max_length=10)


class EmailRequest(BaseModel):
    email: EmailStr


class ResetPasswordRequest(BaseModel):
    email: EmailStr
    code: str = Field(..., min_length=4, max_length=10)
    new_password: str = Field(..., min_length=8, max_length=128)

    @field_validator("new_password")
    @classmethod
    def _strong(cls, v: str) -> str:
        return ensure_strong_password(v)


class ChangePasswordRequest(BaseModel):
    current_password: str = Field(..., min_length=1, max_length=128)
    new_password: str = Field(..., min_length=8, max_length=128)
    # Email OTP confirming the signed-in user controls the account inbox.
    code: str = Field(..., min_length=4, max_length=10)

    @field_validator("new_password")
    @classmethod
    def _strong(cls, v: str) -> str:
        return ensure_strong_password(v)


class UpdateProfileRequest(BaseModel):
    full_name: Optional[str] = Field(None, min_length=2, max_length=120)
    origin_region: Optional[str] = Field(None, min_length=2, max_length=120)
    primary_dialect: Optional[str] = Field(None, min_length=2, max_length=100)
    country_code: Optional[str] = Field(None, min_length=2, max_length=2)

    @field_validator("country_code")
    @classmethod
    def _country(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return v
        code = v.strip().upper()
        if code not in VALID_AFRICAN_COUNTRY_CODES:
            raise ValueError(f"Country code '{code}' must be one of the 54 African states.")
        return code


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: Dict[str, Any]


class OtpSentResponse(BaseModel):
    status: str = "otp_sent"
    email: str
    delivered: bool
    # Present ONLY when email isn't configured (dev), so testing can proceed.
    debug_code: Optional[str] = None


def _public_user(user: User) -> Dict[str, Any]:
    return {
        "id": user.id,
        "username": user.username,
        "email": user.email,
        "full_name": user.full_name,
        "country_code": user.country_code,
        "origin_region": user.origin_region,
        "primary_dialect": user.primary_dialect,
        "f0_baseline_hz": user.f0_baseline_hz,
        "email_verified": user.email_verified,
    }


class AuthService:
    @staticmethod
    def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
        to_encode = data.copy()
        expire = datetime.now(timezone.utc) + (
            expires_delta or timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
        )
        to_encode.update({"exp": expire, "iat": datetime.now(timezone.utc)})
        return jwt.encode(to_encode, settings.resolved_secret_key, algorithm=settings.ALGORITHM)

    @staticmethod
    def decode_access_token(token: str) -> dict:
        try:
            return jwt.decode(
                token, settings.resolved_secret_key, algorithms=[settings.ALGORITHM]
            )
        except PyJWTError:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid or expired authentication credentials",
                headers={"WWW-Authenticate": "Bearer"},
            )

    @staticmethod
    async def _issue_otp(db: AsyncSession, email: str, purpose: str) -> OtpSentResponse:
        code = await OtpService.create(db, email, purpose)
        delivered = await send_otp_email(email, code, purpose)
        # Only surface the code for local testing: never in production, and never
        # once the provider has accepted the message.
        expose = (not delivered) and (not settings.is_production)
        return OtpSentResponse(
            email=email,
            delivered=delivered,
            debug_code=code if expose else None,
        )

    @staticmethod
    async def register_user(db: AsyncSession, req: SignUpRequest) -> OtpSentResponse:
        if await db.scalar(select(User).where(User.username == req.username)):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"Username {req.username} is already taken.",
            )
        existing = await db.scalar(select(User).where(User.email == req.email))
        if existing is not None:
            if existing.email_verified:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="An account with this email already exists.",
                )
            # Unverified signup being retried: refresh its details and re-send a code.
            existing.username = req.username
            existing.password_hash = hash_password(req.password)
            existing.full_name = req.full_name.strip()
            existing.country_code = req.country_code
            existing.origin_region = req.origin_region.strip()
            existing.primary_dialect = req.primary_dialect.strip()
            await db.commit()
            return await AuthService._issue_otp(db, req.email, "signup")

        new_user = User(
            username=req.username,
            email=req.email,
            password_hash=hash_password(req.password),
            full_name=req.full_name.strip(),
            country_code=req.country_code,
            origin_region=req.origin_region.strip(),
            primary_dialect=req.primary_dialect.strip(),
            f0_baseline_hz=138.0,
            email_verified=False,
        )
        db.add(new_user)
        await db.commit()
        return await AuthService._issue_otp(db, req.email, "signup")

    @staticmethod
    async def verify_email(db: AsyncSession, req: VerifyEmailRequest) -> TokenResponse:
        email = str(req.email).strip().lower()
        user = await db.scalar(select(User).where(User.email == email))
        if user is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="No account is awaiting verification for this email.",
            )
        if not await OtpService.verify(db, email, "signup", req.code):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid or expired verification code.",
            )
        user.email_verified = True
        await db.commit()
        await db.refresh(user)
        token = AuthService.create_access_token({"sub": user.id, "username": user.username})
        return TokenResponse(access_token=token, user=_public_user(user))

    @staticmethod
    async def resend_signup_otp(db: AsyncSession, email: str) -> OtpSentResponse:
        email = email.strip().lower()
        user = await db.scalar(select(User).where(User.email == email))
        if user is not None and not user.email_verified:
            return await AuthService._issue_otp(db, email, "signup")
        # Don't reveal whether the account exists / is already verified.
        return OtpSentResponse(email=email, delivered=False, debug_code=None)

    @staticmethod
    async def authenticate_user(db: AsyncSession, req: LoginRequest):
        identifier = req.email_or_username.strip().lower()
        # Users may sign in with either their email or their @username.
        user = await db.scalar(
            select(User).where(
                (User.email == identifier)
                | (User.username == normalize_username(identifier))
            )
        )

        if not user or not verify_password(req.password, user.password_hash):
            # Uniform error to avoid user enumeration.
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid credentials. Please check your email/username and password.",
            )

        if not user.email_verified:
            # Credentials are correct but the email was never verified: send a
            # fresh code and tell the client to route to the OTP screen.
            await AuthService._issue_otp(db, user.email, "signup")
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="email_not_verified",
            )

        token = AuthService.create_access_token({"sub": user.id, "username": user.username})
        return TokenResponse(access_token=token, user=_public_user(user))

    @staticmethod
    async def forgot_password(db: AsyncSession, email: str) -> OtpSentResponse:
        email = email.strip().lower()
        user = await db.scalar(select(User).where(User.email == email))
        if user is not None:
            return await AuthService._issue_otp(db, email, "reset")
        # Uniform response — never reveal whether the email is registered.
        return OtpSentResponse(email=email, delivered=False, debug_code=None)

    @staticmethod
    async def reset_password(db: AsyncSession, req: ResetPasswordRequest) -> Dict[str, Any]:
        email = str(req.email).strip().lower()
        user = await db.scalar(select(User).where(User.email == email))
        if user is None or not await OtpService.verify(db, email, "reset", req.code):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid or expired reset code.",
            )
        user.password_hash = hash_password(req.new_password)
        user.email_verified = True  # proving email control also verifies it
        await db.commit()
        return {"status": "password_reset"}

    @staticmethod
    async def request_change_password_otp(
        db: AsyncSession, user: User
    ) -> OtpSentResponse:
        """Email the signed-in user a code to authorize a password change."""
        return await AuthService._issue_otp(db, user.email, "change_pw")

    @staticmethod
    async def change_password(
        db: AsyncSession, user: User, req: ChangePasswordRequest
    ) -> Dict[str, Any]:
        if not verify_password(req.current_password, user.password_hash):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Your current password is incorrect.",
            )
        if not await OtpService.verify(db, user.email, "change_pw", req.code):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid or expired verification code.",
            )
        user.password_hash = hash_password(req.new_password)
        await db.commit()
        return {"status": "password_changed"}

    @staticmethod
    async def update_profile(
        db: AsyncSession, user: User, req: UpdateProfileRequest
    ) -> Dict[str, Any]:
        if req.full_name is not None:
            user.full_name = req.full_name.strip()
        if req.origin_region is not None:
            user.origin_region = req.origin_region.strip()
        if req.primary_dialect is not None:
            user.primary_dialect = req.primary_dialect.strip()
        if req.country_code is not None:
            user.country_code = req.country_code
        await db.commit()
        await db.refresh(user)
        return _public_user(user)
