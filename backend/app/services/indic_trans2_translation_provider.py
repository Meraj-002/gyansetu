"""Real machine-translation provider: IndicTrans2 through ONNX Runtime.

Implements the exact [TranslationProvider] seam so the router, schema and the
on-device cache path do not change. IndicTrans2 supports the 22 scheduled Indic
languages including Santali (`sat_Olck`), so the Hindi ↔ Santali pair this
project cares about is native to the model.

Production behaviours encoded here:

- **Lazy load.** Nothing is imported from the model runtime and no checkpoint
  is downloaded at application import or startup. The model loads only on the
  first translate request, so a server that never sees the provider stays
  cheap and a gated/missing model cannot take the app down at boot.
- **One copy, reused.** A process-wide cache keyed by ``(model_id, token)``
  guarantees a single loaded checkpoint, shared across every provider instance
  and every request. Concurrent first-requests race on the same lock and only
  one wins the load.
- **No fabrication.** If the model cannot load (deps missing, gated, offline)
  or a sentence produces nothing, the provider raises [ModelUnavailableError]
  and the endpoint returns an explicit ``model_unavailable`` state. It never
  invents a translation and never falls back to the dev phrasebook.
- **No fake confidence.** IndicTrans2 emits no calibrated probability; the
  provider reports ``confidence=None`` and never invents a number.
- **Speaker review.** Model output is never "speaker verified",
  ``reviewed_by_speaker=False``.
- **Ol Chiki audio safety.** The model outputs Ol Chiki, which no device TTS
  can read; ``spoken_text=None`` so the audio layer is never handed a script it
  would mispronounce.
- **Diagnostics.** ``diagnostics`` reports dependency availability and (once
  load is attempted) timings and any load error, for honest operator visibility.

The IndicTrans2 recipe is followed exactly: build the IndicProcessor in
inference mode, ``preprocess_batch(…, src_lang=…, tgt_lang=…)`` before
tokenising, ``model.generate`` under ``torch.no_grad``, decode, then
``postprocess_batch(…, lang=<target>)``. The default checkpoint is an INT8
ONNX export of the IndicTrans2 checkpoint, executed by ONNX Runtime on CPU.
"""

from __future__ import annotations

import logging
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

from app.core.exceptions import not_found
from app.schemas.translation import TranslateRequest, TranslateResponse
from app.services.translation_provider import TranslationProvider

logger = logging.getLogger("gyansetu.translation.indic_trans2")

MODEL_ID = "TigreGotico/indictrans2-indic-indic-dist-320M-onnx"
MODEL_VERSION = "indictrans2-indic-indic-dist-320M-onnx-int8"
_ONNX_SUBFOLDER = "int8"
PROVIDER_NAME = "indic_trans2"

# Canonical GyanSetu codes -> IndicTrans2 codes. The classroom pair this project
# cares about is wired in both directions; the map is a fold, not a replacement.
_INDICTRANS2_CODES = {
    "hindi": "hin_Deva",
    "santali": "sat_Olck",
}

_GATE_MESSAGE = (
    "IndicTrans2 checkpoint {model_id!r} is gated or not signed in. Accept the "
    "model's access terms on its Hugging Face page and provide a token "
    "(HF_TOKEN in backend/.env) so the model can be downloaded. This provider "
    "refuses to run without the real model."
)

_REQUIREMENTS_MESSAGE = (
    "IndicTrans2 provider needs: torch, transformers, optimum, onnxruntime and "
    "IndicTransToolkit (pip install torch transformers optimum onnxruntime "
    "IndicTransToolkit). They are not installed, so the real model cannot load."
)


class ModelUnavailableError(RuntimeError):
    """Raised when the real model cannot be produced for a translation request.

    Carries a stable machine-readable ``code`` so the HTTP layer can respond
    ``model_unavailable`` rather than inventing a translation or crashing.
    """

    def __init__(self, code: str, reason: str, detail: str) -> None:
        self.code = code
        self.reason = reason
        self.detail = detail
        super().__init__(detail or reason)


@dataclass(frozen=True)
class LoadDiagnostics:
    attempted: bool = False
    elapsed_ms: float | None = None
    error_code: str | None = None
    error_detail: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "attempted": self.attempted,
            "elapsed_ms": self.elapsed_ms,
            "error_code": self.error_code,
            "error_detail": self.error_detail,
        }


# A process-wide cache so the 320M checkpoint is ever loaded once, no matter how
# many provider instances or requests the process handles.
_MODEL_CACHE: dict[tuple[str, str | None], tuple[Any, Any, Any]] = {}
_MODEL_CACHE_LOCK = threading.Lock()
_MODEL_DIAGNOSTICS: dict[tuple[str, str | None], LoadDiagnostics] = {}


def _check_dependencies() -> None:
    """Import and touch the heavy modules, raising RuntimeError if any are shy.
    Imported here (inside the lazy path) so nothing is pulled at app startup."""
    try:
        import torch  # noqa: F401
        import onnxruntime  # noqa: F401
        from optimum.onnxruntime import ORTModelForSeq2SeqLM  # noqa: F401
        from transformers import AutoModelForSeq2SeqLM, AutoTokenizer
        from IndicTransToolkit.processor import IndicProcessor
    except ImportError as error:  # pragma: no cover - exercised live, not unit
        raise RuntimeError(_REQUIREMENTS_MESSAGE) from error


class IndicTrans2TranslationProvider(TranslationProvider):
    """One IndicTrans2 checkpoint behind the standard provider seam.

    Construction is cheap and never touches the network or torch. The model is
    loaded on first use and cached process-wide, so multiple instances share a
    single loaded checkpoint and requests reuse it.

    Tests inject a ``loader`` (returning the ``(tokenizer, model, processor)``
    triple) so the full stack is exercisable without downloading / without
    torch; a ``cache`` may be injected to isolate the unit tests from the real
    process-wide cache.
    """

    def __init__(
        self,
        model_id: str | None = None,
        token: str | None = None,
        loader: Callable[[str, str | None], tuple[Any, Any, Any]] | None = None,
        cache: dict[tuple[str, str | None], tuple[Any, Any, Any]] | None = None,
        diagnostics: dict[tuple[str, str | None], LoadDiagnostics] | None = None,
    ) -> None:
        self._model_id = model_id or MODEL_ID
        self._token = token
        self._loader = loader or self._default_loader
        self._cache = cache if cache is not None else _MODEL_CACHE
        self._diagnostics = diagnostics if diagnostics is not None else _MODEL_DIAGNOSTICS
        self._key = (self._model_id, self._token)

    @property
    def source(self) -> str:
        return self._model_id

    @property
    def provider(self) -> str:
        return PROVIDER_NAME

    @property
    def model_id(self) -> str:
        return self._model_id

    @property
    def model_version(self) -> str:
        # Part of the on-device cache key. Different from "dev-rules-1", so a
        # cached dev answer is never served as a model answer.
        return MODEL_VERSION if self._model_id == MODEL_ID else self._model_id

    @property
    def reviewed_by_speaker(self) -> bool:
        return False

    @property
    def is_real_model(self) -> bool:
        # True only once the real checkpoint is actually loaded and answerable.
        return self._key in self._cache

    @property
    def loaded(self) -> bool:
        return self._key in self._cache

    @property
    def diagnostics(self) -> dict[str, Any]:
        current = self._diagnostics.get(self._key)
        return (
            current.to_dict()
            if current
            else {"attempted": False, "elapsed_ms": None, "error_code": None, "error_detail": None}
        )

    # -- Loading -------------------------------------------------------------

    def _ensure_loaded(self) -> tuple[Any, Any, Any]:
        existing = self._cache.get(self._key)
        if existing is not None:
            return existing

        with _MODEL_CACHE_LOCK:
            existing = self._cache.get(self._key)
            if existing is not None:
                return existing

            started = time.perf_counter()
            try:
                components = self._loader(self._model_id, self._token)
            except RuntimeError as error:
                self._diagnostics[self._key] = LoadDiagnostics(
                    attempted=True,
                    elapsed_ms=(time.perf_counter() - started) * 1000.0,
                    error_code="model_unavailable",
                    error_detail=str(error),
                )
                logger.error("IndicTrans2 load failed: %s", error)
                raise ModelUnavailableError(
                    "model_unavailable", "model could not be loaded", str(error)
                ) from error
            except Exception as error:
                self._diagnostics[self._key] = LoadDiagnostics(
                    attempted=True,
                    elapsed_ms=(time.perf_counter() - started) * 1000.0,
                    error_code="model_unavailable",
                    error_detail=str(error),
                )
                logger.error("IndicTrans2 load failed: %s", error)
                raise ModelUnavailableError(
                    "model_unavailable", "model could not be loaded", str(error)
                ) from error

            self._cache[self._key] = components
            self._diagnostics[self._key] = LoadDiagnostics(
                attempted=True, elapsed_ms=(time.perf_counter() - started) * 1000.0
            )
            logger.info(
                "IndicTrans2 loaded %s in %.0f ms", self._model_id, self.diagnostics["elapsed_ms"]
            )
            return components

    def _default_loader(
        self, model_id: str, token: str | None
    ) -> tuple[Any, Any, Any]:
        _check_dependencies()
        from transformers import AutoConfig, AutoModelForSeq2SeqLM, AutoTokenizer
        from IndicTransToolkit.processor import IndicProcessor

        kwargs: dict[str, Any] = {"trust_remote_code": True}
        if token:
            kwargs["token"] = token

        if _is_onnx_model(model_id):
            from optimum.onnxruntime import ORTModelForSeq2SeqLM

            model_source = model_id
            model_subfolder = _ONNX_SUBFOLDER
            local_path = Path(model_id)
            if local_path.is_dir() and (
                (local_path / "encoder_model.onnx").exists()
                or local_path.name.lower() == _ONNX_SUBFOLDER
            ):
                # Accept either the repository root or a directly supplied
                # local int8/ directory for offline deployments.
                if local_path.name.lower() == _ONNX_SUBFOLDER:
                    model_source = str(local_path.parent)
                else:
                    model_source = str(local_path)
                model_subfolder = ""

            # The export keeps model config/code at the repository root while
            # the ONNX graphs live under int8/. Supplying the config explicitly
            # lets Optimum load that layout without copying model files.
            config = AutoConfig.from_pretrained(
                model_source,
                subfolder=model_subfolder,
                **kwargs,
            )
            tokenizer = AutoTokenizer.from_pretrained(model_source, **kwargs)
            model = ORTModelForSeq2SeqLM.from_pretrained(
                model_source,
                subfolder=model_subfolder,
                config=config,
                provider="CPUExecutionProvider",
                encoder_file_name="encoder_model.onnx",
                decoder_file_name="decoder_model.onnx",
                decoder_with_past_file_name="decoder_with_past_model.onnx",
                **kwargs,
            )
            return tokenizer, model, IndicProcessor(inference=True)

        try:
            tokenizer = AutoTokenizer.from_pretrained(model_id, **kwargs)
            model = AutoModelForSeq2SeqLM.from_pretrained(model_id, **kwargs).to("cpu")
        except Exception as error:  # gated / offline / OOM / corrupt
            raise RuntimeError(_GATE_MESSAGE.format(model_id=model_id)) from error
        model.eval()
        return tokenizer, model, IndicProcessor(inference=True)

    # -- Translation ---------------------------------------------------------

    def translate(self, request: TranslateRequest) -> TranslateResponse:
        source = _INDICTRANS2_CODES.get(request.source_language)
        target = _INDICTRANS2_CODES.get(request.target_language)
        if source is None or target is None:
            not_found(
                "unsupported_pair",
                "This language pair is not supported by the IndicTrans2 provider.",
            )

        # Load on demand. Raises ModelUnavailableError (never fabricates) if the
        # real checkpoint cannot be produced.
        tokenizer, model, processor = self._ensure_loaded()

        translated = self._generate(request.text, source, target, tokenizer, model, processor)
        if not translated:
            raise ModelUnavailableError(
                "model_unavailable",
                "model produced no output",
                "IndicTrans2 returned an empty translation for the sentence.",
            )

        return TranslateResponse(
            translated_text=translated,
            source_text=request.text,
            source_language=request.source_language,
            target_language=request.target_language,
            source=self.source,
            provider=self.provider,
            model=self.model_id,
            model_version=self.model_version,
            confidence=None,
            spoken_text=None,
            reviewed_by_speaker=False,
            reviewed=False,
            is_real_model=True,
        )

    def _generate(
        self,
        text: str,
        source: str,
        target: str,
        tokenizer: Any,
        model: Any,
        processor: Any,
    ) -> str:
        inputs = processor.preprocess_batch([text], src_lang=source, tgt_lang=target)
        tokens = tokenizer(inputs, return_tensors="pt", padding=True)
        # Real inference runs under torch.no_grad. The test seam (injected fakes
        # with no torch installed) must still be exercisable, so the context
        # manager degrades to a no-op when torch is absent.
        from contextlib import nullcontext

        try:
            import torch

            guard = torch.no_grad()
        except ImportError:
            guard = nullcontext()
        with guard:
            generated = model.generate(**tokens, num_beams=4, max_new_tokens=256)
        with tokenizer.as_target_tokenizer():
            decoded = tokenizer.batch_decode(generated, skip_special_tokens=True)
        return processor.postprocess_batch(decoded, lang=target)[0]


def _is_onnx_model(model_id: str) -> bool:
    """Recognise the ONNX export without probing or downloading at startup."""
    lowered = model_id.lower()
    if lowered.endswith("-onnx"):
        return True
    path = Path(model_id)
    return path.name.lower() == _ONNX_SUBFOLDER or (
        path.is_dir() and (path / "encoder_model.onnx").exists()
    )
