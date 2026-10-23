from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from ...database.session import get_db
from ...database.models import User
from ...services.admin_service import AdminService, require_admin

router = APIRouter(prefix="/admin", tags=["Admin"])


@router.get("/me")
async def admin_me(admin: User = Depends(require_admin)):
    """Confirm the caller is an admin (used by the dashboard login)."""
    return {"username": admin.username, "full_name": admin.full_name, "is_admin": True}


@router.get("/stats")
async def stats(
    admin: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    return await AdminService.stats(db)


@router.get("/users")
async def list_users(
    q: str | None = Query(None),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    admin: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    return await AdminService.list_users(db, q, limit, offset)


@router.post("/users/{username}/ban")
async def ban_user(
    username: str,
    admin: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    return await AdminService.set_banned(db, admin, username, True)


@router.post("/users/{username}/unban")
async def unban_user(
    username: str,
    admin: User = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    return await AdminService.set_banned(db, admin, username, False)
