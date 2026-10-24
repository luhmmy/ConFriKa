from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from ...database.models import User
from ...database.session import get_db
from ...services.learning_stats_service import LearningStatsService
from ...services.native_tone_service import NativeToneService
from ...services.community_word_service import CommunityWordService, TeachWordRequest
from ...services.tone_coach_service import (
    ToneCoachService,
    TonalMinimalPair,
    ToneCalibrationRequest,
    ToneCalibrationResponse,
)
from .auth import get_current_user

router = APIRouter(prefix="/tone-coach", tags=["Self-Learning Tonal Coach"])


class ContributeToneRequest(BaseModel):
    target_word_id: str
    native_semitones: List[float] = Field(..., min_length=1)
    mean_f0_hz: float | None = None


@router.get("/languages")
async def list_tonal_languages(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """All tonal languages the coach supports (curated + community-taught),
    including Atyap. Curated ones ship gold pairs; the rest learn from natives."""
    counts = await CommunityWordService.counts_by_language(db)
    return ToneCoachService.languages(counts)


@router.get("/minimal-pairs", response_model=List[TonalMinimalPair])
async def list_minimal_pairs(
    language: Optional[str] = Query(None, description="Filter to one tonal language"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Tonal practice words for a language: curated gold pairs (where they exist)
    plus community-taught words, each enriched with the native-speaker target."""
    counts = await NativeToneService.community_counts(db)
    pairs: List[TonalMinimalPair] = []
    for p in ToneCoachService.get_minimal_pairs(language):
        community = None
        count = counts.get(p.id, 0)
        if count:
            community, count = await NativeToneService.community_target(db, p.id)
        pairs.append(
            p.model_copy(
                update={
                    "community_target_semitones": community,
                    "community_sample_count": count,
                }
            )
        )
    # Append community-taught words for this language.
    if language and language != "all":
        for w in await CommunityWordService.list_words(db, language):
            pairs.append(TonalMinimalPair(**w))
    return pairs


@router.post("/teach")
async def teach_word(
    req: TeachWordRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Native speakers add a word in any tonal language (e.g. Atyap) and record
    its real pitch, so others can practise against genuine pronunciations."""
    return await CommunityWordService.teach(db, current_user, req)


@router.post("/calibrate", response_model=ToneCalibrationResponse)
async def calibrate_tone(
    req: ToneCalibrationRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Score the user's spoken pitch against the target (native community target
    when available) and record the attempt toward their real stats."""
    if req.user_baseline_f0_hz == 138.0 and current_user.f0_baseline_hz:
        req.user_baseline_f0_hz = current_user.f0_baseline_hz

    community, _ = await NativeToneService.community_target(db, req.target_word_id)
    result = ToneCoachService.evaluate_tone_performance(req, target_override=community)
    pair = ToneCoachService.get_pair(req.target_word_id)

    await LearningStatsService.record_practice(
        db,
        current_user,
        base_word=pair.base_word,
        diacritized_spelling=result.target_word,
        meaning=result.meaning,
        tone_pattern=pair.tone_pattern,
        measured_f0_hz=result.mean_f0_hz,
        semitone_contour=result.learner_semitones,
        match_score_pct=result.match_score_pct,
    )
    return result


@router.post("/contribute")
async def contribute_native_tone(
    req: ContributeToneRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Native speakers record a reference pronunciation; the app learns from it."""
    return await NativeToneService.contribute(
        db,
        current_user,
        word_id=req.target_word_id,
        semitones=req.native_semitones,
        mean_f0_hz=req.mean_f0_hz,
    )
