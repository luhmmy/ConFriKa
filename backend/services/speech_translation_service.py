from typing import List, Optional

from fastapi import HTTPException, status
from pydantic import BaseModel, Field

from ..config.settings import settings
from . import translation_engine


class TranslationRequest(BaseModel):
    text: str = Field(..., min_length=1)
    source_dialect: str = "English"
    target_dialect: str = "Yorùbá"
    respect_tones: bool = True
    formality: str = "respectful"  # 'respectful', 'formal', 'casual'


class TranslationResponse(BaseModel):
    original_text: str
    translated_text: str
    source_dialect: str
    target_dialect: str
    source_code: str
    target_code: str
    detected_diacritics: List[str]
    confidence_score: float
    model: str
    phonetic_pronunciation_guide: Optional[str] = None


# Combining tone marks and special African orthographic characters used for
# genuine diacritic detection (not a lookup table — these are scanned in text).
_TONE_MARKS = [
    "́",  # acute (high tone)
    "̀",  # grave (low tone)
    "̂",  # circumflex
    "̌",  # caron
    "̄",  # macron (mid tone)
    "ọ", "ẹ", "ṣ", "ị", "ụ", "ṅ", "ɓ", "ɗ", "ŋ", "ɛ", "ɔ", "ǹ",
]


class SpeechTranslationService:
    @classmethod
    def extract_diacritics(cls, text: str) -> List[str]:
        low = text.lower()
        return [m for m in _TONE_MARKS if m in low]

    @classmethod
    async def translate_text(cls, req: TranslationRequest) -> TranslationResponse:
        if len(req.text) > settings.MAX_TEXT_LENGTH:
            raise HTTPException(
                status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                detail=f"Text exceeds the {settings.MAX_TEXT_LENGTH} character limit.",
            )

        result = await translation_engine.translate(
            req.text, req.source_dialect, req.target_dialect
        )
        diacritics = cls.extract_diacritics(result.translated_text)

        return TranslationResponse(
            original_text=req.text,
            translated_text=result.translated_text,
            source_dialect=req.source_dialect,
            target_dialect=req.target_dialect,
            source_code=result.source_code,
            target_code=result.target_code,
            detected_diacritics=diacritics,
            confidence_score=result.confidence,
            model=result.model,
        )
