import base64
import hashlib
import hmac
import time
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from ..config.settings import settings
from ..database.models import CallSession, User


def build_ice_servers() -> List[Dict[str, Any]]:
    """Return ICE servers with time-limited TURN credentials (coturn REST auth)."""
    servers: List[Dict[str, Any]] = [{"urls": [settings.STUN_URL]}]
    if settings.TURN_HOST and settings.TURN_SECRET:
        expiry = int(time.time()) + settings.TURN_TTL_SECONDS
        username = str(expiry)
        digest = hmac.new(
            settings.TURN_SECRET.encode("utf-8"), username.encode("utf-8"), hashlib.sha1
        ).digest()
        credential = base64.b64encode(digest).decode("utf-8")
        servers.append(
            {
                "urls": [
                    f"turn:{settings.TURN_HOST}:{settings.TURN_PORT}?transport=udp",
                    f"turn:{settings.TURN_HOST}:{settings.TURN_PORT}?transport=tcp",
                ],
                "username": username,
                "credential": credential,
            }
        )
    return servers


class InitiateCallRequest(BaseModel):
    callee_username: str
    call_transport: str = "inapp"  # 'inapp' or 'telecom'
    sdp_offer: Optional[str] = None


class CallSignalMessage(BaseModel):
    session_id: str
    sender_username: str
    target_username: str
    signal_type: str  # 'offer', 'answer', 'candidate', 'hangup', 'reject'
    payload: Dict[str, Any]


class CallSignalingService:
    ACTIVE_SESSIONS: Dict[str, Dict[str, Any]] = {}

    @classmethod
    async def initiate_call(
        cls, db: AsyncSession, caller: User, req: InitiateCallRequest
    ) -> Dict[str, Any]:
        callee_handle = req.callee_username.strip().lower()
        if not callee_handle.startswith("@"):
            callee_handle = "@" + callee_handle

        if req.call_transport == "telecom":
            return {
                "status": "coming_soon",
                "message": "No-App (PSTN) calling is not available yet. Please use In-App Call.",
                "call_transport": "telecom",
            }

        session = CallSession(
            caller_id=caller.id,
            caller_username=caller.username,
            callee_username=callee_handle,
            call_transport="inapp",
            status="ringing",
        )
        db.add(session)
        await db.commit()
        await db.refresh(session)

        session_data = {
            "session_id": session.id,
            "caller_username": caller.username,
            "caller_name": caller.full_name,
            "callee_username": callee_handle,
            "status": "ringing",
            "sdp_offer": req.sdp_offer,
            "created_at": datetime.now(timezone.utc).isoformat(),
        }
        cls.ACTIVE_SESSIONS[session.id] = session_data

        return {
            "session_id": session.id,
            "status": "ringing",
            "caller": caller.username,
            "callee": callee_handle,
            "call_transport": "inapp",
        }

    @classmethod
    async def answer_call(
        cls, db: AsyncSession, session_id: str, sdp_answer: str
    ) -> Dict[str, Any]:
        session_data = cls.ACTIVE_SESSIONS.get(session_id)
        if session_data:
            session_data["status"] = "connected"
            session_data["sdp_answer"] = sdp_answer
            session_data["connected_at"] = datetime.now(timezone.utc).isoformat()

        return {
            "session_id": session_id,
            "status": "connected",
            "sdp_answer": sdp_answer,
        }

    @classmethod
    async def end_call(cls, db: AsyncSession, session_id: str) -> Dict[str, Any]:
        session_data = cls.ACTIVE_SESSIONS.pop(session_id, None)
        return {
            "session_id": session_id,
            "status": "ended",
        }
