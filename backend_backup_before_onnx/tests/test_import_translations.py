"""Tests for the authoritative data pipeline (scripts/import_translations).

These run against synthetic fixture files, never real Santali. They prove the
ingestion boundary behaves honestly: it validates, normalises, deduplicates and
stays idempotent — and it refuses to fabricate or silently verify data.
"""

from __future__ import annotations

import csv
import hashlib
import io
import json
import pathlib

import pytest

from app.schemas.translation_record import (
    TranslationRecord,
    build_translation_record_id,
)
from scripts.import_translations import (
    ImportValidationError,
    import_translations,
)

HEADER = [
    "sourceLanguage",
    "targetLanguage",
    "sourceText",
    "targetText",
    "spokenText",
    "category",
    "context",
    "dialect",
    "provenance",
    "verified",
]


def _csv_rows(rows: list[list[str]]) -> str:
    buffer = io.StringIO()
    writer = csv.writer(buffer)
    writer.writerow(HEADER)
    writer.writerows(rows)
    return buffer.getvalue()


def _one_row_csv(tmp_path, rows: list[list[str]]) -> str:
    path = tmp_path / "input.csv"
    path.write_text(_csv_rows(rows), encoding="utf-8")
    return str(path)


def _load_output(write_path) -> list[dict]:
    return [
        json.loads(line)
        for line in write_path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def test_imports_an_unverified_row_as_unverified_only(tmp_path):
    out = tmp_path / "out.jsonl"
    csv = _one_row_csv(
        tmp_path,
        [["hindi", "santali", "बच्चों, कितने आम हैं?", "Gidra'ko, kete ul menaka?",
          "गिड़ाको, केते उल् मेनाका?", "questions", "", "", "authored-development",
          "false"]],
    )
    report = import_translations(
        [pathlib.Path(csv)], write_path=out
    )

    assert report.inserted == 1
    assert report.verified == 0
    assert report.unverified == 1
    lines = _load_output(out)
    assert len(lines) == 1
    row = lines[0]
    assert row["verified"] is False
    assert row["reviewedBySpeaker"] is False
    assert row["sourceLanguage"] == "hindi"
    assert row["targetLanguage"] == "santali"
    assert row["version"] == 1
    assert row["id"].startswith("pb-")
    # Deterministic id from the natural key.
    expected = build_translation_record_id("hindi", "santali", "बच्चों, कितने आम हैं?")
    assert row["id"] == expected


def test_imports_a_verified_sourced_row_as_verified(tmp_path):
    out = tmp_path / "out.jsonl"
    csv = _one_row_csv(
        tmp_path,
        [["hindi", "santali", "एक", "mit'", "मित्", "numbers", "", "", "sourced", "true"]],
    )
    report = import_translations([pathlib.Path(csv)], write_path=out)

    assert report.verified == 1
    row = _load_output(out)[0]
    assert row["verified"] is True
    assert row["reviewedBySpeaker"] is True
    assert row["provenance"] == "sourced"


def test_verified_without_a_real_provenance_is_rejected(tmp_path):
    out = tmp_path / "out.jsonl"
    csv = _one_row_csv(
        tmp_path,
        [["hindi", "santali", "एक", "mit'", "मित्", "numbers", "", "", "authored-development",
          "true"]],
    )
    with pytest.raises(ImportValidationError, match="real provenance"):
        import_translations([pathlib.Path(csv)], write_path=out)


def test_verified_placeholder_is_rejected(tmp_path):
    out = tmp_path / "out.jsonl"
    csv = _one_row_csv(
        tmp_path,
        [["hindi", "santali", "सुप्रभात, बच्चों।", "", "", "greetings", "", "", "sourced",
          "true"]],
    )
    with pytest.raises(ImportValidationError, match="placeholder"):
        import_translations([pathlib.Path(csv)], write_path=out)


def test_placeholders_import_unverified_with_null_target(tmp_path):
    out = tmp_path / "out.jsonl"
    csv = _one_row_csv(
        tmp_path,
        [["hindi", "santali", "सुप्रभात, बच्चों।", "", "", "greetings", "", "",
          "authored-development", "false"]],
    )
    report = import_translations([pathlib.Path(csv)], write_path=out)
    assert report.placeholders == 1
    row = _load_output(out)[0]
    assert row.get("targetText") is None


def test_normalisation_collapses_punctuation_and_case_duplicates(tmp_path):
    out = tmp_path / "out.jsonl"
    csv = _one_row_csv(
        tmp_path,
        [
            ["hindi", "santali", "बच्चों, कितने आम हैं?", "first", "", "questions", "", "",
             "authored-development", "false"],
            ["hindi", "santali", "बच्चों   कितने  आम हैं", "duplicate", "", "questions", "",
             "", "authored-development", "false"],
        ],
    )
    report = import_translations([pathlib.Path(csv)], write_path=out)
    lines = _load_output(out)
    assert len(lines) == 1
    assert report.skipped_duplicate_or_idempotent == 1
    assert lines[0]["targetText"] == "first"


def test_unknown_language_is_rejected(tmp_path):
    out = tmp_path / "out.jsonl"
    csv = _one_row_csv(
        tmp_path,
        [["klingon", "santali", "hello", "world", "", "greetings", "", "",
          "authored-development", "false"]],
    )
    with pytest.raises(ImportValidationError, match="unknown language"):
        import_translations([pathlib.Path(csv)], write_path=out)


def test_unsupported_pair_is_rejected(tmp_path):
    out = tmp_path / "out.jsonl"
    csv = _one_row_csv(
        tmp_path,
        [["english", "santali", "Hello", "world", "", "greetings", "", "",
          "authored-development", "false"]],
    )
    with pytest.raises(ImportValidationError, match="not supported"):
        import_translations([pathlib.Path(csv)], write_path=out)


def test_mundari_is_a_known_but_not_yet_supported_language(tmp_path):
    # Secondary-language readiness: "unr" is recognised so a mistyped code is
    # caught, but the pair is refused because no verified data exists for it.
    out = tmp_path / "out.jsonl"
    csv = _one_row_csv(
        tmp_path,
        [["unr", "santali", "one", "mit'", "", "numbers", "", "",
          "authored-development", "false"]],
    )
    with pytest.raises(ImportValidationError, match="not supported"):
        import_translations([pathlib.Path(csv)], write_path=out)


def test_unknown_category_is_rejected(tmp_path):
    out = tmp_path / "out.jsonl"
    csv = _one_row_csv(
        tmp_path,
        [["hindi", "santali", "एक", "mit'", "", "astrology", "", "",
          "authored-development", "false"]],
    )
    with pytest.raises(ImportValidationError, match="category"):
        import_translations([pathlib.Path(csv)], write_path=out)


def test_blank_source_text_is_rejected(tmp_path):
    out = tmp_path / "out.jsonl"
    csv = _one_row_csv(
        tmp_path,
        [["hindi", "santali", "   ", "mit'", "", "numbers", "", "",
          "authored-development", "false"]],
    )
    with pytest.raises((ImportValidationError, ValueError)):
        import_translations([pathlib.Path(csv)], write_path=out)


def test_reimport_is_idempotent(tmp_path):
    out = tmp_path / "out.jsonl"
    csv = _one_row_csv(
        tmp_path,
        [["hindi", "santali", "एक", "mit'", "मित्", "numbers", "", "",
          "authored-development", "false"]],
    )
    first = import_translations([pathlib.Path(csv)], write_path=out)
    second = import_translations([pathlib.Path(csv)], write_path=out)

    assert first.inserted == 1
    assert second.inserted == 0
    assert second.skipped_duplicate_or_idempotent == 1
    assert len(_load_output(out)) == 1


def test_replace_overwrites_existing_rows(tmp_path):
    out = tmp_path / "out.jsonl"
    csv = _one_row_csv(
        tmp_path,
        [["hindi", "santali", "एक", "old", "", "numbers", "", "",
          "authored-development", "false"]],
    )
    import_translations([pathlib.Path(csv)], write_path=out)

    fixed = _one_row_csv(
        tmp_path,
        [["hindi", "santali", "एक", "corrected", "", "numbers", "", "",
          "authored-development", "false"]],
    )
    import_translations(
        [__import__("pathlib").Path(fixed)], write_path=out, replace=True
    )
    rows = _load_output(out)
    assert len(rows) == 1
    assert rows[0]["targetText"] == "corrected"


def test_json_import_supports_a_translations_list(tmp_path):
    out = tmp_path / "out.jsonl"
    data = tmp_path / "input.json"
    data.write_text(
        json.dumps(
            {
                "translations": [
                    {
                        "sourceLanguage": "hindi",
                        "targetLanguage": "santali",
                        "sourceText": "दो",
                        "targetText": "bar",
                        "spokenText": "बार",
                        "category": "numbers",
                        "provenance": "authored-development",
                        "verified": False,
                    }
                ]
            }
        ),
        encoding="utf-8",
    )
    report = import_translations([data], write_path=out)
    assert report.inserted == 1
    assert _load_output(out)[0]["targetText"] == "bar"


def test_jsonl_import_reads_the_canonical_pack_shape(tmp_path):
    out = tmp_path / "out.jsonl"
    data = tmp_path / "input.jsonl"
    data.write_text(
        "\n".join(
            [
                json.dumps(
                    {
                        "sourceLanguage": "hindi",
                        "targetLanguage": "santali",
                        "sourceText": "दो",
                        "targetText": "bar",
                        "spokenText": "बार",
                        "category": "numbers",
                        "provenance": "authored-development",
                        "verified": False,
                    }
                ),
                # A real sourced record with a non-development provenance is
                # allowed to carry verification.
                json.dumps(
                    {
                        "sourceLanguage": "hindi",
                        "targetLanguage": "santali",
                        "sourceText": "धन्यवाद",
                        "targetText": "Adhniyaw",
                        "provenance": "examinedStandard",
                        "verified": True,
                        "version": 3,
                    }
                ),
            ]
        ),
        encoding="utf-8",
    )
    report = import_translations([data], write_path=out)
    assert report.inserted == 2
    rows = _load_output(out)
    verified = [r for r in rows if r["verified"]]
    assert len(verified) == 1
    assert verified[0]["provenance"] == "examinedStandard"
    assert verified[0]["reviewedBySpeaker"] is True


def test_malformed_json_is_a_clean_validation_error_never_a_crash(tmp_path):
    out = tmp_path / "out.jsonl"
    # Neither a list nor {"translations": [...]} — not a valid input shape.
    data = tmp_path / "input.json"
    data.write_text(json.dumps({"verified": True}), encoding="utf-8")
    with pytest.raises(ImportValidationError):
        import_translations([data], write_path=out)
    assert not out.exists()

    junk = tmp_path / "junk.json"
    junk.write_text("this is not json", encoding="utf-8")
    with pytest.raises(ImportValidationError):
        import_translations([junk], write_path=out)
    assert not out.exists()


def test_any_invalid_row_aborts_the_whole_import(tmp_path):
    out = tmp_path / "out.jsonl"
    csv = _one_row_csv(
        tmp_path,
        [
            ["hindi", "santali", "एक", "mit'", "", "numbers", "", "",
             "authored-development", "false"],
            ["klingon", "santali", "bad", "row", "", "numbers", "", "",
             "authored-development", "false"],
        ],
    )
    with pytest.raises(ImportValidationError):
        import_translations([pathlib.Path(csv)], write_path=out)
    assert not out.exists()  # nothing partial was written


def test_canonical_record_schema_carries_all_phase_two_fields():
    record = TranslationRecord(
        id=build_translation_record_id("hindi", "santali", "एक"),
        source_language="hindi",
        target_language="santali",
        source_text="एक",
        target_text="mit'",
        spoken_text="मित्",
        category="numbers",
        context="counting lesson",
        dialect="santali (Jharkhand)",
        provenance="sourced",
        verified=True,
        version=3,
    )
    payload = record.to_pack_json()
    for key in (
        "id",
        "sourceLanguage",
        "targetLanguage",
        "sourceText",
        "targetText",
        "category",
        "context",
        "dialect",
        "verified",
        "provenance",
        "version",
        "reviewedBySpeaker",
    ):
        assert key in payload
    assert payload["verified"] is True
    assert payload["reviewedBySpeaker"] is True


def test_verified_requires_the_version_to_be_honest():
    from pydantic import ValidationError

    with pytest.raises(ValidationError):
        TranslationRecord(
            id="x",
            source_language="hindi",
            target_language="santali",
            source_text="एक",
            target_text="mit'",
            provenance="sourced",
            verified=True,
            version=0,
        )