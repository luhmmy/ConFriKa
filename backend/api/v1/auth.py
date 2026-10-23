from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from ...database.session import get_db
from ...database.models import User
from ...services.auth_service import (
    AuthService,
    SignUpRequest,
    LoginRequest,
    TokenResponse,
    OtpSentResponse,
    VerifyEmailRequest,
    EmailRequest,
    ResetPasswordRequest,
    ChangePasswordRequest,
    UpdateProfileRequest,
)
from ...services.learning_stats_service import LearningStatsService


class TonalBaselineRequest(BaseModel):
    f0_baseline_hz: float = Field(..., ge=50.0, le=500.0)

router = APIRouter(prefix="/auth", tags=["Authentication"])
security = HTTPBearer()


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    db: AsyncSession = Depends(get_db),
) -> User:
    token = credentials.credentials
    payload = AuthService.decode_access_token(token)
    user_id = payload.get("sub")
    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token payload missing subject identifier",
        )

    user = await db.get(User, user_id)
    if not user:
        # Fallback by username if user was seeded or created in another worker
        username = payload.get("username")
        if username:
            user = await db.scalar(select(User).where(User.username == username))
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authenticated user no longer exists",
        )
    return user


@router.post("/signup", response_model=OtpSentResponse)
async def signup(req: SignUpRequest, db: AsyncSession = Depends(get_db)):
    """Begin registration: create the account and email a verification code."""
    return await AuthService.register_user(db, req)


@router.post("/verify-email", response_model=TokenResponse)
async def verify_email(req: VerifyEmailRequest, db: AsyncSession = Depends(get_db)):
    """Confirm the signup email with the OTP and return the access token."""
    return await AuthService.verify_email(db, req)


@router.post("/resend-otp", response_model=OtpSentResponse)
async def resend_otp(req: EmailRequest, db: AsyncSession = Depends(get_db)):
    """Re-send the signup verification code."""
    return await AuthService.resend_signup_otp(db, str(req.email))


@router.post("/login", response_model=TokenResponse)
async def login(req: LoginRequest, db: AsyncSession = Depends(get_db)):
    """Authenticate user with email address or @username."""
    return await AuthService.authenticate_user(db, req)


@router.post("/forgot-password", response_model=OtpSentResponse)
async def forgot_password(req: EmailRequest, db: AsyncSession = Depends(get_db)):
    """Email a password-reset code (always returns success — no enumeration)."""
    return await AuthService.forgot_password(db, str(req.email))


@router.post("/reset-password")
async def reset_password(req: ResetPasswordRequest, db: AsyncSession = Depends(get_db)):
    """Reset the password using the emailed code."""
    return await AuthService.reset_password(db, req)


@router.post("/change-password/request-otp", response_model=OtpSentResponse)
async def request_change_password_otp(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Email the signed-in user a one-time code to authorize a password change."""
    return await AuthService.request_change_password_otp(db, current_user)


@router.post("/change-password")
async def change_password(
    req: ChangePasswordRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Change the password for the signed-in user (requires an emailed OTP)."""
    return await AuthService.change_password(db, current_user, req)


@router.put("/me")
async def update_profile(
    req: UpdateProfileRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Update the signed-in user's profile (name, origin, dialect, country)."""
    return await AuthService.update_profile(db, current_user, req)


@router.get("/me")
async def get_my_profile(current_user: User = Depends(get_current_user)):
    """Get current authenticated user profile, dialect, and voice baseline."""
    return {
        "id": current_user.id,
        "username": current_user.username,
        "email": current_user.email,
        "full_name": current_user.full_name,
        "country_code": current_user.country_code,
        "origin_region": current_user.origin_region,
        "primary_dialect": current_user.primary_dialect,
        "f0_baseline_hz": current_user.f0_baseline_hz,
        "email_verified": current_user.email_verified,
    }


@router.get("/me/stats")
async def get_my_stats(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Real learning progress (streak, words learned, XP) derived from activity."""
    return await LearningStatsService.get_user_stats(db, current_user)


@router.put("/me/tonal-baseline")
async def update_tonal_baseline(
    req: TonalBaselineRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Calibrate the user's personal baseline vocal pitch (mean F0 in Hz)."""
    current_user.f0_baseline_hz = req.f0_baseline_hz
    db.add(current_user)
    await db.commit()
    return {"status": "updated", "f0_baseline_hz": current_user.f0_baseline_hz}
