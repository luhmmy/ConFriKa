from typing import Any, Dict, List, Optional

from fastapi import HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..config.settings import settings
from ..database.models import DirectMessage, GlobalSpacesMessage, User
from .auth_service import normalize_username
from .speech_translation_service import SpeechTranslationService, TranslationRequest


class SendDmRequest(BaseModel):
    recipient_username: str
    message_type: str = "text"  # 'text' or 'voicenote'
    original_text: str = Field(..., min_length=1)
    source_dialect: str = "English"
    target_dialect: Optional[str] = None
    audio_url: Optional[str] = None
    audio_duration_seconds: Optional[float] = None
    auto_translate: bool = True


class SendSpacesRequest(BaseModel):
    channel_category: str = "all"  # 'all', 'trade', 'culture'
    country_filter: str = "ALL"
    message_type: str = "text"
    original_text: str = Field(..., min_length=1)
    source_dialect: str = "English"
    duration_label: Optional[str] = None
    audio_url: Optional[str] = None
    auto_translate: bool = True


def _initials(name: str) -> str:
    parts = [w for w in name.split() if w]
    return ("".join(w[0] for w in parts[:2]).upper()) or "·"


def _duration_label(seconds: Optional[float]) -> str:
    if not seconds or seconds <= 0:
        return ""
    total = int(round(seconds))
    return f"{total // 60}:{total % 60:02d}"


class ChatService:
    @classmethod
    async def _translate(cls, text: str, source: str, target: str) -> Optional[str]:
        if not target or source.strip().lower() == target.strip().lower():
            return None
        res = await SpeechTranslationService.translate_text(
            TranslationRequest(text=text, source_dialect=source, target_dialect=target)
        )
        return res.translated_text

    @classmethod
    async def get_direct_messages(
        cls, db: AsyncSession, current_user: User, partner_username: str
    ) -> List[Dict[str, Any]]:
        partner_handle = normalize_username(partner_username)
        partner = await db.scalar(select(User).where(User.username == partner_handle))

        conditions = [
            (DirectMessage.sender_id == current_user.id)
            & (DirectMessage.recipient_username == partner_handle)
        ]
        if partner is not None:
            conditions.append(
                (DirectMessage.sender_id == partner.id)
                & (DirectMessage.recipient_username == current_user.username)
            )

        stmt = (
            select(DirectMessage)
            .where(or_(*conditions))
            .order_by(DirectMessage.created_at.asc())
        )
        rows = (await db.scalars(stmt)).all()

        thread: List[Dict[str, Any]] = []
        for m in rows:
            is_me = m.sender_id == current_user.id
            sender = current_user if is_me else partner
            thread.append(
                {
                    "id": m.id,
                    "sender_username": sender.username if sender else partner_handle,
                    "sender_name": sender.full_name if sender else partner_handle.lstrip("@"),
                    "message_type": m.message_type,
                    "duration_label": _duration_label(m.audio_duration_seconds),
                    "dialect_name": m.source_dialect,
                    "original_text": m.original_text,
                    "translated_text": m.translated_text,
                    "audio_url": m.audio_url,
                    "is_me": is_me,
                    "is_read": m.is_read,
                    "created_at": m.created_at.isoformat(),
                }
            )
        return thread

    @classmethod
    async def get_conversations(
        cls, db: AsyncSession, current_user: User
    ) -> List[Dict[str, Any]]:
        """WhatsApp-style conversation list: one row per chat partner with the
        last message preview, its time, and how many messages are unread."""
        me = current_user.username
        # Every DM that involves me: either I sent it, or it was sent to me.
        stmt = (
            select(DirectMessage)
            .join(User, User.id == DirectMessage.sender_id)
            .where(
                or_(
                    DirectMessage.sender_id == current_user.id,
                    DirectMessage.recipient_username == me,
                )
            )
            .order_by(DirectMessage.created_at.asc())
        )
        rows = (await db.execute(stmt)).scalars().all()

        # Resolve sender handle/name for each message in one pass.
        sender_ids = {m.sender_id for m in rows}
        users = {
            u.id: u
            for u in (
                await db.scalars(select(User).where(User.id.in_(sender_ids)))
            ).all()
        }

        convos: Dict[str, Dict[str, Any]] = {}
        for m in rows:
            sender = users.get(m.sender_id)
            is_me = m.sender_id == current_user.id
            # The "other party" of this conversation.
            partner_handle = m.recipient_username if is_me else (
                sender.username if sender else me
            )
            if partner_handle == me:
                continue
            convo = convos.setdefault(
                partner_handle,
                {
                    "partner_username": partner_handle,
                    "partner_name": partner_handle.lstrip("@"),
                    "last_message": "",
                    "last_message_type": "text",
                    "last_at": None,
                    "unread_count": 0,
                    "last_is_me": False,
                },
            )
            # Prefer a real display name when we know the partner user.
            if not is_me and sender is not None:
                convo["partner_name"] = sender.full_name
            # Messages roll forward in time, so the final write is the latest.
            convo["last_message"] = (
                m.original_text if m.message_type == "text" else "🎤 Voice note"
            )
            convo["last_message_type"] = m.message_type
            convo["last_at"] = m.created_at.isoformat()
            convo["last_is_me"] = is_me
            if (not is_me) and (not m.is_read):
                convo["unread_count"] += 1

        # Newest conversation first.
        return sorted(
            convos.values(),
            key=lambda c: c["last_at"] or "",
            reverse=True,
        )

    @classmethod
    async def mark_thread_read(
        cls, db: AsyncSession, current_user: User, partner_username: str
    ) -> Dict[str, Any]:
        """Mark every message the partner sent me in this thread as read."""
        partner_handle = normalize_username(partner_username)
        partner = await db.scalar(select(User).where(User.username == partner_handle))
        if partner is None:
            return {"status": "ok", "marked": 0}
        rows = (
            await db.scalars(
                select(DirectMessage).where(
                    (DirectMessage.sender_id == partner.id)
                    & (DirectMessage.recipient_username == current_user.username)
                    & (DirectMessage.is_read == False)  # noqa: E712
                )
            )
        ).all()
        for m in rows:
            m.is_read = True
        await db.commit()
        return {"status": "ok", "marked": len(rows)}

    @classmethod
    async def send_direct_message(
        cls, db: AsyncSession, current_user: User, req: SendDmRequest
    ) -> Dict[str, Any]:
        recipient_handle = normalize_username(req.recipient_username)
        recipient = await db.scalar(select(User).where(User.username == recipient_handle))
        if recipient is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Recipient {recipient_handle} was not found.",
            )

        # Translate into the recipient's own dialect so they read it natively.
        target = req.target_dialect or recipient.primary_dialect
        translated = None
        if req.auto_translate and req.message_type == "text":
            translated = await cls._translate(req.original_text, req.source_dialect, target)

        dm = DirectMessage(
            sender_id=current_user.id,
            recipient_username=recipient_handle,
            message_type=req.message_type,
            original_text=req.original_text,
            translated_text=translated,
            source_dialect=req.source_dialect,
            target_dialect=target,
            audio_url=req.audio_url,
            audio_duration_seconds=req.audio_duration_seconds,
            is_read=False,
        )
        db.add(dm)
        await db.commit()
        await db.refresh(dm)

        return {
            "id": dm.id,
            "sender_username": current_user.username,
            "sender_name": current_user.full_name,
            "recipient_username": recipient_handle,
            "message_type": dm.message_type,
            "duration_label": _duration_label(dm.audio_duration_seconds),
            "dialect_name": dm.source_dialect,
            "original_text": dm.original_text,
            "translated_text": dm.translated_text,
            "audio_url": dm.audio_url,
            "is_me": True,
            "created_at": dm.created_at.isoformat(),
        }

    @classmethod
    async def get_spaces_messages(
        cls, db: AsyncSession, channel: str = "all", country: str = "ALL", limit: int = 100
    ) -> List[Dict[str, Any]]:
        stmt = select(GlobalSpacesMessage)
        if channel and channel != "all":
            stmt = stmt.where(GlobalSpacesMessage.channel_category == channel)
        if country and country != "ALL":
            stmt = stmt.where(GlobalSpacesMessage.country_filter == country)
        stmt = stmt.order_by(GlobalSpacesMessage.created_at.asc()).limit(limit)
        rows = (await db.scalars(stmt)).all()

        return [
            {
                "id": m.id,
                "sender_name": m.sender_name,
                "sender_username": m.sender_username,
                "sender_location": m.sender_location,
                "sender_initials": _initials(m.sender_name),
                "channel_category": m.channel_category,
                "dialect_name": m.source_dialect,
                "message_type": m.message_type,
                "duration_label": m.duration_label or "",
                "original_text": m.original_text,
                "translated_text": m.translated_text,
                "audio_url": m.audio_url,
                "created_at": m.created_at.isoformat(),
            }
            for m in rows
        ]

    @classmethod
    async def post_spaces_message(
        cls, db: AsyncSession, current_user: User, req: SendSpacesRequest
    ) -> Dict[str, Any]:
        translated = None
        if req.auto_translate and req.message_type == "text":
            translated = await cls._translate(req.original_text, req.source_dialect, "English")

        location = f"{current_user.origin_region}".strip()
        msg = GlobalSpacesMessage(
            sender_id=current_user.id,
            sender_name=current_user.full_name,
            sender_username=current_user.username,
            sender_location=location or current_user.country_code,
            channel_category=req.channel_category,
            country_filter=req.country_filter,
            message_type=req.message_type,
            original_text=req.original_text,
            translated_text=translated,
            source_dialect=req.source_dialect,
            duration_label=req.duration_label,
            audio_url=req.audio_url,
        )
        db.add(msg)
        await db.commit()
        await db.refresh(msg)

        return {
            "id": msg.id,
            "sender_name": msg.sender_name,
            "sender_username": msg.sender_username,
            "sender_location": msg.sender_location,
            "sender_initials": _initials(msg.sender_name),
            "channel_category": msg.channel_category,
            "dialect_name": msg.source_dialect,
            "message_type": msg.message_type,
            "duration_label": msg.duration_label or "",
            "original_text": msg.original_text,
            "translated_text": msg.translated_text,
            "audio_url": msg.audio_url,
            "created_at": msg.created_at.isoformat(),
        }
