import math
from typing import List, Dict, Any
from pydantic import BaseModel, Field


class TonalMinimalPair(BaseModel):
    id: str
    base_word: str
    diacritized_word: str
    tone_pattern: str
    meaning: str
    target_semitones: List[float]
    coaching_tip: str


class ToneCalibrationRequest(BaseModel):
    user_baseline_f0_hz: float = Field(default=138.0, ge=70.0, le=400.0)
    target_word_id: str
    learner_semitones: List[float]


class ToneCalibrationResponse(BaseModel):
    target_word: str
    meaning: str
    match_score_pct: float
    target_semitones: List[float]
    learner_semitones: List[float]
    mean_f0_hz: float
    feedback: str
    is_acceptable_tone: bool


class ToneCoachService:
    # Curated African tonal minimal pairs with gold-standard semitone curves (normalized to Mid = 0.0 ST)
    MINIMAL_PAIRS: List[TonalMinimalPair] = [
        TonalMinimalPair(
            id="oko-mid",
            base_word="oko",
            diacritized_word="ọkọ",
            tone_pattern="Mid · Mid",
            meaning="Husband",
            target_semitones=[0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
            coaching_tip="Keep both syllables flat at your Mid baseline pitch (0 ST).",
        ),
        TonalMinimalPair(
            id="oko-low",
            base_word="oko",
            diacritized_word="ọkọ̀",
            tone_pattern="Mid · Low",
            meaning="Vehicle / Car",
            target_semitones=[0.0, 0.0, -0.8, -2.2, -3.3, -3.4],
            coaching_tip="Lower your pitch by -3.4 semitones on the second syllable into your Low band.",
        ),
        TonalMinimalPair(
            id="oko-high",
            base_word="oko",
            diacritized_word="ọkọ́",
            tone_pattern="Mid · High",
            meaning="Farm Hoe / Spear",
            target_semitones=[0.0, 0.1, 0.9, 2.0, 2.8, 2.9],
            coaching_tip="Raise your pitch by +2.8 semitones on the second syllable into your High band.",
        ),
        TonalMinimalPair(
            id="akwa-cloth",
            base_word="akwa",
            diacritized_word="àkwà",
            tone_pattern="Low · Low",
            meaning="Cloth / Wrapper (Igbo)",
            target_semitones=[-3.2, -3.3, -3.2, -3.4, -3.5, -3.4],
            coaching_tip="Drop pitch immediately on the first syllable and maintain low pitch.",
        ),
        TonalMinimalPair(
            id="akwa-bed",
            base_word="akwa",
            diacritized_word="ákwà",
            tone_pattern="High · Low",
            meaning="Bed (Igbo)",
            target_semitones=[2.8, 2.9, 1.2, -1.5, -3.0, -3.2],
            coaching_tip="Start high (+2.8 ST) on the first syllable and fall sharply down to low (-3.2 ST).",
        ),
        TonalMinimalPair(
            id="akwa-egg",
            base_word="akwa",
            diacritized_word="àkwá",
            tone_pattern="Low · High",
            meaning="Egg (Igbo)",
            target_semitones=[-3.2, -3.0, -1.0, 1.2, 2.7, 2.9],
            coaching_tip="Start low (-3.2 ST) and rise decisively up to high tone (+2.9 ST).",
        ),
    ]

    @classmethod
    def get_minimal_pairs(cls) -> List[TonalMinimalPair]:
        return cls.MINIMAL_PAIRS

    @classmethod
    def hz_to_semitones(cls, frequency_hz: float, baseline_f0_hz: float) -> float:
        if frequency_hz <= 0 or baseline_f0_hz <= 0:
            return 0.0
        return 12.0 * math.log2(frequency_hz / baseline_f0_hz)

    @classmethod
    def evaluate_tone_performance(
        cls, req: ToneCalibrationRequest
    ) -> ToneCalibrationResponse:
        pair = next((p for p in cls.MINIMAL_PAIRS if p.id == req.target_word_id), None)
        if not pair:
            pair = cls.MINIMAL_PAIRS[1]  # Default to ọkọ̀ (vehicle)

        target = pair.target_semitones
        learner = req.learner_semitones

        # Pad or interpolate learner curve to match target curve length
        if len(learner) < len(target):
            learner = learner + [learner[-1] if learner else 0.0] * (len(target) - len(learner))
        elif len(learner) > len(target):
            learner = learner[:len(target)]

        # Calculate Root Mean Square Error (RMSE) in semitone space
        squared_errors = [(l - t) ** 2 for l, t in zip(learner, target)]
        rmse = math.sqrt(sum(squared_errors) / len(squared_errors))

        # Convert RMSE to accuracy percentage (RMSE of 0 ST = 100%, RMSE of 3 ST = 50%, RMSE >= 6 ST = 0%)
        match_score = max(5.0, min(99.0, 100.0 - (rmse * 16.5)))

        is_acceptable = match_score >= 80.0
        if is_acceptable:
            feedback = f"Excellent! Accurate pitch inflection for {pair.diacritized_word} ({pair.meaning})."
        else:
            feedback = f"Tonal drift detected ({rmse:.1f} ST error). {pair.coaching_tip}"

        return ToneCalibrationResponse(
            target_word=pair.diacritized_word,
            meaning=pair.meaning,
            match_score_pct=round(match_score, 1),
            target_semitones=target,
            learner_semitones=learner,
            mean_f0_hz=req.user_baseline_f0_hz,
            feedback=feedback,
            is_acceptable_tone=is_acceptable,
        )
