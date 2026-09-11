# Data sources, provenance and license

Everything below is recorded so that any row in the processed pipeline can be
traced back to a documented, licensed source. Nothing in this file claims
speaker verification unless the source itself establishes it.

## COILD-MT-Corpus (Hindi ↔ Santali) — BLOCKED, not yet acquired

- **Dataset**: COILD-MT-Corpus
- **Pair**: HIN-SAT (Hindi ↔ Santali)
- **License**: CC BY 4.0 (per the dataset card)
- **Source**: AI-NLP-ML Research Group, IIT Patna, on Hugging Face
  - https://huggingface.co/datasets/ainlpml-iitp/COILD-MT-Corpus
- **Documented size**: 20,603 Hindi–Santali sentence pairs (per dataset card)
- **Access requirement**: **GATED dataset.** Hugging Face answers 401 until the
  account owning the token has accepted the dataset's access terms / agreed to
  share contact information on the dataset page. This access is a hard
  boundary: the acquisition script `scripts/acquire_coild_hin_sat.py` reports
  the gate and **never bypasses it**.
- **Retrieval date**: 2026-08-30 (attempted; answered 401)
- **Files acquired**: none yet (`backend/data/raw/coild_hin_sat/` contains only
  `retrieval.json` and `checksums.sha256` metadata; both raw files are pending
  the project owner's terms acceptance + token: `HF_TOKEN=hf_...`).
- **Preprocessing performed**: none — raw files are not present.
- **Checksums**: not yet obtainable; the script writes a `checksums.sha256`
  sidecar the moment the files are acquired.

### To complete acquisition (project owner action, not bypassable by code)

1. Log into Hugging Face and open the dataset page.
2. Accept the dataset terms / sharing agreement.
3. Re-run, providing the account's token:

   ```
   python -m scripts.acquire_coild_hin_sat --token hf_...
   # or: HF_TOKEN=hf_... python -m scripts.acquire_coild_hin_sat
   ```

   The script then fetches only the two needed files
   (`HIN-SAT/Hindi.txt`, `HIN-SAT/Santali.txt`) — never the ~849 MB repo.

### Official citation (preserved from the dataset card)

> Please cite the COILD dataset if you use it in your work:
>
> @article{coild, ... }

*Note:* the full canonical citation text must be copied verbatim from the
dataset card by the project owner when the terms are accepted; the card's
preprint reference is "COILD: A parallel corpus for low-resource Indic
languages" (IIT Patna AI-NLP-ML group). This placeholder is replaced at
acquisition time — the code never fabricates it.

## IndicTrans2 (model checkpoints) — BLOCKED, not yet evaluated

- **Model**: AI4Bharat IndicTrans2 (Indic-to-Indic / En-Indic)
  - https://github.com/AI4Bharat/IndicTrans2
- **Relevant codes**: `hin_Deva` (source), `sat_Olck` (target)
- **License**: CC-BY-NC (non-commercial) for IndicTrans2 — see the repo; HF
  checkpoints (e.g. `ai4bharat/indic-indic-trans-100M`,
  `ai4bharat/indictrans2-hin-sat-dist-320M`) are **gated** and answered 401 on
  2026-08-30, same boundary as COILD.
- **Status**: adapter seam built; real weights not downloadable here without
  the project owner accepting the model license and providing a token.

## Processing guarantees

- Raw files are never modified by any preparation step: outputs are written to
  `backend/data/processed/hin_sat/` (and `backend/data/generated/`), raw lives
  under `backend/data/raw/` (gitignored).
- Any alignment mismatch between `Hindi.txt` and `Santali.txt` fails loudly in
  `scripts/prepare_hin_sat.py` — the pipeline never truncates one side to make
  the counts match.