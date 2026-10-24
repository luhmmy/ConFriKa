"""Live in-call speech-to-speech translation (voice-preserving).

Pipeline per utterance:  caller audio ─▶ STT ─▶ NLLB translate ─▶ voice-clone TTS
                          (so the listener hears the translation in the caller's
                          own voice, ~1.5–3s behind — the unavoidable latency of
                          waiting for a full phrase before it can be re-spoken).

Provider calls use only the standard library (urllib), matching email_service,
so no new dependency is added. When VOICE_API_KEY is empty the service runs in
STUB mode: it still translates text (via NLLB) but returns no synthesized audio,
so the rest of the app can be wired and tested before the key lands.
"""
from __future__ import annotations

import asyncio
import json
import logging
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Optional

from ..config.settings import settings
from .speech_translation_service import SpeechTranslationService, TranslationRequest

logger = logging.getLogger("confrika.voice")

_ELEVEN_BASE = "https://api.elevenlabs.io/v1"
_TIMEOUT = 30


@dataclass
class TranslatedUtterance:
    source_text: str
    translated_text: str
    audio_b64: Optional[str]  # base64 TTS audio in the speaker's voice, or None (stub)
    provider: str


def _http(method: str, url: str, *, headers: dict, data: Optional[bytes] = None):
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=_TIMEOUT) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()
    except Exception as e:  # network/DNS/timeout
        return 0, str(e).encode()


class VoiceService:
    """Voice-preserving speech-to-speech translation for live calls."""

    # ── Speech-to-text ────────────────────────────────────────────────────
    @staticmethod
    def _stt_sync(audio: bytes) -> str:
        key = settings.VOICE_API_KEY.strip()
        boundary = "----confrikaSTT"
        parts = [
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"model_id\"\r\n\r\n{settings.VOICE_STT_MODEL}\r\n",
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n"
            "Content-Type: audio/wav\r\n\r\n",
        ]
        body = parts[0].encode() + parts[1].encode() + audio + f"\r\n--{boundary}--\r\n".encode()
        status, raw = _http(
            "POST",
            f"{_ELEVEN_BASE}/speech-to-text",
            headers={"xi-api-key": key, "Content-Type": f"multipart/form-data; boundary={boundary}"},
            data=body,
        )
        if 200 <= status < 300:
            try:
                return json.loads(raw).get("text", "")
            except Exception:
                return ""
        logger.error("STT failed (%s): %s", status, raw[:200])
        return ""

    # ── Text-to-speech in a given (cloned) voice ──────────────────────────
    @staticmethod
    def _tts_sync(text: str, voice_id: str) -> Optional[bytes]:
        key = settings.VOICE_API_KEY.strip()
        status, raw = _http(
            "POST",
            f"{_ELEVEN_BASE}/text-to-speech/{voice_id}?output_format=mp3_44100_128",
            headers={"xi-api-key": key, "Content-Type": "application/json"},
            data=json.dumps({"text": text, "model_id": settings.VOICE_TTS_MODEL}).encode(),
        )
        if 200 <= status < 300:
            return raw
        logger.error("TTS failed (%s): %s", status, raw[:200])
        return None

    # ── Instant voice cloning (enrollment) ────────────────────────────────
    @staticmethod
    def _create_clone_sync(name: str, audio: bytes) -> Optional[str]:
        key = settings.VOICE_API_KEY.strip()
        boundary = "----confrikaClone"
        pre = (
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"name\"\r\n\r\n{name}\r\n"
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"files\"; "
            "filename=\"enroll.wav\"\r\nContent-Type: audio/wav\r\n\r\n"
        )
        body = pre.encode() + audio + f"\r\n--{boundary}--\r\n".encode()
        status_code, raw = _http(
            "POST",
            f"{_ELEVEN_BASE}/voices/add",
            headers={"xi-api-key": key, "Content-Type": f"multipart/form-data; boundary={boundary}"},
            data=body,
        )
        if 200 <= status_code < 300:
            try:
                return json.loads(raw).get("voice_id")
            except Exception:
                return None
        logger.error("Voice clone failed (%s): %s", status_code, raw[:200])
        return None

    @classmethod
    async def create_voice_clone(cls, name: str, audio: bytes) -> Optional[str]:
        if not settings.voice_configured:
            return None
        return await asyncio.to_thread(cls._create_clone_sync, name, audio)

    # ── High-level: one utterance, translated and re-spoken ───────────────
    @classmethod
    async def translate_utterance(
        cls,
        *,
        audio: bytes,
        source_dialect: str,
        target_dialect: str,
        voice_id: Optional[str],
    ) -> TranslatedUtterance:
        """STT → NLLB → (clone TTS). In stub mode, audio_b64 is None."""
        import base64

        if not settings.voice_configured:
            # Stub: no live audio, but still exercise translation end-to-end.
            source_text = "[voice service not configured]"
            translated = await cls._translate(source_text, source_dialect, target_dialect)
            return TranslatedUtterance(source_text, translated, None, "stub")

        source_text = await asyncio.to_thread(cls._stt_sync, audio)
        translated = await cls._translate(source_text, source_dialect, target_dialect)
        audio_b64 = None
        if voice_id and translated:
            tts = await asyncio.to_thread(cls._tts_sync, translated, voice_id)
            if tts:
                audio_b64 = base64.b64encode(tts).decode()
        return TranslatedUtterance(
            source_text, translated, audio_b64, settings.VOICE_PROVIDER or "cloud"
        )

    @staticmethod
    async def _translate(text: str, source: str, target: str) -> str:
        if not text or source.strip().lower() == target.strip().lower():
            return text
        res = await SpeechTranslationService.translate_text(
            TranslationRequest(text=text, source_dialect=source, target_dialect=target)
        )
        return res.translated_text or text
