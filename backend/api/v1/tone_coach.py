from typing import List

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from ...database.models import User
from ...database.session import get_db
from ...services.learning_stats_service import LearningStatsService
from ...services.native_tone_service import NativeToneService
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


@router.get("/minimal-pairs", response_model=List[TonalMinimalPair])
async def list_minimal_pairs(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Curated tonal minimal pairs, enriched with the native-speaker community
    target where enough speakers have contributed."""
    counts = await NativeToneService.community_counts(db)
    pairs: List[TonalMinimalPair] = []
    for p in ToneCoachService.get_minimal_pairs():
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
    return pairs


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
