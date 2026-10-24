from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from sqlalchemy import func, select

from ...database.session import get_db
from ...database.models import CommunityMembership, User
from ...services.community_service import CommunityService, CreateCommunityRequest
from ...services import billing_service
from .auth import get_current_user

router = APIRouter(prefix="/communities", tags=["Communities"])


async def _communities_joined(db: AsyncSession, user: User) -> int:
    return await db.scalar(
        select(func.count(CommunityMembership.id)).where(
            CommunityMembership.user_id == user.id
        )
    ) or 0


@router.get("")
async def list_communities(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """List all communities with join status and member counts."""
    return await CommunityService.list_communities(db, current_user)


@router.post("")
async def create_community(
    req: CreateCommunityRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Create a new community (the creator automatically joins)."""
    lims = billing_service.limits_for(current_user)
    if not lims["can_create_communities"]:
        from fastapi import HTTPException, status
        raise HTTPException(
            status.HTTP_402_PAYMENT_REQUIRED,
            "Creating communities is a ConFriKa Pro feature. "
            "Upgrade to ConFriKa Pro for unlimited access.",
        )
    return await CommunityService.create_community(db, current_user, req)


@router.post("/{slug}/join")
async def join_community(
    slug: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    lims = billing_service.limits_for(current_user)
    max_c = lims["max_communities"]
    if max_c >= 0 and await _communities_joined(db, current_user) >= max_c:
        from fastapi import HTTPException, status
        raise HTTPException(
            status.HTTP_402_PAYMENT_REQUIRED,
            f"Free members can join up to {max_c} communities. "
            "Upgrade to ConFriKa Pro to join unlimited communities.",
        )
    return await CommunityService.join(db, current_user, slug)


@router.post("/{slug}/leave")
async def leave_community(
    slug: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await CommunityService.leave(db, current_user, slug)


@router.delete("/{slug}")
async def delete_community(
    slug: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Delete a community you created (not the default one)."""
    return await CommunityService.delete_community(db, current_user, slug)
