import asyncio
import io
import math
import struct
import wave

import pytest

try:
    from backend.config.settings import settings
    from backend.services.auth_service import (
        SignUpRequest,
        hash_password,
        verify_password,
        normalize_username,
    )
    from backend.services import translation_engine
    from backend.services import google_translate_provider
    from backend.services.speech_translation_service import (
        SpeechTranslationService,
        TranslationRequest,
    )
    from backend.services.tone_coach_service import (
        ToneCoachService,
        ToneCalibrationRequest,
    )
    from backend.services.pitch_service import PitchService
    from backend.services.contact_service import country_flag
except ImportError:  # allow running from inside backend/
    from config.settings import settings
    from services.auth_service import (
        SignUpRequest,
        hash_password,
        verify_password,
        normalize_username,
    )
    from services import translation_engine
    from services import google_translate_provider
    from services.speech_translation_service import (
        SpeechTranslationService,
        TranslationRequest,
    )
    from services.tone_coach_service import ToneCoachService, ToneCalibrationRequest
    from services.pitch_service import PitchService
    from services.contact_service import country_flag


# --------------------------------------------------------------------------- #
# Auth validation & password security
# --------------------------------------------------------------------------- #
def test_signup_validation_success():
    req = SignUpRequest(
        email="Jane.Doe@gmail.com",
        password="StrongPass123",
        full_name="Jane Doe",
        username="jane_doe",
        country_code="ng",
        origin_region="Anambra",
        primary_dialect="Igbo (Onitsha)",
    )
    assert req.email == "jane.doe@gmail.com"        # normalized lowercase
    assert req.username == "@jane_doe"              # normalized @handle
    assert req.country_code == "NG"                 # normalized uppercase


def test_signup_rejects_invalid_email():
    with pytest.raises(ValueError):
        SignUpRequest(
            email="not-an-email",
            password="StrongPass123",
            full_name="Test User",
            username="test_user",
            country_code="NG",
            origin_region="Lagos",
            primary_dialect="Yoruba",
        )


def test_signup_rejects_short_password():
    with pytest.raises(ValueError):
        SignUpRequest(
            email="x@gmail.com",
            password="short",
            full_name="Test User",
            username="test_user",
            country_code="NG",
            origin_region="Lagos",
            primary_dialect="Yoruba",
        )


def test_signup_rejects_invalid_country():
    with pytest.raises(ValueError):
        SignUpRequest(
            email="x@gmail.com",
            password="StrongPass123",
            full_name="Test User",
            username="test_user",
            country_code="ZZ",
            origin_region="Nowhere",
            primary_dialect="Yoruba",
        )


def test_change_password_requires_otp_code():
    try:
        from backend.services.auth_service import ChangePasswordRequest
    except ImportError:
        from services.auth_service import ChangePasswordRequest

    # A valid change request must carry the emailed OTP code.
    req = ChangePasswordRequest(
        current_password="OldPass123",
        new_password="NewPass123",
        code="123456",
    )
    assert req.code == "123456"

    # Omitting the code is rejected — change-password is now OTP-gated.
    with pytest.raises(ValueError):
        ChangePasswordRequest(current_password="OldPass123", new_password="NewPass123")
    # A weak new password is still rejected.
    with pytest.raises(ValueError):
        ChangePasswordRequest(
            current_password="OldPass123", new_password="weak", code="123456"
        )


def test_privacy_request_validation():
    try:
        from backend.services.auth_service import UpdatePrivacyRequest
    except ImportError:
        from services.auth_service import UpdatePrivacyRequest

    ok = UpdatePrivacyRequest(calls_privacy="Contacts", messages_privacy="NOBODY",
                              allow_images=False)
    assert ok.calls_privacy == "contacts"       # normalized lowercase
    assert ok.messages_privacy == "nobody"
    assert ok.allow_images is False
    # Invalid reachability value is rejected.
    with pytest.raises(ValueError):
        UpdatePrivacyRequest(calls_privacy="friends-only")


def test_password_hash_roundtrip():
    h = hash_password("StrongPass123")
    assert h != "StrongPass123"
    assert verify_password("StrongPass123", h) is True
    assert verify_password("wrong", h) is False
    assert verify_password("anything", None) is False


def test_normalize_username():
    assert normalize_username("Chioma") == "@chioma"
    assert normalize_username("@Ade") == "@ade"


# --------------------------------------------------------------------------- #
# Translation engine (code resolution + echo/identity paths, no model needed)
# --------------------------------------------------------------------------- #
def test_flores_code_resolution():
    assert translation_engine.resolve_flores_code("Yorùbá (Ọ̀yọ́)") == "yor_Latn"
    assert translation_engine.resolve_flores_code("Igbo (Onitsha)") == "ibo_Latn"
    assert translation_engine.resolve_flores_code("Swahili (Nairobi)") == "swh_Latn"
    assert translation_engine.resolve_flores_code("Amharic") == "amh_Ethi"
    assert translation_engine.resolve_flores_code("English") == "eng_Latn"
    assert translation_engine.resolve_flores_code("Totally Unknown") == "eng_Latn"


def test_identity_translation_same_language():
    res = asyncio.run(translation_engine.translate("Hello", "English", "English"))
    assert res.translated_text == "Hello"
    assert res.model == "identity"


def test_echo_provider_passthrough(monkeypatch):
    monkeypatch.setattr(settings, "TRANSLATION_PROVIDER", "echo")
    res = asyncio.run(
        SpeechTranslationService.translate_text(
            TranslationRequest(text="Ẹ káàsán", source_dialect="Yorùbá", target_dialect="English")
        )
    )
    assert res.original_text == "Ẹ káàsán"
    assert res.source_code == "yor_Latn"
    assert res.target_code == "eng_Latn"
    assert len(res.detected_diacritics) > 0


# --------------------------------------------------------------------------- #
# Translation router: NLLB vs managed provider (Google) selection
# --------------------------------------------------------------------------- #
def test_language_resolution_nllb_vs_gap():
    # NLLB-native language: has a real FLORES code, no provider needed.
    yor = translation_engine._resolve_language("Yoruba")
    assert yor.flores == "yor_Latn" and yor.nllb_native is True
    # Gap language NLLB lacks: English placeholder FLORES but a provider code.
    tiv = translation_engine._resolve_language("Tiv")
    assert tiv.flores == "eng_Latn" and tiv.nllb_native is False and tiv.google == "tiv"


def test_router_prefers_google_for_gap_language(monkeypatch):
    """A language NLLB cannot do is routed to the managed provider; a native
    language stays on NLLB; an unsupported gap language degrades to NLLB."""
    monkeypatch.setattr(settings, "TRANSLATION_PROVIDER", "nllb")
    monkeypatch.setattr(settings, "GOOGLE_TRANSLATE_API_KEY", "TEST_KEY")

    class _FakeEngine:
        def translate(self, text, src, tgt):
            return translation_engine.EngineResult("<nllb>", src, tgt, 0.5, "fake-nllb")

    class _FakeGoogle:
        model_name = "google-translate-v2"

        async def supports(self, *codes):
            return set(codes) <= {"en", "tiv", "yo"}

        async def translate(self, text, s, t):
            return "<google>"

    monkeypatch.setattr(translation_engine, "_engine", _FakeEngine())
    monkeypatch.setattr(google_translate_provider, "get_provider", lambda: _FakeGoogle())
    monkeypatch.setattr(google_translate_provider, "is_configured", lambda: True)

    native = asyncio.run(translation_engine.translate("Hi", "English", "Yoruba"))
    assert native.model == "fake-nllb"  # NLLB handles what it supports

    gap = asyncio.run(translation_engine.translate("Hi", "English", "Tiv"))
    assert gap.model == "google-translate-v2"  # Tiv routed to Google

    uncovered = asyncio.run(translation_engine.translate("Hi", "English", "Efik"))
    assert uncovered.model == "fake-nllb"  # Efik unsupported by provider -> NLLB


# --------------------------------------------------------------------------- #
# Tone coach (real semitone math)
# --------------------------------------------------------------------------- #
def test_tone_coach_semitone_calculation():
    assert abs(ToneCoachService.hz_to_semitones(138.0, 138.0)) < 0.001
    assert abs(ToneCoachService.hz_to_semitones(276.0, 138.0) - 12.0) < 0.001


def test_tone_calibration_minimal_pair_matching():
    res = ToneCoachService.evaluate_tone_performance(
        ToneCalibrationRequest(
            user_baseline_f0_hz=138.0,
            target_word_id="oko-low",
            learner_semitones=[0.0, 0.0, -0.8, -2.2, -3.3, -3.4],
        )
    )
    assert res.match_score_pct >= 95.0
    assert res.is_acceptable_tone is True
    assert "ọkọ̀" in res.target_word


# --------------------------------------------------------------------------- #
# Pitch analysis (real DSP on a synthetic tone)
# --------------------------------------------------------------------------- #
def _sine_wav(freq: float, sr: int = 16000, seconds: float = 0.5) -> bytes:
    n = int(sr * seconds)
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        frames = bytearray()
        for i in range(n):
            val = int(0.6 * 32767 * math.sin(2 * math.pi * freq * i / sr))
            frames += struct.pack("<h", val)
        w.writeframes(bytes(frames))
    return buf.getvalue()


def test_pitch_detection_on_pure_tone():
    wav = _sine_wav(150.0)
    result = PitchService.analyze_wav(wav, baseline_f0_hz=150.0)
    # Autocorrelation should recover ~150 Hz within a tolerance.
    assert abs(result.mean_f0_hz - 150.0) < 8.0
    assert result.voiced_ratio > 0.8
    # At baseline == detected pitch, semitone contour sits near 0.
    assert abs(sum(result.semitone_contour) / len(result.semitone_contour)) < 1.0


def test_country_flag_emoji():
    assert country_flag("NG") == "🇳🇬"
    assert country_flag("KE") == "🇰🇪"
    assert country_flag(None) == "🌍"


# --------------------------------------------------------------------------- #
# Learning stats — real streak math (no fabricated numbers)
# --------------------------------------------------------------------------- #
def test_streak_days_logic():
    from datetime import date, timedelta

    try:
        from backend.services.learning_stats_service import _streak_days
    except ImportError:
        from services.learning_stats_service import _streak_days

    today = date.today()
    # No activity -> no streak.
    assert _streak_days([]) == 0
    # Three consecutive days ending today -> streak of 3 (duplicates ignored).
    assert _streak_days(
        [today, today, today - timedelta(days=1), today - timedelta(days=2)]
    ) == 3
    # Most recent activity was yesterday -> streak still alive.
    assert _streak_days([today - timedelta(days=1), today - timedelta(days=2)]) == 2
    # A two-day gap -> streak has lapsed to 0.
    assert _streak_days([today - timedelta(days=3)]) == 0
    # A break in the middle -> only the recent run counts.
    assert _streak_days(
        [today, today - timedelta(days=1), today - timedelta(days=5)]
    ) == 2
