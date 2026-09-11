# GyanSetu Backend

A FastAPI + SQLAlchemy + PostgreSQL backend for the offline-first GyanSetu app.
It implements the API and sync contracts the Flutter client declares, so the
app's future HTTP layer can talk to it without a re-write.

The app itself is untouched by this project: it has **no HTTP client yet**, and
all offline behaviour is unaffected.

## Quick start

```sh
python3 -m venv .venv
./.venv/bin/pip install -r requirements.txt
cp .env.example .env        # adjust GYANSETU_DATABASE_URL / SECRET_KEY
./.venv/bin/uvicorn app.main:app --reload
```

Interactive API docs: http://127.0.0.1:8000/docs — health: http://127.0.0.1:8000/health

Default config uses a local SQLite file (zero setup). For PostgreSQL set
`GYANSETU_DATABASE_URL=postgresql+psycopg://user:pass@host/db`.

## Database migrations

```sh
GYANSETU_DATABASE_URL=sqlite:///./gyansetu_dev.db ./.venv/bin/alembic upgrade head
```

`alembic/env.py` reads the same `GYANSETU_DATABASE_URL` variable used at runtime.
Run `alembic revision --autogenerate` after model changes.

## Tests

```sh
./.venv/bin/python -m pytest tests/ -q
```

Every test uses a throwaway SQLite database — nothing touches a developer or
production database.

## API surface (all under `/api/v1`)

| Area | Endpoints |
| --- | --- |
| Auth | `auth/register`, `auth/login`, `auth/verify-school-code`, `auth/recover`, `auth/me`, `auth/logout` |
| Teachers | `teachers` CRUD + `teachers/me` |
| Schools | `schools` CRUD + `schools/by-code/{code}` |
| Catalogue | `lessons`, `learning-outcomes`, `translations` |
| Records | `worksheets`, `assessments`, `sessions`, `progress` (teacher-owned) |
| Sync | `sync/push`, `sync/pull`, `sync/status` |
| Health | `/health`, `/health/db` |

Response bodies use **camelCase** keys to match the Flutter models; enum-like
fields travel as strings (e.g. `"subject": "foundationalLiteracy"`).

## Sync contract

Offline-first flow: the app writes locally, then pushes and pulls in batches.

* **push** — `{deviceId, documents: [{type, id, data}]}`. Documents are
  upserted idempotently by client id. Types: `classroomSetup`,
  `classroomSession`, `assessmentResult`, `worksheet`, `progressEvent`,
  `supportReport`. Response reports per-document `acknowledged`, `conflicts`
  (e.g. an event whose `teacherId` belongs to someone else) and `errors`.
* **pull** — `{since, includeCatalog}` returns every teacher-owned document
  changed after `since`, plus the global catalogue (`lesson`,
  `learningOutcome`) when requested. `since` is the cursor from the last pull,
  so `updatedAt` drives recovery.
* **status** — `{serverTime, counts}` per document type.

## Auth

* Password hashing: PBKDF2-HMAC-SHA256 (stdlib), stored as
  `pbkdf2_sha256$<iters>$<salt>$<hash>`.
* Login tokens: signed JWTs (HS256), 7-day expiry, subject = teacher id.
* Teachers authenticate by mobile or teacher id; an optional `schoolCode` on
  login additionally pins the school.

## Deployment notes

* Set `GYANSETU_ENV=production` — the dev SQLite auto-create workaround and
  default secret are dev-only.
* Generate a real `GYANSETU_SECRET_KEY` and restrict
  `GYANSETU_CORS_ORIGINS` to the app's own origin.

## Known limitations (deliberate)

* **No AI or machine translation.** A `translate` endpoint is not implemented;
  translations are stored and served as content, not generated.
* **PIN recovery is acknowledge-only.** `auth/recover` returns `accepted` but
  there is no SMS/email channel wired up.
* **The Flutter app is not wired to this backend yet.** No HTTP layer has been
  added on the Flutter side; this backend is the server the app's existing
  `ApiEndpoints` and service interfaces target.
* **Offline mode is unchanged** — the app continues to work fully offline.