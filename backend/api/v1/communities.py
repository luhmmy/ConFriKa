from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from ...database.session import get_db
from ...database.models import User
from ...services.community_service import CommunityService, CreateCommunityRequest
from .auth import get_current_user

router = APIRouter(prefix="/communities", tags=["Communities"])


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
    return await CommunityService.create_community(db, current_user, req)


@router.post("/{slug}/join")
async def join_community(
    slug: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await CommunityService.join(db, current_user, slug)


@router.post("/{slug}/leave")
async def leave_community(
    slug: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await CommunityService.leave(db, current_user, slug)
