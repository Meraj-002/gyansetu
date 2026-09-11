# IndicTrans2 on-device: resource analysis and the offline decision

Dates: analysis 2026-08‑30 · intended device target: 2 GB RAM Android.

## 1. Candidate model

`ai4bharat/indictrans2-indic-indic-dist-320M` — the smallest official
Indic‑Indic checkpoint (the school needs Hindi→Santali, `hin_Deva`→`sat_Olck`,
which IndicTrans2 supports natively). 320 M parameters, MIT license, gated on
Hugging Face (must agree to share contact info). The 1 B variant
(`indictrans2-indic-indic-1B`) exists but is strictly worse for a small phone.

## 2. Estimated memory, not measured

Safetensor weights are estimates from parameter count — **they are not a
benchmark**. A measurement on a real device happens only after the gated model
is downloadable, and the report is marked *not measured* until then.

| Format | Weights (320 M × N bytes) | Rough process RAM (weights + activations + SentencePiece/IndicProcessor overhead) |
|---|---|---|
| FP32 | ~1.28 GB | ≈1.5–1.7 GB |
| FP16 | ~0.64 GB | ≈0.8–1.0 GB |
| INT8 | ~0.32 GB | ≈0.4–0.5 GB |
| INT4 | ~0.16 GB | ≈0.25–0.35 GB |

An Android 2 GB device already spends most of its RAM on the OS, the Flutter
shell, and the speech/audio stack (<1 GB typically left for a big native
library). FP32 therefore **does not fit**, FP16 is borderline and risky at
runtime, and INT8/INT4 are plausible for memory but there is **no published,
quality-checked quantisation** of IndicTrans2 that we can ship responsibly. On
top of weights, generation with beam‑4 needs a tokenizer, IndicProcessor,
activation workspace, and the Hindi/Santali SentencePiece models.

## 3. Decision: server-side inference

For the 2 GB classroom device, **GyanSetu translates via the backend
(`POST /api/v1/translate`, `IndicTrans2TranslationProvider`), not on-device.**
That server can hold FP32 comfortably and batch requests. The phone keeps its
small offline cache and its curated phrasebook for no-network classrooms; it is
never pushed a 1 GB+ model it cannot host.

Consequence for the milestone: the on-device model-caching phase is superseded
by this decision (server-side model caching/porting to TFLite/GenAI is listed
as "not implemented — deliberately").

## 4. What runs where

| Capability | Where | Notes |
|---|---|---|
| IndicTrans2 FP32 | Backend (CPU/GPU) | Gated checkpoint; needs token + torch/transformers |
| Offline translations | On device: LLM translation cache + curated phrasebook | No model on-device |
| Cache key | `src + tgt + normalised text + model_version` | `indic_trans2-...-dist-320M` ≠ `dev-rules-1`, so no cross-provider staleness |
| "AI translation" badge | On device | Shown only when backend reports `is_real_model: true` |

## 5. Honesty rules enforced by the pipeline (unchanged by this decision)

- No BLEU/chrF claimed until a real checkpoint runs and outputs are guarded by
  `evaluation/evaluation_metrics.json` (`measured: true`).
- Every exported sample is `human_review_required: true`; no prediction is
  labelled correct automatically.
- `confidence` stays null (IndicTrans2 exposes none — fabricating one is
  forbidden); `reviewed_by_speaker` stays false for model output.
- If the 2 GB feasibility of a quantised variant is ever revisited, that claim
  must be supported by an on-device measurement in this file, not an estimate.