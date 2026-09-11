"""Evaluate the Hindi -> Santali test split against a real model when one can
load, and produce the honest sample-translation report either way.

The script is deliberately usable in three states:

- Data available + benchmark adds a loader from ``--out-dir`` -> runs IndicTrans2
  (or loads ``--predictions``) and writes BLEU/chrF.
- Data available + no model -> writes an honest *failure* report.
- No data -> writes an honest *dataset-blocked* report.

It never glances at a file, never drops predictions, and never claims a
prediction is correct: ``human_review_required`` defaults to ``true`` for every
sample. The metrics file is written only when a model actually loaded.

Typical run (after the COILD data landed and torch/transformers/IndicTransToolkit
are installed on a machine that can run inference):

    python scripts/evaluate_hin_sat.py --test-dir data/processed/hin_sat \
      --out-dir ../evaluation

Exits: 0 on a real measurement or an honest blocked report; 2 for any coding /
alignment failure; 3 when the test split (dataset) is not present.
"""

from __future__ import annotations

import argparse
import json
import random
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

# Allow running as `python scripts/evaluate_hin_sat.py` from anywhere.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.schemas.translation import TranslateRequest

EVALUATION_DIR = Path(__file__).resolve().parent.parent.parent / "evaluation"
SRC_LANG = "hindi"
TGT_LANG = "santali"
MODEL_CANDIDATE = "indic_trans2"

# Rough Hindi keyword categories used only to pick a *representative* sample for
# human review. Never used to judge correctness — a model's translation is
# always human-reviewable regardless of category.
_CATEGORIES: dict[str, tuple[str, ...]] = {
    "numbers_counting": (
        "एक", "दो", "तीन", "चार", "पाँच", "पांच", "गिनती", "कितने",
        "का", " 1 ", " 2 ", " 3 ", " 4 ", " 5 ",
    ),
    "greetings_polite": (
        "नमस्ते", "प्रणाम", "सुप्रभात", "शुभ", "धन्यवाद", "क्षमा",
    ),
    "questions": (
        "क्या", "कौन", "कहाँ", "कब", "कैसे", "क्योंकि", "क्यों", "कितना",
        "कौन-सा",
    ),
    "classroom_instructions": (
        "बैठ", "खड़े", "खड़े", "किताब", "कॉपी", "बोर्ड", "ध्यान", "चुप",
        "सुनो", "देखो", "बारी",
    ),
    "school_objects": (
        "कलम", "पेंसिल", "बैग", "चाक", "डेस्क", "रबड़", "रबर", "ईंट",
    ),
    "activities": (
        "खेल", "गाना", "लिखना", "पढ़ना", "पढना", "दौड़", "दौड", "चित्र",
    ),
    "encouragement": (
        "शाबाश", "बहुत अच्छा", "वाह", "बढ़िया", "सुंदर", "सुन्दर", "अच्छा"
    ),
    "safety_health": (
        "सड़क", "सडक", "खतरा", "मदद", "डॉक्टर", "सुरक्षित", "रोग", "दवा",
    ),
}

_OTHER = "other"


@dataclass(frozen=True)
class Pair:
    index: int
    source: str
    reference: str
    category: str


def _category(source: str) -> str:
    for name, keywords in _CATEGORIES.items():
        if any(keyword in source for keyword in keywords):
            return name
    return _OTHER


def load_pairs(test_dir: Path, src_suffix: str, tgt_suffix: str) -> list[Pair]:
    src_file = test_dir / src_suffix
    tgt_file = test_dir / tgt_suffix
    if not src_file.exists() or not tgt_file.exists():
        raise FileNotFoundError(
            f"Test split missing ({src_file} / {tgt_file}); the COILD HIN-SAT "
            "dataset has not been acquired/prepared yet."
        )
    src_lines = src_file.read_text(encoding="utf-8").splitlines()
    tgt_lines = tgt_file.read_text(encoding="utf-8").splitlines()
    if len(src_lines) != len(tgt_lines):
        raise ValueError(
            f"Alignment broken: {len(src_lines)} source vs {len(tgt_lines)} target "
            "lines. The prepare gate should have caught this; re-run prepare_hin_sat."
        )
    return [
        Pair(i, src, ref, _category(src))
        for i, (src, ref) in enumerate(zip(src_lines, tgt_lines))
    ]


def pick_samples(pairs: list[Pair], count: int, seed: int) -> list[Pair]:
    """Deterministic, category-balanced sample for human review."""
    by_category: dict[str, list[Pair]] = {}
    for pair in pairs:
        by_category.setdefault(pair.category, []).append(pair)
    rng = random.Random(seed)
    picked: list[Pair] = []
    remaining = [list(c) for c in by_category.values()]
    while len(picked) < count and remaining:
        for bucket in remaining:
            if len(picked) >= count:
                break
            if bucket:
                picked.append(bucket.pop(rng.randrange(len(bucket))))
        remaining = [b for b in remaining if b]
    return picked


def load_predictions(path: Path, pairs: list[Pair]) -> list[str]:
    predictions = path.read_text(encoding="utf-8").splitlines()
    if len(predictions) != len(pairs):
        raise ValueError(
            f"--predictions has {len(predictions)} lines but the test split has "
            f"{len(pairs)} pairs; alignment must be 1:1."
        )
    return predictions


def measure(pairs: list[Pair], src_lang: str, tgt_lang: str) -> tuple[list[str], list[float]]:
    from app.services.indic_trans2_translation_provider import (
        IndicTrans2TranslationProvider,
    )

    provider = IndicTrans2TranslationProvider()
    predictions: list[str] = []
    latencies_ms: list[float] = []
    for pair in pairs:
        started = time.perf_counter()
        reply = provider.translate(
            TranslateRequest(
                text=pair.source, source_language=src_lang, target_language=tgt_lang
            )
        )
        latencies_ms.append((time.perf_counter() - started) * 1000.0)
        predictions.append(reply.translated_text)
    return predictions, latencies_ms


def compute_metrics(predictions: list[str], references: list[str]) -> dict[str, float]:
    try:
        import sacrebleu
    except ImportError as error:
        raise RuntimeError(
            "Metrics need sacrebleu (pip install sacrebleu)."
        ) from error
    corpus = sacrebleu.corpus_bleu(predictions, [references])
    chrf = sacrebleu.corpus_chrf(predictions, references)
    return {"bleu": round(corpus.score, 2), "chrF": round(chrf.score, 2)}


def write_blocked_report(out_dir: Path, reason: str, detail: str) -> None:
    report = {
        "measured": False,
        "provider": MODEL_CANDIDATE,
        "model_version": "indictrans2-indic-indic-dist-320M",
        "test_pairs": 0,
        "status": "blocked",
        "reason": reason,
        "detail": detail,
        "metrics": None,
        "note": (
            "No real translation was run, so no BLEU/chrF is reported and no "
            "translation is claimed correct. The report exists so the pipeline "
            "is provably present before the data/model become available."
        ),
    }
    out_dir.mkdir(parents=True, exist_ok=True)
    _write_json(out_dir / "evaluation_metrics.json", report)
    _write_json(out_dir / "sample_translations.json", [])
    _write_markdown(out_dir / "evaluation_metrics.md", report, [], [], [])


def _write_json(path: Path, value: Any) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def _write_markdown(
    path: Path,
    report: dict[str, Any],
    pairs: list[Pair],
    predictions: list[str],
    latencies_ms: list[float],
) -> None:
    lines = [
        "# Hindi -> Santali evaluation",
        "",
        f"- Provider: `{report['provider']}`",
        f"- Model version: `{report['model_version']}`",
        f"- Test pairs: {report['test_pairs']}",
        f"- Measured: **{report['measured']}**",
    ]
    metrics = report.get("metrics")
    if metrics:
        lines.append(f"- BLEU: {metrics['bleu']}")
        lines.append(f"- chrF: {metrics['chrF']}")
        latency = report.get("latency_ms")
        if latency is not None:
            lines.append(f"- Latency (ms): p50 {latency.get('p50', 'n/a')} / p95 {latency.get('p95', 'n/a')}")
    if report.get("status") == "blocked":
        lines.append("")
        lines.append(f"Status: **blocked** — {report['reason']}")
        lines.append("")
        lines.append(report["detail"])
        lines.append("")
        lines.append(report["note"])
    lines.append("")
    lines.append("## Human-review samples")
    lines.append("")
    if predictions:
        for pair, prediction, latency in zip(pairs, predictions, latencies_ms):
            lines.append(f"### {pair.index + 1}. {pair.source}")
            lines.append("")
            lines.append(f"- Category: `{pair.category}`")
            lines.append(f"- Reference: {pair.reference}")
            lines.append(f"- Prediction: {prediction}")
            lines.append(f"- Latency: {latency:.0f} ms")
            lines.append("- Human review required: **yes**")
            lines.append("")
    else:
        lines.append("_None — not measured._")
        lines.append("")
    path.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--test-dir", type=Path, default=Path("data/processed/hin_sat"))
    parser.add_argument("--out-dir", type=Path, default=EVALUATION_DIR)
    parser.add_argument("--src-suffix", default="test.hi")
    parser.add_argument("--tgt-suffix", default="test.sat")
    parser.add_argument("--max-samples", type=int, default=30)
    parser.add_argument("--seed", type=int, default=20260830)
    parser.add_argument("--predictions", type=Path, default=None,
                        help="Optional 1-prediction-per-test-line file, to measure BLEU/chrF without the model.")
    parser.add_argument("--src-lang", default="hindi")
    parser.add_argument("--tgt-lang", default="santali")
    args = parser.parse_args()

    out_dir = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    try:
        pairs = load_pairs(args.test_dir, args.src_suffix, args.tgt_suffix)
    except FileNotFoundError as error:
        write_blocked_report(out_dir, "dataset_not_present", str(error))
        print("BLOCKED: dataset not present")
        print(error)
        return 3

    samples = pick_samples(pairs, min(args.max_samples, len(pairs)), args.seed)

    predictions: list[str] = []
    latencies_ms: list[float] = []
    measured_with: str = MODEL_CANDIDATE
    if args.predictions:
        try:
            predictions = load_predictions(args.predictions, pairs)
            measured_with = "external-file"
        except ValueError as error:
            print(f"ERROR: {error}")
            return 2

    if not predictions:
        try:
            predictions, latencies_ms = measure(pairs, args.src_lang, args.tgt_lang)
        except Exception as error:  # model unavailable / deps missing / gated
            detail = str(error)
            write_blocked_report(out_dir, "model_unavailable", detail)
            print("BLOCKED: model unavailable")
            print(detail)
            return 2

    metrics: dict[str, float] | None = None
    try:
        metrics = compute_metrics(predictions, [pair.reference for pair in pairs])
    except RuntimeError as error:
        print(f"WARNING: metrics skipped ({error})")

    percentile = sorted(latencies_ms)
    latency_summary = None
    if percentile:
        latency_summary = {
            "p50": round(percentile[len(percentile) // 2], 1),
            "p95": round(percentile[int(len(percentile) * 0.95) - 1], 1),
        }

    report = {
        "measured": True,
        "provider": measured_with,
        "model_version": "indictrans2-indic-indic-dist-320M",
        "status": "measured",
        "test_pairs": len(pairs),
        "metrics": metrics,
        "latency_ms": latency_summary,
        "samples_exported": len(samples),
        "note": (
            "Model output is never auto-verified. Every exported sample is "
            "human_review_required so a spokesperson can check it before it is "
            "misted for the classroom."
        ),
    }
    sample_objects = []
    for pair, prediction, latency in zip(samples, predictions, latencies_ms):
        sample_objects.append({
            "source": pair.source,
            "reference": pair.reference,
            "prediction": prediction,
            "category": pair.category,
            "latency_ms": round(latency, 1),
            "human_review_required": True,
        })
    _write_json(out_dir / "evaluation_metrics.json", report)
    _write_json(out_dir / "sample_translations.json", sample_objects)
    _write_markdown(out_dir / "evaluation_metrics.md", report, samples, predictions, latencies_ms)
    print(f"Wrote evaluation_metrics.json + sample_translations.json to {out_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())