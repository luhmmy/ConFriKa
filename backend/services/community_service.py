"""Communities: joinable spaces (Business & Tech, Culture & Music, …) that scope
the Global Spaces feed. One community is the default — everyone is a member of it
automatically. Users can also create their own communities."""
from __future__ import annotations

import re
from typing import Any, Dict, List, Optional

from fastapi import HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..database.models import Community, CommunityMembership, User

# Seeded on first startup. The default community has everyone as a member.
_DEFAULT_COMMUNITIES = [
    ("lounge", "ConFriKa Lounge", "The pan-African town square — everyone's here.", "🌍", "general", True),
    ("trade", "Business & Tech", "Trade, startups, jobs and technology across Africa.", "💼", "business", False),
    ("culture", "Culture & Music", "Music, film, food, fashion and traditions.", "🎶", "culture", False),
    ("language", "Language Exchange", "Practise dialects and help others learn.", "🗣️", "learning", False),
    ("sports", "Sports", "Football and sports talk across the continent.", "⚽", "sports", False),
    ("news", "News & Current Affairs", "What's happening across the 54 nations.", "📰", "news", False),
]


class CreateCommunityRequest(BaseModel):
    name: str = Field(..., min_length=3, max_length=60)
    description: Optional[str] = Field(None, max_length=240)
    icon: str = Field("🌍", max_length=8)
    category: str = Field("general", max_length=40)


def _slugify(name: str) -> str:
    s = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
    return s[:40] or "community"


class CommunityService:
    @classmethod
    async def ensure_defaults(cls, db: AsyncSession) -> None:
        for slug, name, desc, icon, cat, is_def in _DEFAULT_COMMUNITIES:
            exists = await db.scalar(select(Community).where(Community.slug == slug))
            if not exists:
                db.add(Community(
                    slug=slug, name=name, description=desc, icon=icon,
                    category=cat, is_default=is_def,
                ))
        await db.commit()

    @classmethod
    async def _member_count(cls, db: AsyncSession, community: Community) -> int:
        if community.is_default:
            return await db.scalar(select(func.count(User.id))) or 0
        return await db.scalar(
            select(func.count(CommunityMembership.id)).where(
                CommunityMembership.community_slug == community.slug
            )
        ) or 0

    @classmethod
    async def is_member(cls, db: AsyncSession, user: User, slug: str) -> bool:
        community = await db.scalar(select(Community).where(Community.slug == slug))
        if community is None:
            return False
        if community.is_default:
            return True
        row = await db.scalar(
            select(CommunityMembership).where(
                (CommunityMembership.user_id == user.id)
                & (CommunityMembership.community_slug == slug)
            )
        )
        return row is not None

    @classmethod
    async def list_communities(
        cls, db: AsyncSession, user: User
    ) -> List[Dict[str, Any]]:
        communities = (
            await db.scalars(select(Community).order_by(Community.is_default.desc(), Community.created_at.asc()))
        ).all()
        my = set(
            (await db.scalars(
                select(CommunityMembership.community_slug).where(
                    CommunityMembership.user_id == user.id
                )
            )).all()
        )
        out = []
        for c in communities:
            out.append({
                "slug": c.slug,
                "name": c.name,
                "description": c.description,
                "icon": c.icon,
                "category": c.category,
                "is_default": c.is_default,
                "joined": c.is_default or c.slug in my,
                "member_count": await cls._member_count(db, c),
            })
        return out

    @classmethod
    async def create_community(
        cls, db: AsyncSession, user: User, req: CreateCommunityRequest
    ) -> Dict[str, Any]:
        base = _slugify(req.name)
        slug = base
        i = 1
        while await db.scalar(select(Community).where(Community.slug == slug)):
            i += 1
            slug = f"{base}-{i}"[:40]
        community = Community(
            slug=slug, name=req.name.strip(), description=(req.description or "").strip() or None,
            icon=req.icon or "🌍", category=req.category or "general", created_by=user.id,
        )
        db.add(community)
        db.add(CommunityMembership(user_id=user.id, community_slug=slug))  # creator joins
        await db.commit()
        return {
            "slug": slug, "name": community.name, "description": community.description,
            "icon": community.icon, "category": community.category,
            "is_default": False, "joined": True, "member_count": 1,
        }

    @classmethod
    async def join(cls, db: AsyncSession, user: User, slug: str) -> Dict[str, Any]:
        community = await db.scalar(select(Community).where(Community.slug == slug))
        if community is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Community not found.")
        if not community.is_default and not await cls.is_member(db, user, slug):
            db.add(CommunityMembership(user_id=user.id, community_slug=slug))
            await db.commit()
        return {"status": "joined", "slug": slug}

    @classmethod
    async def leave(cls, db: AsyncSession, user: User, slug: str) -> Dict[str, Any]:
        community = await db.scalar(select(Community).where(Community.slug == slug))
        if community is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Community not found.")
        if community.is_default:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="You can't leave the default community.")
        row = await db.scalar(
            select(CommunityMembership).where(
                (CommunityMembership.user_id == user.id)
                & (CommunityMembership.community_slug == slug)
            )
        )
        if row is not None:
            await db.delete(row)
            await db.commit()
        return {"status": "left", "slug": slug}
