from typing import Optional
from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession
from ...database.session import get_db
from ...database.models import User
from ...services.chat_service import (
    ChatService,
    SendDmRequest,
    SendSpacesRequest,
)
from .auth import get_current_user

router = APIRouter(prefix="/chat", tags=["Chat & Direct Messages"])


@router.get("/conversations")
async def list_conversations(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """List my direct-message conversations (one row per partner, newest first)."""
    return await ChatService.get_conversations(db, current_user)


@router.post("/dm/{username}/read")
async def mark_thread_read(
    username: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Mark all messages from this partner as read."""
    return await ChatService.mark_thread_read(db, current_user, username)


@router.get("/dm/{username}")
async def get_direct_message_thread(
    username: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get 1-on-1 private chat thread with a specific contact (@username)."""
    return await ChatService.get_direct_messages(db, current_user, username)


@router.post("/dm")
async def send_direct_message(
    req: SendDmRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Send a private text message or voice note to a contact with optional auto-translation."""
    return await ChatService.send_direct_message(db, current_user, req)


@router.get("/spaces")
async def get_spaces_messages(
    channel: str = Query("all", description="Channel filter: all, trade, culture"),
    country: str = Query("ALL", description="Country code filter (ALL or 54 African country ISO)"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Retrieve public Pan-African Global Spaces messages and voice notes."""
    return await ChatService.get_spaces_messages(db, channel, country)


@router.post("/spaces")
async def post_spaces_message(
    req: SendSpacesRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Post a message or voice note to public Pan-African Global Spaces."""
    return await ChatService.post_spaces_message(db, current_user, req)
