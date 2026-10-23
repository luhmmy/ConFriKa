"""Crowd-sourced tone learning from real native speakers.

Native speakers of a dialect record target words; the platform averages their
pitch (semitone) contours into a community target that learners then train
against. The more natives contribute, the more the target reflects how the word
is actually spoken — the app "learns" the tone from the people who own it.
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional, Tuple

from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..database.models import NativeToneSample, User
from .tone_coach_service import ToneCoachService

# A community target is used once at least this many natives have contributed.
MIN_SAMPLES = 2


def _resample(xs: List[float], n: int) -> List[float]:
    if not xs or n <= 0:
        return []
    if len(xs) == n:
        return [float(x) for x in xs]
    if len(xs) == 1:
        return [float(xs[0])] * n
    out: List[float] = []
    for i in range(n):
        pos = i * (len(xs) - 1) / (n - 1)
        lo = int(pos)
        hi = min(lo + 1, len(xs) - 1)
        frac = pos - lo
        out.append(round(xs[lo] * (1 - frac) + xs[hi] * frac, 3))
    return out


def _looks_native(dialect: str) -> bool:
    """A contributor counts as native when they registered with an African
    dialect (not a global lingua franca). Keeps global-language speakers from
    skewing a dialect's tone target."""
    d = (dialect or "").strip().lower()
    if not d:
        return False
    global_langs = ("english", "français", "francais", "french", "português",
                    "portuguese", "arabic", "العربية")
    return not any(g in d for g in global_langs)


class NativeToneService:
    @classmethod
    async def contribute(
        cls,
        db: AsyncSession,
        user: User,
        word_id: str,
        semitones: List[float],
        mean_f0_hz: Optional[float] = None,
    ) -> Dict[str, Any]:
        if not _looks_native(user.primary_dialect):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Only native speakers (registered with an African dialect) "
                "can contribute a reference pronunciation.",
            )
        if not semitones:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="No pitch contour was provided.",
            )
        pair = ToneCoachService.get_pair(word_id)
        contour = _resample([float(s) for s in semitones], len(pair.target_semitones))

        db.add(
            NativeToneSample(
                word_id=pair.id,
                dialect=user.primary_dialect,
                contributor_id=user.id,
                semitone_contour=contour,
                mean_f0_hz=mean_f0_hz,
            )
        )
        await db.commit()

        target, count = await cls.community_target(db, pair.id)
        return {
            "status": "recorded",
            "word_id": pair.id,
            "community_sample_count": count,
            "community_target_semitones": target,
            "thanks": f"Added your native {pair.diacritized_word} pronunciation.",
        }

    @classmethod
    async def community_target(
        cls, db: AsyncSession, word_id: str
    ) -> Tuple[Optional[List[float]], int]:
        rows = (
            await db.scalars(
                select(NativeToneSample.semitone_contour).where(
                    NativeToneSample.word_id == word_id
                )
            )
        ).all()
        count = len(rows)
        if count < MIN_SAMPLES:
            return None, count
        # Element-wise average of the (equal-length) contours.
        length = len(rows[0])
        clean = [r for r in rows if isinstance(r, list) and len(r) == length and length > 0]
        if not clean:
            return None, count
        avg = [round(sum(r[i] for r in clean) / len(clean), 3) for i in range(length)]
        return avg, count

    @classmethod
    async def community_counts(cls, db: AsyncSession) -> Dict[str, int]:
        rows = (
            await db.execute(
                select(NativeToneSample.word_id, func.count(NativeToneSample.id)).group_by(
                    NativeToneSample.word_id
                )
            )
        ).all()
        return {word_id: int(n) for word_id, n in rows}
