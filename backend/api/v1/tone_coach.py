from typing import List
from fastapi import APIRouter, Depends
from ...services.tone_coach_service import (
    ToneCoachService,
    TonalMinimalPair,
    ToneCalibrationRequest,
    ToneCalibrationResponse,
)
from .auth import get_current_user
from ...database.models import User

router = APIRouter(prefix="/tone-coach", tags=["Self-Learning Tonal Coach"])


@router.get("/minimal-pairs", response_model=List[TonalMinimalPair])
async def list_minimal_pairs(current_user: User = Depends(get_current_user)):
    """Get curated African tonal minimal pairs with target semitone contours."""
    return ToneCoachService.get_minimal_pairs()


@router.post("/calibrate", response_model=ToneCalibrationResponse)
async def calibrate_tone(
    req: ToneCalibrationRequest,
    current_user: User = Depends(get_current_user),
):
    """Calibrate user's spoken semitone pitch against baseline F0 and target tone."""
    # Use user's registered baseline if request default is passed
    if req.user_baseline_f0_hz == 138.0 and current_user.f0_baseline_hz:
        req.user_baseline_f0_hz = current_user.f0_baseline_hz
    return ToneCoachService.evaluate_tone_performance(req)
