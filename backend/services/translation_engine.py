"""Real neural machine translation engine for ConFriKa.

Backed by Meta's open-source NLLB-200 model (No Language Left Behind), which
covers the major African languages ConFriKa targets. The model is loaded lazily
on first use and inference runs in a worker thread so the async event loop is
never blocked.

No external API keys are required; the model runs locally. The provider is
pluggable via ``settings.TRANSLATION_PROVIDER`` so a managed translation API can
be substituted later without touching callers.
"""
from __future__ import annotations

import asyncio
import logging
import math
import threading
from dataclasses import dataclass
from typing import Optional

from ..config.settings import settings

logger = logging.getLogger("confrika.translation")

# ---------------------------------------------------------------------------
# Language label -> FLORES-200 code resolution
# ---------------------------------------------------------------------------
# Keys are lowercase keywords searched for inside a free-form dialect label such
# as "Yorùbá (Ọ̀yọ́)" or "Swahili (Nairobi)". Order matters: more specific keys
# should precede broader ones.
_KEYWORD_TO_FLORES: list[tuple[str, str]] = [
    ("english", "eng_Latn"),
    ("français", "fra_Latn"),
    ("francais", "fra_Latn"),
    ("french", "fra_Latn"),
    ("português", "por_Latn"),
    ("portugues", "por_Latn"),
    ("portuguese", "por_Latn"),
    ("العربية", "arb_Arab"),
    ("arabic", "arb_Arab"),
    ("afrikaans", "afr_Latn"),
    ("yorùbá", "yor_Latn"),
    ("yoruba", "yor_Latn"),
    ("igbo", "ibo_Latn"),
    ("hausa", "hau_Latn"),
    ("fulfulde", "fuv_Latn"),
    ("fulani", "fuv_Latn"),
    ("fula", "fuv_Latn"),
    ("swahili", "swh_Latn"),
    ("kiswahili", "swh_Latn"),
    ("amharic", "amh_Ethi"),
    ("tigrinya", "tir_Ethi"),
    ("oromo", "gaz_Latn"),
    ("somali", "som_Latn"),
    ("zulu", "zul_Latn"),
    ("isizulu", "zul_Latn"),
    ("xhosa", "xho_Latn"),
    ("isixhosa", "xho_Latn"),
    ("swati", "ssw_Latn"),
    ("tswana", "tsn_Latn"),
    ("setswana", "tsn_Latn"),
    ("northern sotho", "nso_Latn"),
    ("sepedi", "nso_Latn"),
    ("sotho", "sot_Latn"),
    ("sesotho", "sot_Latn"),
    ("tsonga", "tso_Latn"),
    ("shona", "sna_Latn"),
    ("twi", "aka_Latn"),
    ("akan", "aka_Latn"),
    ("ashanti", "aka_Latn"),
    ("ewe", "ewe_Latn"),
    ("fon", "fon_Latn"),
    ("bambara", "bam_Latn"),
    ("bamanankan", "bam_Latn"),
    ("wolof", "wol_Latn"),
    ("lingala", "lin_Latn"),
    ("kongo", "kon_Latn"),
    ("kikongo", "kon_Latn"),
    ("kinyarwanda", "kin_Latn"),
    ("rwanda", "kin_Latn"),
    ("kirundi", "run_Latn"),
    ("rundi", "run_Latn"),
    ("luganda", "lug_Latn"),
    ("ganda", "lug_Latn"),
    ("kikuyu", "kik_Latn"),
    ("gikuyu", "kik_Latn"),
    ("kamba", "kam_Latn"),
    ("luo", "luo_Latn"),
    ("chichewa", "nya_Latn"),
    ("nyanja", "nya_Latn"),
    ("bemba", "bem_Latn"),
    ("umbundu", "umb_Latn"),
    ("kabyle", "kab_Latn"),
    ("tamazight", "kab_Latn"),
    # ----- Extended NLLB-200 African coverage (proper language models) -----
    ("dioula", "dyu_Latn"),
    ("dyula", "dyu_Latn"),
    ("jula", "dyu_Latn"),
    ("kabuverdianu", "kea_Latn"),
    ("cape verdean", "kea_Latn"),
    ("crioulo", "kea_Latn"),
    ("kriolu", "kea_Latn"),
    ("kimbundu", "kmb_Latn"),
    ("mooré", "mos_Latn"),
    ("moore", "mos_Latn"),
    ("mossi", "mos_Latn"),
    ("sango", "sag_Latn"),
    ("tamasheq", "taq_Latn"),
    ("tamajaq", "taq_Latn"),
    ("tuareg", "taq_Latn"),
    ("tshiluba", "lua_Latn"),
    ("ciluba", "lua_Latn"),
    ("luba", "lua_Latn"),
    ("kanuri", "knc_Latn"),
    ("kanembu", "knc_Latn"),
    ("dinka", "dik_Latn"),
    ("nuer", "nus_Latn"),
    ("tumbuka", "tum_Latn"),
    ("kabiyè", "kbp_Latn"),
    ("kabiye", "kbp_Latn"),
    ("malagasy", "plt_Latn"),
    ("merina", "plt_Latn"),
    ("kituba", "kon_Latn"),
    ("kutuba", "kon_Latn"),
    # ----- Regional Arabic varieties -----
    ("darija", "ary_Arab"),
    ("moroccan", "ary_Arab"),
    ("algerian", "ary_Arab"),
    ("egyptian", "arz_Arab"),
    ("masri", "arz_Arab"),
    ("tunisian", "aeb_Arab"),
    # ----- Best-effort fallbacks: NLLB-200 has no dedicated model for these
    # local dialects, so we route them to the closest regional language the
    # model DOES support (better than an "unavailable" error). -----
    ("bamiléké", "fra_Latn"),
    ("bamileke", "fra_Latn"),
    ("duala", "fra_Latn"),
    ("ewondo", "fra_Latn"),
    ("bulu", "fra_Latn"),
    ("basaa", "fra_Latn"),
    ("banda", "sag_Latn"),
    ("gbaya", "sag_Latn"),
    ("sara", "fra_Latn"),
    ("teke", "lin_Latn"),
    ("bariba", "fra_Latn"),
    ("dendi", "fra_Latn"),
    ("chokwe", "umb_Latn"),
    ("kalanga", "sna_Latn"),
    ("shekgalagari", "tsn_Latn"),
    ("shikomori", "swh_Latn"),
    ("shindzuani", "swh_Latn"),
    ("shimwali", "swh_Latn"),
    ("comorian", "swh_Latn"),
    ("nigerian pidgin", "eng_Latn"),
    ("pidgin", "eng_Latn"),
]

DEFAULT_FLORES = "eng_Latn"


def resolve_flores_code(label: Optional[str]) -> str:
    """Map a free-form dialect/language label to a FLORES-200 code.

    Falls back to English when no known language keyword is found.
    """
    if not label:
        return DEFAULT_FLORES
    low = label.strip().lower()
    for keyword, code in _KEYWORD_TO_FLORES:
        if keyword in low:
            return code
    return DEFAULT_FLORES


@dataclass
class EngineResult:
    translated_text: str
    source_code: str
    target_code: str
    confidence: float  # [0, 1], derived from the model's own token scores
    model: str


class _NLLBEngine:
    """Lazy, thread-safe wrapper around an NLLB-200 seq2seq model."""

    def __init__(self) -> None:
        self._tokenizer = None
        self._model = None
        self._torch = None
        self._lock = threading.Lock()
        self._ready = False

    @property
    def is_ready(self) -> bool:
        return self._ready

    def _ensure_loaded(self) -> None:
        if self._ready:
            return
        with self._lock:
            if self._ready:
                return
            logger.info("Loading NLLB translation model: %s", settings.NLLB_MODEL)
            import torch  # noqa: WPS433 (heavy, intentionally lazy)
            from transformers import AutoModelForSeq2SeqLM, AutoTokenizer

            cache_dir = settings.MODEL_CACHE_DIR or None
            self._tokenizer = AutoTokenizer.from_pretrained(
                settings.NLLB_MODEL, cache_dir=cache_dir
            )
            self._model = AutoModelForSeq2SeqLM.from_pretrained(
                settings.NLLB_MODEL, cache_dir=cache_dir
            )
            device = settings.NLLB_DEVICE if (settings.NLLB_DEVICE == "cuda" and torch.cuda.is_available()) else "cpu"
            self._model.to(device)
            self._model.eval()
            self._torch = torch
            self._device = device
            self._ready = True
            logger.info("NLLB model loaded on device=%s", device)

    def translate(self, text: str, src_code: str, tgt_code: str) -> EngineResult:
        self._ensure_loaded()
        torch = self._torch
        tokenizer = self._tokenizer
        model = self._model

        tokenizer.src_lang = src_code
        inputs = tokenizer(
            text,
            return_tensors="pt",
            truncation=True,
            max_length=settings.NLLB_MAX_INPUT_TOKENS,
        ).to(self._device)

        bos_id = tokenizer.convert_tokens_to_ids(tgt_code)
        with torch.no_grad():
            generated = model.generate(
                **inputs,
                forced_bos_token_id=bos_id,
                max_length=settings.NLLB_MAX_INPUT_TOKENS,
                num_beams=4,
                output_scores=True,
                return_dict_in_generate=True,
            )

        sequences = generated.sequences
        translated = tokenizer.batch_decode(sequences, skip_special_tokens=True)[0].strip()

        confidence = 0.0
        try:
            transition = model.compute_transition_scores(
                sequences, generated.scores, generated.beam_indices, normalize_logits=True
            )
            # transition log-probs -> mean prob across generated tokens.
            valid = transition[0][torch.isfinite(transition[0])]
            if valid.numel() > 0:
                confidence = float(torch.exp(valid.mean()).clamp(0.0, 1.0))
        except Exception:  # scoring is best-effort; translation still returned
            confidence = 0.0

        return EngineResult(
            translated_text=translated,
            source_code=src_code,
            target_code=tgt_code,
            confidence=round(confidence, 4),
            model=settings.NLLB_MODEL,
        )


_engine: Optional[_NLLBEngine] = None
_engine_init_lock = threading.Lock()


def _get_engine() -> _NLLBEngine:
    global _engine
    if _engine is None:
        with _engine_init_lock:
            if _engine is None:
                _engine = _NLLBEngine()
    return _engine


def engine_ready() -> bool:
    return _engine is not None and _engine.is_ready


async def warmup() -> None:
    """Pre-load the model so the first user request is fast."""
    if settings.TRANSLATION_PROVIDER != "nllb":
        return
    try:
        await asyncio.to_thread(_get_engine()._ensure_loaded)
    except Exception as exc:  # pragma: no cover - warmup is best effort
        logger.warning("Translation warmup failed (will retry on demand): %s", exc)


async def translate(text: str, source_label: str, target_label: str) -> EngineResult:
    """Translate ``text`` from ``source_label`` to ``target_label``.

    Labels are free-form language/dialect names; they are resolved to FLORES-200
    codes internally.
    """
    src_code = resolve_flores_code(source_label)
    tgt_code = resolve_flores_code(target_label)

    stripped = (text or "").strip()
    if not stripped:
        return EngineResult("", src_code, tgt_code, 0.0, "none")

    if src_code == tgt_code:
        # Same language: nothing to translate.
        return EngineResult(stripped, src_code, tgt_code, 1.0, "identity")

    provider = settings.TRANSLATION_PROVIDER
    if provider == "echo":
        # Development-only passthrough. Never enabled in production.
        return EngineResult(stripped, src_code, tgt_code, 0.0, "echo")

    engine = _get_engine()
    return await asyncio.to_thread(engine.translate, stripped, src_code, tgt_code)
