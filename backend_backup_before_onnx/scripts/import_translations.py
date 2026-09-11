"""Authoritative phrasebook data ingestion (CSV/JSON -> canonical JSONL pack).

This is the repeatable pipeline for bringing REAL, VERIFIED multilingual data
into GyanSetu. It exists so that the day the project owner provides an
authoritative Hindi/Santali (or Mundari/Ho) dataset, it can be validated,
deduplicated and emitted as the on-device phrasebook pack without hand-editing
seed code.

Rules that keep the pipeline honest:

- Every language is validated against the canonical catalogue and the pair must
  be a supported translation pair (hindi<->santali today).
- A record is only ever marked ``verified`` when the row says so *and* carries a
  sourced provenance. Arbitrary/unchecked rows import as unverified and are
  never exposed as real translations.
- A row with no target text is a placeholder and can never be verified.
- Record ids are derived deterministically from (pair, normalised source), so
  re-importing the same sentence is idempotent and duplicates collapse.
- Nothing is written on partial failure: any invalid row aborts the whole
  import before a single line is emitted.

Usage::

    python -m scripts.import_translations \\
        --input data/translations.csv --input data/extra.json \\
        --write data/generated/translations_import.jsonl

Input files may be CSV, JSON (a bare list or `{"translations": [...]}`), or
the canonical JSONL pack shape (one record per line).

If no authoritative dataset is provided, do not run this with fabricated rows —
it is a boundary, not a generator. Use it when the data exists.
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

from pydantic import ValidationError

from app.schemas.translation_record import (
    TranslationRecord,
    build_translation_record_id,
    normalise_translation_source_text,
)

# csv header / JSON key aliases folded onto the canonical record field names.
_FIELD_ALIASES = {
    "source_language": "source_language",
    "sourceLanguage": "source_language",
    "target_language": "target_language",
    "targetLanguage": "target_language",
    "source_text": "source_text",
    "sourceText": "source_text",
    "target_text": "target_text",
    "targetText": "target_text",
    "spoken_text": "spoken_text",
    "spokenText": "spoken_text",
    "category": "category",
    "context": "context",
    "dialect": "dialect",
    "provenance": "provenance",
    "provenance/source": "provenance",
    "source": "provenance",
    "verified": "verified",
    "version": "version",
    "created_at": "created_at",
    "createdAt": "created_at",
    "updated_at": "updated_at",
    "updatedAt": "updated_at",
}

_TRUE_VALUES = {"true", "1", "yes", "y", "verified"}


class ImportValidationError(ValueError):
    """Raised (before any write) when any row fails validation."""


@dataclass(frozen=True)
class ImportReport:
    files_read: int
    rows_read: int
    inserted: int
    skipped_duplicate_or_idempotent: int
    placeholders: int
    verified: int
    unverified: int
    rejected: tuple[str, ...] = field(default_factory=tuple)

    def as_dict(self) -> dict[str, object]:
        return {
            "filesRead": self.files_read,
            "rowsRead": self.rows_read,
            "inserted": self.inserted,
            "skippedDuplicateOrIdempotent": self.skipped_duplicate_or_idempotent,
            "placeholders": self.placeholders,
            "verified": self.verified,
            "unverified": self.unverified,
            "rejected": list(self.rejected),
        }


def _fold_header(value: str) -> str:
    return _FIELD_ALIASES.get(value.strip(), value.strip().replace(" ", "_").lower())


def _as_bool(value: object) -> bool:
    if isinstance(value, bool):
        return value
    return str(value or "").strip().lower() in _TRUE_VALUES


def _clean_row(row: dict[str, str]) -> dict[str, object]:
    folded: dict[str, object] = {}
    for key, raw in row.items():
        if key is None:
            continue
        canonical = _fold_header(key)
        value = (raw or "").strip() if isinstance(raw, str) else raw
        if canonical == "verified":
            value = _as_bool(raw)
        elif canonical in {"version"} and isinstance(value, str) and value != "":
            value = int(value)
        elif canonical in {"created_at", "updated_at"} and value == "":
            value = None
        if value == "":
            value = None
        folded[canonical] = value
    return folded


def _natural_key(record: TranslationRecord) -> tuple[str, str]:
    return (
        f"{record.source_language}>{record.target_language}",
        normalise_translation_source_text(record.source_text),
    )


def _row_to_record(
    row: dict[str, object], origin: str, line_number: int
) -> TranslationRecord:
    try:
        source_language = str(row.get("source_language") or "").strip()
        target_language = str(row.get("target_language") or "").strip()
        source_text = str(row.get("source_text") or "").strip()
        # target_text comes through as None when the cell was blank -> a
        # placeholder, never a guessed translation.
        target_raw = row.get("target_text")
        target_text = None if target_raw is None else str(target_raw).strip()
        if target_text == "":
            target_text = None

        record = TranslationRecord(
            id=build_translation_record_id(
                source_language.lower(), target_language.lower(), source_text
            ),
            source_language=source_language,
            target_language=target_language,
            source_text=source_text,
            target_text=target_text,
            spoken_text=(
                None
                if row.get("spoken_text") is None
                else str(row.get("spoken_text")).strip()
            ),
            category=None if row.get("category") is None else str(row["category"]),
            context=None if row.get("context") is None else str(row["context"]),
            dialect=None if row.get("dialect") is None else str(row["dialect"]),
            verified=bool(row.get("verified") or False),
            provenance=str(row.get("provenance") or "").strip(),
            version=int(row.get("version") or 1),
            created_at=_parse_datetime(row.get("created_at")),
            updated_at=_parse_datetime(row.get("updated_at")),
        )
        return record
    except (ValidationError, ValueError) as exc:
        raise ImportValidationError(
            f"{origin}:{line_number}: invalid row -> {exc}"
        ) from exc


def _parse_datetime(value: object) -> datetime | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        return value
    try:
        return datetime.fromisoformat(str(value))
    except ValueError:
        return None


def _read_rows(path: Path) -> list[tuple[dict[str, object], str, int]]:
    """Read one input file into raw rows.

    Accepted shapes: CSV (one record per row) and JSON (either a bare list of
    records or `{"translations": [...]}` for Flex portability), and the
    canonical pack shape JSONL (one record per line) — so the importer can
    re-swallow its own output. Every malformed file is reported as an
    [ImportValidationError], never a crash.
    """
    raw = path.read_bytes()
    if path.suffix.lower() == ".csv":
        text = raw.decode("utf-8-sig")
        reader = csv.DictReader(text.splitlines())
        return [
            (_clean_row(row), f"{path.name}", index + 2)
            for index, row in enumerate(reader)
            if any((k is not None and (v or "").strip() != "") for k, v in row.items())
        ]
    if path.suffix.lower() == ".jsonl":
        rows: list[tuple[dict[str, object], str, int]] = []
        for index, line in enumerate(raw.decode("utf-8").splitlines(), start=1):
            text = line.strip()
            if not text:
                continue
            try:
                obj = json.loads(text)
            except json.JSONDecodeError as error:
                raise ImportValidationError(
                    f"{path.name} line {index} is not valid JSON: {error.msg}"
                ) from error
            if not isinstance(obj, dict):
                raise ImportValidationError(
                    f"{path.name} line {index}: expected one record per line"
                )
            rows.append((_clean_row(obj), f"{path.name}", index))
        return rows
    try:
        payload = json.loads(raw.decode("utf-8"))
    except json.JSONDecodeError as error:
        raise ImportValidationError(
            f"{path.name} is not valid JSON: {error.msg}"
        ) from error
    if isinstance(payload, dict):
        records = payload.get("translations")
        if not isinstance(records, list):
            raise ImportValidationError(
                f"{path.name}: expected a bare list of records or a "
                '{"translations": [...]} object'
            )
    else:
        records = payload
    if not isinstance(records, list):
        raise ImportValidationError(f"{path.name}: expected a list of records")
    return [
        (_clean_row(row), f"{path.name}", index + 1)
        for index, row in enumerate(records)
        if isinstance(row, dict)
    ]


def _load_existing(write_path: Path) -> dict[str, dict[str, object]]:
    if not write_path.exists():
        return {}
    existing: dict[str, dict[str, object]] = {}
    for line in write_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        obj = json.loads(line)
        existing[str(obj["id"])] = obj
    return existing


def import_translations(
    input_paths: list[Path],
    write_path: Path | None = None,
    replace: bool = False,
    now: datetime | None = None,
) -> ImportReport:
    """Validate, deduplicate and write every input row into the canonical pack.

    Strict by design: any invalid row aborts before a single line is written,
    and an unverified row is stored unverified — never silently accepted as a
    real translation.
    """
    if not input_paths:
        raise ImportValidationError("no --input files given")

    stamped = now or datetime.now(timezone.utc)
    rows: list[tuple[dict[str, object], str, int]] = []
    for path in input_paths:
        if not path.exists():
            raise ImportValidationError(f"input file not found: {path}")
        rows.extend(_read_rows(path))

    rejected: list[str] = []
    validated: list[TranslationRecord] = []
    seen_natural: set[tuple[str, str]] = set()
    duplicate_natural = 0
    for row, origin, line in rows:
        try:
            record = _row_to_record(row, origin, line)
        except ImportValidationError as exc:
            rejected.append(str(exc))
            continue

        natural = _natural_key(record)
        if natural in seen_natural:
            duplicate_natural += 1
            continue
        seen_natural.add(natural)
        if record.created_at is None:
            record.created_at = stamped
        if record.updated_at is None:
            record.updated_at = stamped
        validated.append(record)

    if rejected:
        raise ImportValidationError(
            f"{len(rejected)} rows failed validation; nothing was written:\n"
            + "\n".join(f"- {message}" for message in rejected)
        )

    existing = {} if write_path is None else _load_existing(write_path)
    merged: dict[str, dict[str, object]] = dict(existing)
    if replace:
        merged = {}
    already_present = 0
    rejected_natural = 0
    added = 0
    for record in validated:
        if record.id in merged:
            already_present += 1
            continue
        row_id = _natural_key(record)
        if any(_natural_key_from_line(line) == row_id for line in merged.values()):
            rejected_natural += 1
            continue
        merged[record.id] = record.to_pack_json()
        added += 1

    if write_path is not None:
        write_path.parent.mkdir(parents=True, exist_ok=True)
        body = "\n".join(json.dumps(line, ensure_ascii=False) for line in merged.values())
        write_path.write_text((body + "\n") if body else "", encoding="utf-8")

    placeholders = sum(1 for r in validated if r.is_placeholder)
    verified = sum(1 for r in validated if r.verified)
    skipped = (
        duplicate_natural
        + already_present
        + rejected_natural
        + (len(existing) if replace else 0)
    )
    return ImportReport(
        files_read=len(input_paths),
        rows_read=len(rows),
        inserted=added,
        skipped_duplicate_or_idempotent=skipped,
        placeholders=placeholders,
        verified=verified,
        unverified=len(validated) - verified,
        rejected=tuple(),
    )


def _natural_key_from_line(line: dict[str, object]) -> tuple[str, str]:
    return (
        f"{line.get('sourceLanguage')}>{line.get('targetLanguage')}",
        normalise_translation_source_text(str(line.get("sourceText") or "")),
    )


def _print_report(report: ImportReport) -> None:
    print("Translation import complete:")
    for label, value in report.as_dict().items():
        print(f"  {label}: {value}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Import authoritative phrasebook data (CSV/JSON) into the canonical "
            "JSONL pack. Validates, normalises and deduplicates; any invalid row "
            "aborts before anything is written."
        )
    )
    parser.add_argument("--input", action="append", required=True, type=Path)
    parser.add_argument(
        "--write",
        type=Path,
        default=Path("data/generated/translations_import.jsonl"),
    )
    parser.add_argument(
        "--replace",
        action="store_true",
        help="Overwrite existing idempotent output rows instead of keeping them.",
    )
    args = parser.parse_args(argv)

    try:
        report = import_translations(
            input_paths=args.input, write_path=args.write, replace=args.replace
        )
    except ImportValidationError as exc:
        print(str(exc), file=sys.stderr)
        return 2
    _print_report(report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())