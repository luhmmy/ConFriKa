"""Monetization API: entitlements + store purchase verification (ConFriKa Pro)."""
from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from ...database.session import get_db
from ...database.models import User
from ...services import billing_service
from ...services.rate_limit import rate_limit
from .auth import get_current_user

router = APIRouter(prefix="/billing", tags=["Billing"])


class VerifyPurchaseRequest(BaseModel):
    platform: str          # 'google_play' | 'app_store'
    product_id: str        # e.g. 'confrika_pro_monthly'
    token: str             # store purchase/subscription token


@router.get("/entitlements")
async def get_entitlements(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """The caller's tier, limits, today's usage, ads flag, and Pro products."""
    return await billing_service.entitlements(db, current_user)


@router.post("/verify", dependencies=[rate_limit("billing_verify", 20, 60)])
async def verify_purchase(
    req: VerifyPurchaseRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Verify a store purchase and grant Pro on success. Returns new entitlements."""
    return await billing_service.verify_and_apply(
        db, current_user, req.platform, req.product_id, req.token
    )
