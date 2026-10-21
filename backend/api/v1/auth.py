from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from ...database.session import get_db
from ...database.models import User
from ...services.auth_service import AuthService, SignUpRequest, LoginRequest, TokenResponse


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


@router.post("/signup", response_model=TokenResponse)
async def signup(req: SignUpRequest, db: AsyncSession = Depends(get_db)):
    """Register a new ConFriKa user across any of the 54 African countries."""
    return await AuthService.register_user(db, req)


@router.post("/login", response_model=TokenResponse)
async def login(req: LoginRequest, db: AsyncSession = Depends(get_db)):
    """Authenticate user with Gmail address or @username."""
    return await AuthService.authenticate_user(db, req)


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
    }


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
