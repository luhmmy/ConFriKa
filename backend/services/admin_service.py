"""Admin / moderation: platform stats, user listing, and bans.

Admin access is granted to accounts whose email is in ADMIN_EMAILS (applied on
startup) and enforced by `require_admin`."""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from fastapi import Depends, HTTPException, status
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..config.settings import settings
from ..database.models import (
    Community,
    DirectMessage,
    GlobalSpacesMessage,
    User,
)
from ..database.session import get_db
from ..api.v1.auth import get_current_user


async def require_admin(current_user: User = Depends(get_current_user)) -> User:
    if not current_user.is_admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin access required.",
        )
    return current_user


class AdminService:
    @staticmethod
    async def bootstrap_admins(db: AsyncSession) -> None:
        """Grant admin to the configured ADMIN_EMAILS (idempotent)."""
        emails = settings.admin_emails
        if not emails:
            return
        users = (await db.scalars(select(User).where(User.email.in_(emails)))).all()
        changed = False
        for u in users:
            if not u.is_admin:
                u.is_admin = True
                changed = True
        if changed:
            await db.commit()

    @staticmethod
    async def stats(db: AsyncSession) -> Dict[str, Any]:
        total_users = await db.scalar(select(func.count(User.id))) or 0
        verified = await db.scalar(
            select(func.count(User.id)).where(User.email_verified == True)  # noqa: E712
        ) or 0
        banned = await db.scalar(
            select(func.count(User.id)).where(User.is_banned == True)  # noqa: E712
        ) or 0
        countries = await db.scalar(
            select(func.count(func.distinct(User.country_code)))
        ) or 0
        communities = await db.scalar(select(func.count(Community.id))) or 0
        dm_count = await db.scalar(select(func.count(DirectMessage.id))) or 0
        space_count = await db.scalar(select(func.count(GlobalSpacesMessage.id))) or 0
        # Users per country (top 10).
        rows = (
            await db.execute(
                select(User.country_code, func.count(User.id))
                .group_by(User.country_code)
                .order_by(func.count(User.id).desc())
                .limit(10)
            )
        ).all()
        by_country = [{"country": c, "count": n} for c, n in rows]
        return {
            "total_users": total_users,
            "verified_users": verified,
            "banned_users": banned,
            "total_countries": countries,
            "total_communities": communities,
            "direct_messages": dm_count,
            "global_messages": space_count,
            "users_by_country": by_country,
        }

    @staticmethod
    async def list_users(
        db: AsyncSession, q: Optional[str], limit: int, offset: int
    ) -> List[Dict[str, Any]]:
        stmt = select(User)
        if q:
            like = f"%{q.strip().lower()}%"
            stmt = stmt.where(
                or_(
                    func.lower(User.username).like(like),
                    func.lower(User.email).like(like),
                    func.lower(User.full_name).like(like),
                )
            )
        stmt = stmt.order_by(User.created_at.desc()).limit(limit).offset(offset)
        users = (await db.scalars(stmt)).all()
        return [
            {
                "username": u.username,
                "email": u.email,
                "full_name": u.full_name,
                "country_code": u.country_code,
                "origin_region": u.origin_region,
                "email_verified": u.email_verified,
                "is_banned": u.is_banned,
                "is_admin": u.is_admin,
                "avatar_url": u.avatar_url,
                "created_at": u.created_at.isoformat() if u.created_at else None,
            }
            for u in users
        ]

    @staticmethod
    async def set_banned(
        db: AsyncSession, admin: User, username: str, banned: bool
    ) -> Dict[str, Any]:
        from .auth_service import normalize_username

        handle = normalize_username(username)
        user = await db.scalar(select(User).where(User.username == handle))
        if user is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found.")
        if user.id == admin.id:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="You can't ban yourself.")
        if user.is_admin:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="You can't ban another admin.")
        user.is_banned = banned
        await db.commit()
        return {"username": handle, "is_banned": banned}
