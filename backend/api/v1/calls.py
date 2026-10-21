from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from ...database.session import get_db
from ...database.models import User
from ...services.call_signaling_service import (
    CallSignalingService,
    InitiateCallRequest,
    build_ice_servers,
)
from .auth import get_current_user

router = APIRouter(prefix="/calls", tags=["In-App Voice Calls & Telecom"])


@router.get("/ice-servers")
async def ice_servers(current_user: User = Depends(get_current_user)):
    """Return STUN/TURN ICE servers with time-limited credentials for WebRTC."""
    return {"ice_servers": build_ice_servers()}


@router.post("/initiate")
async def initiate_call(
    req: InitiateCallRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Initiate an In-App Voice Call or request a No-App Telecom call."""
    return await CallSignalingService.initiate_call(db, current_user, req)


@router.post("/{session_id}/answer")
async def answer_call(
    session_id: str,
    sdp_answer: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Answer an incoming In-App Call with WebRTC SDP answer."""
    return await CallSignalingService.answer_call(db, session_id, sdp_answer)


@router.post("/{session_id}/end")
async def end_call(
    session_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Hang up / terminate an active call session."""
    return await CallSignalingService.end_call(db, session_id)
