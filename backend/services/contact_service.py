from typing import Any, Dict, List, Optional

from fastapi import HTTPException, status
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..database.models import User, UserContact
from . import presence
from .auth_service import normalize_username


def country_flag(code: Optional[str]) -> str:
    """Render an ISO 3166-1 alpha-2 code as its flag emoji (real, computed)."""
    if not code or len(code) != 2 or not code.isalpha():
        return "🌍"
    base = 0x1F1E6
    return "".join(chr(base + (ord(c) - ord("A"))) for c in code.upper())


def _initials(name: str) -> str:
    parts = [w for w in name.split() if w]
    return ("".join(w[0] for w in parts[:2]).upper()) or "·"


def _user_descriptor(user: User, alias: Optional[str] = None) -> Dict[str, Any]:
    display = alias or user.full_name
    return {
        "username": user.username,
        "name": display,
        "initials": _initials(display),
        "country_code": user.country_code,
        "flag": country_flag(user.country_code),
        "origin": user.origin_region,
        "dialect": user.primary_dialect,
        "is_online": presence.is_online(user.username),
    }


class ContactService:
    @classmethod
    async def get_user_contacts(cls, db: AsyncSession, user_id: str) -> List[Dict[str, Any]]:
        stmt = select(UserContact).where(UserContact.user_id == user_id)
        records = (await db.scalars(stmt)).all()

        results: List[Dict[str, Any]] = []
        for r in records:
            target = await db.scalar(select(User).where(User.username == r.contact_username))
            if target is not None:
                results.append(_user_descriptor(target, r.alias_name))
            else:
                # Contact saved but not (yet) a registered user.
                handle = r.contact_username
                name = r.alias_name or handle.lstrip("@").replace("_", " ").title()
                results.append(
                    {
                        "username": handle,
                        "name": name,
                        "initials": _initials(name),
                        "country_code": None,
                        "flag": "🌍",
                        "origin": None,
                        "dialect": r.preferred_language,
                        "is_online": False,
                        "pending": True,
                    }
                )
        return results

    @classmethod
    async def add_contact(
        cls,
        db: AsyncSession,
        user_id: str,
        contact_username: str,
        alias_name: Optional[str] = None,
        preferred_language: Optional[str] = None,
    ) -> Dict[str, Any]:
        handle = normalize_username(contact_username)

        owner = await db.get(User, user_id)
        if owner and owner.username == handle:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="You cannot add yourself as a contact.",
            )

        target = await db.scalar(select(User).where(User.username == handle))
        if target is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"No ConFriKa user found with username {handle}.",
            )

        existing = await db.scalar(
            select(UserContact).where(
                (UserContact.user_id == user_id)
                & (UserContact.contact_username == handle)
            )
        )
        if existing is None:
            db.add(
                UserContact(
                    user_id=user_id,
                    contact_username=handle,
                    alias_name=alias_name,
                    preferred_language=preferred_language or target.primary_dialect,
                )
            )
            await db.commit()

        return _user_descriptor(target, alias_name)

    @classmethod
    async def search_directory(
        cls, db: AsyncSession, query: str, exclude_user_id: Optional[str] = None, limit: int = 25
    ) -> List[Dict[str, Any]]:
        q = query.strip().lower()
        if not q:
            return []
        like = f"%{q}%"
        stmt = (
            select(User)
            .where(
                or_(
                    func.lower(User.username).like(like),
                    func.lower(User.full_name).like(like),
                    func.lower(User.primary_dialect).like(like),
                    func.lower(User.origin_region).like(like),
                    func.lower(User.country_code) == q,
                )
            )
            .limit(limit)
        )
        rows = (await db.scalars(stmt)).all()
        return [
            _user_descriptor(u)
            for u in rows
            if exclude_user_id is None or u.id != exclude_user_id
        ]
