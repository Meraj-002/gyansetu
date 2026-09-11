"""Reproducibly acquire COILD-MT-Corpus HIN-SAT (Hindi ↔ Santali).

Only the two files this project needs are fetched — never the whole ~849 MB
repository:

    HIN-SAT/Hindi.txt
    HIN-SAT/Santali.txt

License: CC BY 4.0. The dataset lives behind Hugging Face's access gate: it
ships as a "gated" (limited) dataset, so the file server answers 401 until the
account that owns the token has accepted the dataset terms on
https://huggingface.co/datasets/ainlpml-iitp/COILD-MT-Corpus.

This script NEVER bypasses the gate. Without an authenticated token it reports
the exact condition and exits non-zero; with a token whose account has accepted
the terms (via ``HF_TOKEN``/``HUGGING_FACE_HUB_TOKEN`` or ``--token``) it uses
the standard ``Authorization: Bearer`` header the gate itself expects.

Usage::

    python -m scripts.acquire_coild_hin_sat            # reports gating
    HF_TOKEN=hf_... python -m scripts.acquire_coild_hin_sat

Output goes to ``data/raw/coild_hin_sat/`` (gitignored), with a ``checksums.sha256``
sidecar and a ``retrieval.json`` metadata record.
"""

from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

DATASET = "ainlpml-iitp/COILD-MT-Corpus"
REVISION = "main"
RAWFILES = (
    "HIN-SAT/Hindi.txt",
    "HIN-SAT/Santali.txt",
)
BASE_URL = f"https://huggingface.co/datasets/{DATASET}/resolve/{REVISION}/"

DEFAULT_OUT = Path(__file__).resolve().parent.parent / "data" / "raw" / "coild_hin_sat"

GATED_MSG = """\
COILD-MT-Corpus is GATED (limited access): the server answered {status} without
authentication. Hugging Face only releases the files to an account that has
accepted the dataset's terms on:
    https://huggingface.co/datasets/{DATASET}

To continue you must, as the project owner:
  1. create/log into a Hugging Face account,
  2. open that page and accept the dataset terms / agree to share contact info,
  3. provide a token:  HF_TOKEN=hf_...  (or --token / .env GYANSETU_HF_TOKEN).

This script will not bypass the gate. Re-run it with the token once accepted.
"""


def _token(args: argparse.Namespace) -> str | None:
    if args.token:
        return args.token
    for name in ("HUGGING_FACE_HUB_TOKEN", "HF_TOKEN", "GYANSETU_HF_TOKEN"):
        value = os.environ.get(name)
        if value:
            return value
    return None


def _download(path: str, destination: Path, token: str | None) -> tuple[int, str]:
    url = BASE_URL + path
    headers = {"User-Agent": "gyansetu-data-acquire/1.0 (COILD HIN-SAT; CC BY 4.0)"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=120) as response, open(
            destination, "wb"
        ) as out:
            digest = hashlib.sha256()
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                digest.update(chunk)
                out.write(chunk)
            return response.status, digest.hexdigest()
    except urllib.error.HTTPError as error:
        raise AccessGated(error.code) if error.code in (401, 403) else error


class AccessGated(Exception):
    """The dataset refused the request because its terms have not been accepted."""

    def __init__(self, status: int):
        super().__init__(f"gated dataset answered HTTP {status}")
        self.status = status


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Acquire COILD-MT-Corpus HIN-SAT")
    parser.add_argument(
        "--out",
        type=Path,
        default=DEFAULT_OUT,
        help="target directory for the raw files",
    )
    parser.add_argument(
        "--token",
        default=None,
        help="explicit Hugging Face token (else HF_TOKEN / HUGGING_FACE_HUB_TOKEN)",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="re-download even when the files already exist",
    )
    parser.add_argument(
        "--date",
        default=None,
        help="retrieval date override (ISO), for reproducible provenance records",
    )
    args = parser.parse_args(argv)

    token = _token(args)
    out: Path = args.out
    out.mkdir(parents=True, exist_ok=True)
    retrieved_on = args.date or datetime.date.today().isoformat()

    checksums: list[str] = []
    retrieval: dict[str, object] = {
        "dataset": DATASET,
        "revision": REVISION,
        "url_template": BASE_URL + "{path}",
        "license": "CC BY 4.0",
        "retrieved_on": retrieved_on,
    }
    statuses: dict[str, int] = {}

    for path in RAWFILES:
        destination = out / Path(path).name
        if destination.exists() and not args.force:
            print(f"exists, skipping: {destination.name}")
            checksums.append(
                f"{hashlib.sha256(destination.read_bytes()).hexdigest()}  {destination.name}"
            )
            continue
        print(f"fetching: {path} -> {destination.name}")
        try:
            status, digest = _download(path, destination, token)
        except AccessGated as gated:
            print(GATED_MSG.format(status=gated.status, DATASET=DATASET))
            statuses[path] = gated.status
            break
        statuses[path] = status
        checksums.append(f"{digest}  {destination.name}")

    retrieval["statuses"] = statuses
    retrieval["files"] = {Path(p).name: bool((out / Path(p).name).exists()) for p in RAWFILES}

    (out / "retrieval.json").write_text(
        json.dumps(retrieval, indent=2) + "\n", encoding="utf-8"
    )
    if checksums:
        (out / "checksums.sha256").write_text("\n".join(sorted(checksums)) + "\n", encoding="utf-8")

    if any(code in (401, 403) for code in statuses.values()):
        return 3
    if not all(code == 200 for code in statuses.values()):
        return 2
    print("acquired both HIN-SAT files.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())