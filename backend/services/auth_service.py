import re
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, Optional

import bcrypt
from fastapi import HTTPException, status
from jose import jwt, JWTError
from pydantic import BaseModel, EmailStr, Field, field_validator
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..config.settings import settings
from ..database.models import User

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


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: Dict[str, Any]


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
        except JWTError:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid or expired authentication credentials",
                headers={"WWW-Authenticate": "Bearer"},
            )

    @staticmethod
    async def register_user(db: AsyncSession, req: SignUpRequest) -> TokenResponse:
        if await db.scalar(select(User).where(User.username == req.username)):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"Username {req.username} is already taken.",
            )
        if await db.scalar(select(User).where(User.email == req.email)):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="An account with this email already exists.",
            )

        new_user = User(
            username=req.username,
            email=req.email,
            password_hash=hash_password(req.password),
            full_name=req.full_name.strip(),
            country_code=req.country_code,
            origin_region=req.origin_region.strip(),
            primary_dialect=req.primary_dialect.strip(),
            f0_baseline_hz=138.0,
        )
        db.add(new_user)
        await db.commit()
        await db.refresh(new_user)

        token = AuthService.create_access_token(
            {"sub": new_user.id, "username": new_user.username}
        )
        return TokenResponse(access_token=token, user=_public_user(new_user))

    @staticmethod
    async def authenticate_user(db: AsyncSession, req: LoginRequest) -> TokenResponse:
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

        token = AuthService.create_access_token({"sub": user.id, "username": user.username})
        return TokenResponse(access_token=token, user=_public_user(user))
