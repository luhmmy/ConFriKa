"""Community-taught tone words: native speakers add words for any tonal language
(including ones with no curated data, like Atyap/Tyap) and record their real
pitch. The target is the average of native recordings, never fabricated."""
from __future__ import annotations

import re
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..database.models import CommunityToneWord, NativeToneSample, User

_CONTOUR_LEN = 6


class TeachWordRequest(BaseModel):
    language: str = Field(..., min_length=2, max_length=60)
    spelling: str = Field(..., min_length=1, max_length=80)
    meaning: str = Field(..., min_length=1, max_length=120)
    tone_pattern: Optional[str] = Field(None, max_length=60)
    semitones: List[float] = Field(..., min_length=1)


def _slug(language: str, spelling: str) -> str:
    base = re.sub(r"[^a-z0-9]+", "-", f"{language}-{spelling}".lower()).strip("-")
    return base[:60] or "word"


def _resample(xs: List[float], n: int) -> List[float]:
    if not xs:
        return [0.0] * n
    if len(xs) == n:
        return [round(float(x), 3) for x in xs]
    out = []
    for i in range(n):
        pos = i * (len(xs) - 1) / (n - 1) if n > 1 else 0
        lo = int(pos)
        hi = min(lo + 1, len(xs) - 1)
        frac = pos - lo
        out.append(round(float(xs[lo]) * (1 - frac) + float(xs[hi]) * frac, 3))
    return out


class CommunityWordService:
    @classmethod
    async def _target(cls, db: AsyncSession, word_id: str):
        rows = (
            await db.scalars(
                select(NativeToneSample.semitone_contour).where(
                    NativeToneSample.word_id == word_id
                )
            )
        ).all()
        count = len(rows)
        clean = [r for r in rows if isinstance(r, list) and len(r) == _CONTOUR_LEN]
        if not clean:
            return None, count
        avg = [round(sum(r[i] for r in clean) / len(clean), 3) for i in range(_CONTOUR_LEN)]
        return avg, count

    @classmethod
    async def teach(
        cls, db: AsyncSession, user: User, req: TeachWordRequest
    ) -> Dict[str, Any]:
        word_id = _slug(req.language, req.spelling)
        word = await db.scalar(
            select(CommunityToneWord).where(CommunityToneWord.word_id == word_id)
        )
        if word is None:
            word = CommunityToneWord(
                word_id=word_id,
                language=req.language.strip(),
                spelling=req.spelling.strip(),
                meaning=req.meaning.strip(),
                tone_pattern=(req.tone_pattern or "").strip() or None,
                created_by=user.id,
            )
            db.add(word)
        db.add(
            NativeToneSample(
                word_id=word_id,
                dialect=user.primary_dialect,
                contributor_id=user.id,
                semitone_contour=_resample([float(s) for s in req.semitones], _CONTOUR_LEN),
            )
        )
        await db.commit()
        target, count = await cls._target(db, word_id)
        return {
            "status": "taught",
            "word_id": word_id,
            "language": req.language,
            "community_sample_count": count,
            "community_target_semitones": target,
            "thanks": f"Added your native “{req.spelling}”. Thank you for teaching {req.language}.",
        }

    @classmethod
    async def list_words(cls, db: AsyncSession, language: str) -> List[Dict[str, Any]]:
        words = (
            await db.scalars(
                select(CommunityToneWord)
                .where(CommunityToneWord.language == language)
                .order_by(CommunityToneWord.created_at.desc())
            )
        ).all()
        out = []
        for w in words:
            target, count = await cls._target(db, w.word_id)
            out.append({
                "id": w.word_id,
                "language": w.language,
                "base_word": w.spelling,
                "diacritized_word": w.spelling,
                "meaning": w.meaning,
                "tone_pattern": w.tone_pattern or "Community",
                "target_semitones": target or [],
                "community_target_semitones": target,
                "community_sample_count": count,
                "coaching_tip": (
                    "Practise against the native-speaker recordings."
                    if target else "No native recording yet. Be the first to teach it."
                ),
                "source": "community",
            })
        return out

    @classmethod
    async def counts_by_language(cls, db: AsyncSession) -> Dict[str, int]:
        rows = (
            await db.execute(
                select(CommunityToneWord.language, func.count(CommunityToneWord.id))
                .group_by(CommunityToneWord.language)
            )
        ).all()
        return {lang: n for lang, n in rows}
