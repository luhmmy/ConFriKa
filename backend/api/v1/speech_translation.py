from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status

from ...config.settings import settings
from ...database.models import User
from ...services.pitch_service import PitchService
from ...services.speech_translation_service import (
    SpeechTranslationService,
    TranslationRequest,
    TranslationResponse,
)
from ...services import billing_service
from .auth import get_current_user

router = APIRouter(prefix="/speech", tags=["African Speech & Translation"])


@router.post("/translate", response_model=TranslationResponse)
async def translate_text(
    req: TranslationRequest,
    current_user: User = Depends(get_current_user),
):
    """Translate text across African language pairs with real neural MT."""
    await billing_service.enforce(current_user, "translations")
    return await SpeechTranslationService.translate_text(req)


@router.post("/pitch-analysis")
async def pitch_analysis(
    audio: UploadFile = File(...),
    baseline_f0_hz: float = 138.0,
    current_user: User = Depends(get_current_user),
):
    """Analyze an uploaded WAV sample, returning F0 track and semitone contour."""
    data = await audio.read()
    if len(data) > settings.MAX_AUDIO_BYTES:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="Audio payload exceeds the maximum allowed size.",
        )
    try:
        result = PitchService.analyze_wav(data, baseline_f0_hz=baseline_f0_hz)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc))
    return result.__dict__
