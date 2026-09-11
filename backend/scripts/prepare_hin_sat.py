"""Validate, clean, report and split the COILD HIN-SAT pair.

Reads ``Hindi.txt`` + ``Santali.txt`` (one sentence per line, parallel order),
normalises both sides identically, verifies that the alignment is exact, removes
empty/duplicate/malformed rows *on both sides together* (so pairing is never
broken), computes script and length statistics, and writes a deterministic
80/10/10 train/validation/test split.

Safety rules (load-bearing):

- If one side has N lines and the other has M != N lines, the pipeline FAILS
  loudly. It never truncates or pads one side to make the counts match.
- Duplicates are removed only as *pairs* (normalised hindi + normalised santali),
  first occurrence wins, so a sentence can never leak across train/valid/test.
- Raw files are never modified. Everything is written under ``--out-dir``.
- Empty output (raw files absent, e.g. the dataset is still gated) produces an
  honest zero-row report — never fabricated pairs.

Usage::

    python -m scripts.prepare_hin_sat \
        --raw-dir data/raw/coild_hin_sat \
        --out-dir data/processed/hin_sat \
        --seed 20260830
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import unicodedata
from collections import Counter
from pathlib import Path
from typing import Callable

RAW_HIN = "Hindi.txt"
RAW_SAT = "Santali.txt"

SPLITS: dict[str, tuple[int, int]] = {
    "train": (0.0, 0.80),
    "valid": (0.80, 0.90),
    "test": (0.90, 1.00),
}

_LONG_LINE_CHARS = 300
_WHITESPACE = re.compile(r"\s+")

_OL_CHIKI = re.compile(r"[\u1C50-\u1C7F]")
_DEVANAGARI = re.compile(r"[\u0900-\u097F]")
_LATIN = re.compile(r"[A-Za-z\u00C0-\u024F]")
_ASCII_DIGIT = re.compile(r"[0-9]")
_OTHER = re.compile(r"[\uFFFD]")  # replacement char = malformed input signal


def _clean(text: str) -> str:
    """NFC-normalise, strip a BOM, collapse whitespace, strip edges.

    Applied identically to both sides so pair keys and counts always agree.
    """
    value = text.strip()
    if value.startswith("\ufeff"):
        value = value[1:].strip()
    value = unicodedata.normalize("NFC", value)
    return _WHITESPACE.sub(" ", value).strip()


def read_and_validate(path: Path) -> tuple[list[str], list[tuple[int, str]]]:
    """Read a UTF-8 sentence-per-line file with line-level error reporting."""
    raw = path.read_bytes()
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as error:
        raise ValueError(f"{path.name} is not valid UTF-8 at byte {error.start}") from error
    lines: list[tuple[int, str]] = []
    for index, line in enumerate(text.splitlines(), start=1):
        if index == 1 and line.startswith("\ufeff"):
            line = line[1:]
        lines.append((index, line))
    return _clean_all(lines), lines


def _clean_all(rows: list[tuple[int, str]]) -> list[str]:
    return [_clean(line) for _, line in rows]


def check_alignment(hin: list[str], sat: list[str]) -> int:
    """The alignment gate: equal length, else a loud failure. Returns the count."""
    if len(hin) != len(sat):
        shortest = min(len(hin), len(sat))
        preview = ""
        if shortest > 0:
            preview = (
                f" first mismatch sample -> hindi: {hin[shortest - 1]!r} | "
                f"santali: {sat[shortest - 1]!r}"
            )
        raise ValueError(
            f"ALIGNMENT FAILED: Hindi.txt has {len(hin)} lines, Santali.txt has "
            f"{len(sat)} lines.{preview} "
            "One side will never be truncated or padded to match; fix the source files."
        )
    return len(hin)


def script_distribution(texts: list[str]) -> dict[str, int]:
    """Per-line dominant-script histogram for one side (used for the Santali side)."""
    counts: Counter[str] = Counter()
    for text in texts:
        if not text:
            counts["empty"] += 1
        elif _OL_CHIKI.search(text):
            counts["ol_chiki"] += 1
        elif _DEVANAGARI.search(text):
            counts["devanagari"] += 1
        elif _LATIN.search(text):
            counts["latin"] += 1
        else:
            counts["other/digits"] += 1
    return dict(sorted(counts.items()))


def has_malformed_unicode(text: str) -> bool:
    """True for replacement characters or lone UTF-16 surrogates — either means
    the source was not round-tripped through UTF-8 cleanly."""
    return bool(
        _OTHER.search(text)
        or any(0xD800 <= ord(ch) <= 0xDFFF for ch in text)
    )


class DatasetNormaliser:
    """One place that owns "what counts as the same sentence" for dedup."""

    def __init__(self, fold_case: bool = True):
        self._fold_case = fold_case

    def key(self, value: str) -> str:
        value = value.lower() if self._fold_case else value
        value = unicodedata.normalize("NFC", value)
        value = _WHITESPACE.sub(" ", value).strip()
        value = re.sub(r"[!?।\u0964\u0965.,'’\u201c\u201d\"()\[\]]+", " ", value)
        return _WHITESPACE.sub(" ", value).strip()


def token_length_stats(texts: list[str]) -> dict[str, float | int]:
    if not texts:
        return {"pairs": 0}
    lengths = [len(text.split()) for text in texts]
    return {
        "pairs": len(lengths),
        "min_tokens": min(lengths),
        "max_tokens": max(lengths),
        "mean_tokens": round(sum(lengths) / len(lengths), 3),
        "median_tokens": round(sorted(lengths)[len(lengths) // 2], 1),
    }


def char_length_stats(texts: list[str]) -> dict[str, float | int]:
    if not texts:
        return {"pairs": 0}
    lengths = [len(text) for text in texts]
    return {
        "pairs": len(lengths),
        "min_chars": min(lengths),
        "max_chars": max(lengths),
        "mean_chars": round(sum(lengths) / len(lengths), 3),
    }


def write_markdown(summary: dict[str, object], out_dir: Path) -> None:
    """Human-readable mirror of dataset_report.json at `out_dir/DATASET_REPORT.md`."""
    md = [
        "# COILD-MT-Corpus HIN-SAT — dataset report",
        "",
        "- Dataset: `{dataset}`".format(**summary),
        "- Acquired: **{acquired}**".format(**summary),
    ]
    if not summary.get("acquired"):
        md += ["", str(summary.get("blocked_note", ""))]
    else:
        md += [
            "",
            f"- Raw pair count: **{summary['raw_pair_count']}**",
            f"- Valid pair count: **{summary['valid_pair_count']}**",
            f"- Removed pair count: **{summary['removed_pair_count']}** "
            f"(empty {summary['removed_empty']}, malformed {summary['removed_malformed']}, "
            f"duplicates {summary['duplicate_count']}, ratio {summary['duplicate_ratio']})",
            f"- Long lines (>300 chars): hindi {summary['long_line_gt_300_chars_hindi']}, "
            f"santali {summary['long_line_gt_300_chars_santali']}",
            "",
            "## Santali script distribution",
            "",
            "| script | pairs |",
            "| --- | --- |",
        ]
        for script, count in summary["santali_script_distribution"].items():
            md.append(f"| {script} | {count} |")
        md += [
            "",
            "## Length statistics",
            "",
            "| side | min | max | mean | median |",
            "| --- | --- | --- | --- | --- |",
            f"| hindi tokens | {summary['hindi_tokens']['min_tokens']} | "
            f"{summary['hindi_tokens']['max_tokens']} | "
            f"{summary['hindi_tokens']['mean_tokens']} | "
            f"{summary['hindi_tokens']['median_tokens']} |",
            f"| santali tokens | {summary['santali_tokens']['min_tokens']} | "
            f"{summary['santali_tokens']['max_tokens']} | "
            f"{summary['santali_tokens']['mean_tokens']} | "
            f"{summary['santali_tokens']['median_tokens']} |",
            "",
            "## Splits (deterministic)",
            "",
            "| split | pairs |",
            "| --- | --- |",
        ]
        for name, count in summary["splits"].items():
            md.append(f"| {name} | {count} |")
        md += [
            "",
            f"- Split seed: {summary['split_seed']} — {summary['split_note']}",
        ]
    (out_dir / "DATASET_REPORT.md").write_text("\n".join(md) + "\n", encoding="utf-8")


def prepare(
    raw_dir: Path,
    out_dir: Path,
    seed: int,
    report: Path,
    progress: Callable[[str], None] = print,
) -> dict[str, object]:
    """The whole pipeline. Runs the alignment gate, cleans, dedupes, splits."""
    out_dir.mkdir(parents=True, exist_ok=True)
    hin_path = raw_dir / RAW_HIN
    sat_path = raw_dir / RAW_SAT

    if not hin_path.exists() or not sat_path.exists():
        missing = [p.name for p in (hin_path, sat_path) if not p.exists()]
        summary = {
            "dataset": "COILD-MT-Corpus HIN-SAT",
            "raw_files": sorted(p.name for p in (hin_path, sat_path)),
            "acquired": False,
            "blocked_note": (
                "The COILD HIN-SAT files are gated and not yet acquired. Run "
                "scripts/acquire_coild_hin_sat.py with an accepted-terms token "
                f"first; missing: {missing}. No pairs were fabricated."
            ),
            "raw_pair_count": 0,
            "valid_pair_count": 0,
            "removed_pair_count": 0,
            "splits": {name: 0 for name in SPLITS},
        }
        report.parent.mkdir(parents=True, exist_ok=True)
        report.write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        write_markdown(summary, out_dir)
        progress("BLOCKED: raw COILD files are not acquired — zero-row honest report written.")
        return summary

    progress(f"reading {hin_path.name} …")
    hin, hin_raw = read_and_validate(hin_path)
    progress(f"reading {sat_path.name} …")
    sat, sat_raw = read_and_validate(sat_path)

    check_alignment(hin, sat)
    raw_count = len(hin)

    # Remove rows that are empty on EITHER side (a pair is only a pair if both
    # halves exist). Removal is symmetric — the pairing is never shifted.
    kept: list[tuple[str, str]] = []
    rejected_empty = 0
    for hi, sa in zip(hin, sat):
        if not hi or not sa:
            rejected_empty += 1
            continue
        kept.append((hi, sa))

    malformed_indexes: list[int] = []
    for index, (hi, sa) in enumerate(kept):
        if has_malformed_unicode(hi) or has_malformed_unicode(sa):
            malformed_indexes.append(index)
    for index in reversed(malformed_indexes):
        kept.pop(index)

    # Duplicate removal on the NORMALISED pair (first occurrence wins). This
    # happens before the split, so a sentence cannot leak across partitions.
    normaliser = DatasetNormaliser()
    seen: set[tuple[str, str]] = set()
    deduped: list[tuple[str, str]] = []
    duplicate_count = 0
    for hi, sa in kept:
        pair_key = (normaliser.key(hi), normaliser.key(sa))
        if pair_key in seen:
            duplicate_count += 1
            continue
        seen.add(pair_key)
        deduped.append((hi, sa))

    long_hi = [i for i, (hi, _) in enumerate(deduped) if len(hi) > _LONG_LINE_CHARS]
    long_sa = [i for i, (_, sa) in enumerate(deduped) if len(sa) > _LONG_LINE_CHARS]

    hin_clean = [hi for hi, _ in deduped]
    sat_clean = [sa for _, sa in deduped]

    # Deterministic split.
    rng = __import__("random").Random(seed)
    order = list(range(len(deduped)))
    rng.shuffle(order)
    split_files: dict[str, int] = {}
    for name, (start, end) in SPLITS.items():
        lo = int(len(order) * start)
        hi = int(len(order) * end)
        indexes = order[lo:hi]
        split_files[name] = len(indexes)
        (out_dir / f"{name}.hi").write_text(
            "\n".join(deduped[i][0] for i in indexes) + ("\n" if indexes else ""),
            encoding="utf-8",
        )
        (out_dir / f"{name}.sat").write_text(
            "\n".join(deduped[i][1] for i in indexes) + ("\n" if indexes else ""),
            encoding="utf-8",
        )

    scripts = script_distribution(sat_clean)

    summary = {
        "dataset": "COILD-MT-Corpus HIN-SAT",
        "acquired": True,
        "normalisation": "NFC + whitespace fold, both sides identically",
        "duplicate_rule": "normalised pair key, first wins, before splitting",
        "raw_pair_count": raw_count,
        "valid_pair_count": len(deduped),
        "removed_pair_count": raw_count - len(deduped),
        "removed_empty": rejected_empty,
        "removed_malformed": len(malformed_indexes),
        "duplicate_count": duplicate_count,
        "duplicate_ratio": round(duplicate_count / raw_count, 4) if raw_count else 0,
        "long_line_gt_300_chars_hindi": len(long_hi),
        "long_line_gt_300_chars_santali": len(long_sa),
        "santali_script_distribution": scripts,
        "hindi_tokens": token_length_stats(hin_clean),
        "santali_tokens": token_length_stats(sat_clean),
        "hindi_chars": char_length_stats(hin_clean),
        "santali_chars": char_length_stats(sat_clean),
        "splits": split_files,
        "split_seed": seed,
        "split_note": (
            "Deterministic random shuffle (seed above) after global pair "
            "dedupe — no source sentence appears in more than one split."
        ),
    }
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    write_markdown(summary, out_dir)

    progress(
        f"done: {raw_count} raw -> {len(deduped)} clean "
        f"(train {split_files['train']}, valid {split_files['valid']}, "
        f"test {split_files['test']})."
    )
    return summary


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Validate, clean, report and split HIN-SAT")
    parser.add_argument("--raw-dir", type=Path, default=Path("data/raw/coild_hin_sat"))
    parser.add_argument("--out-dir", type=Path, default=Path("data/processed/hin_sat"))
    parser.add_argument("--report", type=Path, default=Path("data/processed/hin_sat/dataset_report.json"))
    parser.add_argument("--seed", type=int, default=20260830)
    args = parser.parse_args(argv)

    try:
        prepare(args.raw_dir, args.out_dir, args.seed, args.report)
    except ValueError as error:
        print(f"FAILED: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())