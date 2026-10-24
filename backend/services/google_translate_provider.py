"""Managed translation provider: Google Cloud Translation API (v2).

This is a *fallback* provider used by the translation router for languages that
the local NLLB-200 model does not cover well (e.g. Tiv), while NLLB keeps
handling everything it supports for free. It uses the simple API-key auth of the
v2 REST endpoint, so the only configuration needed is ``GOOGLE_TRANSLATE_API_KEY``
in the environment.

Design notes:
- All failures are soft: the router treats any exception here as "provider
  unavailable" and falls back to NLLB. A wrong language code therefore degrades
  gracefully instead of breaking a translation.
- The set of codes Google actually supports is fetched once and cached, so we
  never spend an API call (or return a confusing error) on a code Google does
  not know.
"""
from __future__ import annotations

import asyncio
import logging
from typing import Optional, Set

import httpx

from ..config.settings import settings

logger = logging.getLogger("confrika.translation.google")

_BASE = "https://translation.googleapis.com/language/translate/v2"
_TIMEOUT = httpx.Timeout(10.0, connect=5.0)

# Managed providers do not expose per-token scores; report a fixed, honest
# "high but not perfect" confidence so callers have a sensible number.
_PROVIDER_CONFIDENCE = 0.9


def is_configured() -> bool:
    """True when a Google Translate API key is present."""
    return bool((settings.GOOGLE_TRANSLATE_API_KEY or "").strip())


class GoogleTranslateProvider:
    """Thin async client around the Google Cloud Translation v2 REST API."""

    def __init__(self) -> None:
        self._supported: Optional[Set[str]] = None
        self._supported_lock = asyncio.Lock()

    @property
    def model_name(self) -> str:
        return "google-translate-v2"

    async def _api_key(self) -> str:
        key = (settings.GOOGLE_TRANSLATE_API_KEY or "").strip()
        if not key:
            raise RuntimeError("GOOGLE_TRANSLATE_API_KEY is not configured")
        return key

    async def supported_codes(self) -> Set[str]:
        """Return the set of language codes Google supports (cached).

        Best-effort: on any failure we return an empty set, which makes
        ``supports`` fall back to trusting the caller's code map.
        """
        if self._supported is not None:
            return self._supported
        async with self._supported_lock:
            if self._supported is not None:
                return self._supported
            try:
                key = await self._api_key()
                async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
                    resp = await client.get(
                        f"{_BASE}/languages", params={"key": key}
                    )
                resp.raise_for_status()
                langs = resp.json().get("data", {}).get("languages", [])
                self._supported = {
                    (item.get("language") or "").lower() for item in langs if item.get("language")
                }
                logger.info(
                    "Google Translate supports %d languages", len(self._supported)
                )
            except Exception as exc:  # pragma: no cover - network best-effort
                logger.warning("Could not fetch Google language list: %s", exc)
                self._supported = set()
            return self._supported

    async def supports(self, *codes: str) -> bool:
        """True if every given code is known to be supported.

        If the supported-language list could not be fetched (empty set), we
        optimistically return True and let the translate call decide.
        """
        known = await self.supported_codes()
        if not known:
            return True
        return all((c or "").lower() in known for c in codes)

    async def translate(self, text: str, source_code: str, target_code: str) -> str:
        """Translate ``text`` from ``source_code`` to ``target_code``.

        Codes are Google Translate language codes (e.g. ``en``, ``yo``, ``tiv``).
        Raises on any API error; the router catches and falls back to NLLB.
        """
        key = await self._api_key()
        payload = {
            "q": text,
            "source": source_code,
            "target": target_code,
            "format": "text",
            "key": key,
        }
        async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
            resp = await client.post(_BASE, data=payload)
        resp.raise_for_status()
        translations = resp.json().get("data", {}).get("translations", [])
        if not translations:
            raise RuntimeError("Google Translate returned no translation")
        translated = (translations[0].get("translatedText") or "").strip()
        if not translated:
            raise RuntimeError("Google Translate returned an empty translation")
        return translated


_provider: Optional[GoogleTranslateProvider] = None


def get_provider() -> GoogleTranslateProvider:
    global _provider
    if _provider is None:
        _provider = GoogleTranslateProvider()
    return _provider


PROVIDER_CONFIDENCE = _PROVIDER_CONFIDENCE
