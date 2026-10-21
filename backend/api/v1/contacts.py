from typing import List, Optional
from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from ...database.session import get_db
from ...database.models import User
from ...services.contact_service import ContactService
from .auth import get_current_user

router = APIRouter(prefix="/contacts", tags=["Contacts & Directory"])


class AddContactRequest(BaseModel):
    username: str
    alias_name: Optional[str] = None
    preferred_language: Optional[str] = None


@router.get("")
async def list_contacts(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """List saved contacts with dialable @username, name, dialect, and live online indicator."""
    return await ContactService.get_user_contacts(db, current_user.id)


@router.post("")
async def add_contact(
    req: AddContactRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Add a person to your contacts list by their @username."""
    return await ContactService.add_contact(
        db,
        user_id=current_user.id,
        contact_username=req.username,
        alias_name=req.alias_name,
        preferred_language=req.preferred_language,
    )


@router.get("/search")
async def search_directory(
    q: str = Query(..., min_length=1, description="Query @username, name, origin, or dialect"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Search users across all 54 African countries."""
    return await ContactService.search_directory(db, q, exclude_user_id=current_user.id)
