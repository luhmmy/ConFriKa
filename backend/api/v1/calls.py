import base64

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession
from ...config.settings import settings
from ...database.session import get_db
from ...database.models import User
from ...services.call_signaling_service import (
    CallSignalingService,
    InitiateCallRequest,
    build_ice_servers,
)
from ...services.voice_service import VoiceService
from ...services import billing_service
from .auth import get_current_user

router = APIRouter(prefix="/calls", tags=["In-App Voice Calls & Telecom"])


@router.get("/voice/status")
async def voice_status(current_user: User = Depends(get_current_user)):
    """Whether this user has enrolled a translation voice, and if the service is on."""
    return {
        "enrolled": bool(current_user.voice_id),
        "voice_service_configured": settings.voice_configured,
    }


@router.post("/voice/enroll")
async def enroll_voice(
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Create a voice clone from a short enrollment recording so live call
    translation can speak in the user's own voice."""
    # Voice-preserving ("speak in your own voice") is a ConFriKa Pro feature.
    billing_service.require_pro(current_user, "Voice-preserving call translation")
    if not settings.voice_configured:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                            detail="Voice service is not configured yet.")
    audio = await file.read()
    if len(audio) > settings.VOICE_MAX_CLIP_BYTES * 4:
        raise HTTPException(status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                            detail="Recording too large.")
    voice_id = await VoiceService.create_voice_clone(
        name=f"confrika_{current_user.username.lstrip('@')}", audio=audio
    )
    if not voice_id:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY,
                            detail="Could not create the voice. Try a clearer, longer sample.")
    current_user.voice_id = voice_id
    await db.commit()
    return {"status": "enrolled", "voice_id": voice_id}


class TranslateUtteranceRequest(BaseModel):
    audio_b64: str = Field(..., description="Base64-encoded WAV/MP3 of one spoken phrase")
    source_dialect: str = "English"
    target_dialect: str = "English"
    voice_id: str | None = None  # cloned-voice id to re-speak in the speaker's tone


@router.post("/translate-utterance")
async def translate_utterance(
    req: TranslateUtteranceRequest,
    current_user: User = Depends(get_current_user),
):
    """Live call translation: STT → translate → voice-clone TTS for one utterance.
    Returns the translated text and (when the voice service is configured) audio
    re-spoken in the speaker's own voice. Stub mode returns text only."""
    try:
        audio = base64.b64decode(req.audio_b64)
    except Exception:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="audio_b64 is not valid base64.")
    if len(audio) > settings.VOICE_MAX_CLIP_BYTES:
        raise HTTPException(status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, detail="Utterance clip too large.")
    # Count translated call time against the free daily cap (Pro = unlimited).
    # One utterance is billed a flat ~10s estimate of speaking time.
    await billing_service.enforce(current_user, "call_seconds", amount=10)
    out = await VoiceService.translate_utterance(
        audio=audio,
        source_dialect=req.source_dialect,
        target_dialect=req.target_dialect,
        voice_id=req.voice_id or current_user.voice_id,
    )
    return {
        "source_text": out.source_text,
        "translated_text": out.translated_text,
        "audio_b64": out.audio_b64,
        "provider": out.provider,
        "voice_service_configured": settings.voice_configured,
    }


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


@router.get("/history")
async def call_history(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Recent calls involving the user (incoming/outgoing, with missed flags)."""
    return await CallSignalingService.history(db, current_user)


class CallOutcomeRequest(BaseModel):
    connected: bool = False
    duration_seconds: int = 0


@router.post("/{session_id}/outcome")
async def record_call_outcome(
    session_id: str,
    req: CallOutcomeRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Record how a call ended so it appears in call history."""
    return await CallSignalingService.record_outcome(
        db, session_id, req.connected, req.duration_seconds
    )


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
