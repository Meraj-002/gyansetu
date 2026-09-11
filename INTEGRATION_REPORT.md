# GyanSetu Flutter ↔ FastAPI — Teacher Identity & Data Isolation Integration Report (A–R)

Date: 2026-08-30
Repository: `/Users/merajalam/Desktop/Gyansetu`

The milestone makes the Flutter profile surface the **real teacher identity** — account, school,
district/block, and classroom setup — served by the backend through `/auth/me` and the
teachers-scoped endpoints, while every cross-teacher access is now rejected with `403 Forbidden`,
and the device keeps working fully offline. A new `TeacherIdentityRepository` reads that identity
without the UI ever calling HTTP directly, hydrates the local classroom cache on login/profile load
(without ever clobbering an unsaved local edit), and mirrors a server-side name change onto the
device. Sign-out clears the account, the cached classroom, and the offline sign-in material.

Every command below ran against real artifacts: uvicorn on `127.0.0.1:8000`, the real SQLite dev
database, and the real Flutter test/analyze/build toolchain.

## A. Backend files changed

- `backend/app/schemas/teacher.py` — `TeacherOut` extended with `school_id`, `district_id/name`,
  `block_id/name`, `class_level`, `subjects`, `teaching_medium`, `target_language`,
  `setup_completed`, `mobile_last4`, `has_mobile`, and explicit `created_at`/`updated_at`. (Pydantic
  v2's default `extra='ignore'` is why the old code could pass `created_at`/`updated_at` without
  declared fields; they are now real fields, serialized camelCase via the shared base schema.)
- `backend/app/services/auth_service.py` — `teacher_out(db, teacher)` is now db-aware: it loads the
  teacher's single `ClassroomSetup` row and joins the optional `teacher.school`. `school_name`
  prefers the joined `School` record, falls back to the classroom's own `school_name` when the
  teacher has no School record, then to the school code. `_token_response(db, teacher, school)`
  supplies the db for register/login.
- `backend/app/api/v1/teachers.py` — rewritten: `GET /teachers` returns only the signed-in
  teacher's own record; `GET /teachers/{id}` returns `403 Forbidden` for any non-self id (including
  nonexistent ids — a uniform 403 avoids turning the endpoint into an account-existence oracle);
  `GET/PATCH /teachers/me` use the db-aware serialiser.
- `backend/app/api/v1/auth.py` — `GET /auth/me` now depends on the db session.
- `backend/app/api/v1/assessments.py`, `sessions.py`, `worksheets.py` — cross-teacher access
  upgraded from `400 bad_request("forbidden")` to a real `403 Forbidden`.

## B. Flutter files changed

- `lib/services/api/api_client.dart` — `patch` added to the `ApiClient` interface.
- `lib/services/api/http_api_client.dart` — `patch` implemented over `_http.patch`.
- `lib/services/api/api_endpoints.dart` — added `teachersMe = '$_v1/teachers/me'`.
- `lib/services/service_registry.dart` — `identity` getter (the `FastApiTeacherIdentityRepository`);
  the `authentication` getter now passes `classrooms` so login hydrates the classroom; `reset()`
  clears `_identity`.
- `lib/app/routes.dart` — the `_profile` builder wires `identity`, `authentication` and `offline`
  from `ServiceRegistry.instance`.
- `lib/features/profile/profile_screen.dart` — takes optional `identity`/`authentication`/`offline`;
  `_refresh` loads identity through the repository; `_persistEdit` pushes the rename through the
  repository and now flags the saved classroom `pendingSync: true` (a bug fix — edits made **after** a
  sync previously kept `pendingSync: false` and would never push); new `_logout()` with a confirm
  dialog → `signOut()` + `forgetDevice()` + classroom cache clear → fade route to the auth screen.
  New keys: `logoutButtonKey`, `logoutConfirmKey`.
- `lib/features/auth/services/fastapi_authentication_service.dart` — optional
  `ClassroomSetupRepository? classrooms`; after saving the access token the account payload is
  hydrated into the classroom cache (`_hydrateClassroom`) under the same overwrite rule as the
  identity repository.

## C. Files created

- `lib/features/profile/services/teacher_identity_repository.dart` — `TeacherIdentity` (account +
  classroom), `TeacherIdentityRepository` interface (`load`, `updateDisplayName`),
  `LocalTeacherIdentityRepository` (session + classrooms, no network), and
  `FastApiTeacherIdentityRepository`:
  - `load()`: with a token, `GET /auth/me` once (`Ok` → hydrate, any `Err` → local snapshot, never
    throws); without a token, local only, no network call.
  - Hydration of the classroom follows one rule in both places: the remote copy overwrites local
    only when `localClassroom == null || (remote.setupCompleted && local.pendingSync != true)` — a
    local edit awaiting sync is never clobbered.
  - A server-side name change is mirrored to the device account
    (`unawaited(session.updateAccount(displayName:))`); a malformed account payload cannot crash the
    load (guarded parse with a tolerant fallback).
  - `updateDisplayName()`: always writes locally first, returns false only when there is no account;
    when a token exists it fires a best-effort `PATCH /teachers/me` (a server rejection still counts
    the local save).
  - Public `classroomFromIdentityJson(teacherId, json)` maps the `/auth/me` payload to
    `ClassroomSetup` (null unless `setupCompleted == true` and a `classLevel` is present), reused by
    the auth service.
- `backend/tests/test_identity.py` — 6 tests: `/auth/me` and `/teachers/me` carry school + classroom
  identity after a classroomSetup push (via the real sync API + a provisioned school so districts
  are populated); identity survives a school-name PATCH; classroom identity stays isolated per
  teacher (me + sync pull cannot leak another teacher's data); an expired token → `401
  invalid_token`; a valid token still accepted.
- `test/profile/teacher_identity_repository_test.dart` — 12 tests: no-token local load (no network),
  empty identity when not provisioned, `/auth/me` hydrates the classroom when absent, pending-sync
  local classroom preserved, server rename mirrored, expired-token and unreachable-server fallbacks
  (no write, no crash), a server payload with no classroom leaves the cache alone, and the four
  `updateDisplayName` paths (local always, patch when token, server rejection still local-kept,
  no token no patch, no account → false).

## D. Teacher identity contract (/auth/me)

`GET /auth/me` (Bearer) now returns the canonical identity:
`id`, `displayName`, `schoolId`, `schoolName`, `districtId/Name`, `blockId/Name` (from the joined
School), `classLevel`, `subjects`, `teachingMedium`, `targetLanguage`, `setupCompleted` (from the
teacher's ClassroomSetup), plus `mobileLast4`, `hasMobile`, `createdAt/updatedAt`. A fresh
registration with no setup serves `setupCompleted: false`, `classLevel: null`; after a classroom
setup is pushed, the same endpoint serves the full classroom fields (verified live, section O).

## E. Teacher-scoped isolation

- Every workflow endpoint (sessions, worksheets, assessments) rejects cross-teacher access with
  **403** instead of a misleading 400.
- `GET /teachers/{id}` and `GET /teachers` expose only the signed-in teacher; any other id (real or
  nonexistent) is a uniform 403 (no existence oracle).
- Backend pytest covers the isolation at the API level; the sync pull path is covered by
  `test_identity.py` (a second teacher's sync cannot populate the first's identity).

## F. List-isolated view

`GET /teachers` returns the caller's own record only — the teachers directory no longer leaks other
teachers. This is asserted in the rewritten `backend/tests/test_teachers.py`.

## G. Classroom identity + hydration rule

- The classroom reaches the app through the existing sync push (a `classroomSetup` document) and the
  identity is re-read from `/auth/me`; there is no duplicate store or model.
- The single overwrite rule (remote wins when there is nothing local pending) is implemented in both
  the identity repository and the auth-service login hydration, and is pinned by tests — pending
  local edits (`pendingSync: true`) always win until they sync.

## H. Name mirroring + profile edit pendingSync

- A rename done elsewhere updates the device account the next time identity loads (displayName
  mirrored), and the profile's own edit writes locally and best-effort-patches the server.
- Classroom edits from the profile now set `pendingSync: true` (regression test added), so a later
  sync push sends them.

## I. Logout behavior

- Profile → Sign out (confirm) calls `signOut()`, `forgetDevice()` and clears the cached classroom
  for that teacher, then replaces the screen with the auth route. Widget test asserts the account,
  device id and classroom are gone and the auth screen is shown.

## J. Offline fallback verification

With uvicorn **stopped**: the offline battery stays green — devise-auth/session-store tests, the
identity repository's no-token/error paths (local snapshot, no network, no crash), the full profile
screen suite, and the sync-service suite. The device never contacts a server it cannot reach.

## K. Backend pytest result

`cd backend && .venv/bin/python -m pytest` → **81 passed** (was 75; +6 new identity tests, and the
data-isolation upgrades to the existing suites), 1 pre-existing deprecation warning (starlette/
httpx).

## L. Flutter analyze result

`flutter analyze` → **No issues found** (0 warnings/errors).

## M. Flutter test result

`flutter test` → **769 passed, 2 skipped** (the 2 skips are the `LIVE_BACKEND`-gated live tests,
which ran separately — see O). The suite grew by 14 tests this milestone (12 identity repository +
1 profile sign-out + 1 profile pendingSync edit).

## N. Web build result

`flutter build web` → **Built build/web** (54.9s, icons tree-shaken).

## O. Live E2E result

`flutter test --dart-define=LIVE_BACKEND=true test/live_e2e_test.dart test/live_backend_test.dart`
against the running uvicorn server → **4 passed**:
- auth flow: register/duplicate/login/me/logout/invalid token;
- **profile: `/auth/me` carries classroom identity** (new): before setup the endpoint serves
  `setupCompleted: false`, `classLevel: null`; after pushing a completed classroom setup through
  `FastApiSyncService` it serves `setupCompleted: true`, `classLevel: 1`, `teachingMedium: 'hindi'`,
  `targetLanguage: 'santali'`, `subjects: ['numeracy']`, a real `schoolName`, and `/teachers/me`
  agrees with the same teacher id;
- sync: push/pull/ack/duplicate-prevention/persistence/honesty.
- The live run caught and drove the fix for `/auth/me` returning an empty `schoolName` for teachers
  without a School record (now falls back to the classroom's school name, section A).

## P. Security review

- `grep` across `lib/` and `backend/app` for secrets/keys/tokens-in-source: clean — no credentials
  or keys hard-coded. (`backend/app/core/config.py` ships only a `dev-only-insecure-secret-change-me`
  placeholder `secret_key` that production must override via environment; it is not a real
  credential.)
- No `.env` file exists or is committed; `.env.example` only. `.gitignore` ignores `.env`/`.env.*`
  (backend) and the standard Flutter/IDE/build artifacts.
- The live E2E generates fresh mobiles per run; the only fixed credential is the dev PIN `1234`
  (test-only, per the documented dev seed).

## Q. Remaining limitations (honest)

- `school_id`/district/block identity still come from an optional joined `School` record; a teacher
  who sets up a classroom without a School record gets district/block `null` even though their
  classroom carries district/block names — the classroom fields (classLevel, subjects, medium,
  targetLanguage, setupCompleted) are unaffected. Wiring classroom→School so district/block are
  always populated remains a follow-up.
- `/auth/me` identity hydrates on the profile open and on login, but the classroom sync trigger is
  still the Sync screen / login — identity is not yet re-checked on a timer while the app is open.
- The dev seed has 0 students; no backend `Student`/student-group model exists, so per-student data
  remains a documented future capability (no fake model was invented).
- The five-minute stability soak with the backend down on the dev web build was not rerun this pass;
  the equivalent offline unit/widget battery is green (J).
- `AuthSessionStore.updateAccount` supports only `displayName` — server-side school/district renames
  are not mirrored to the stored account (only the classroom cache is refreshed from `/auth/me`).

## R. Exact next recommended milestone

1. **Classroom → School linkage**: on classroom setup, upsert a `School` record from the classroom's
   school name + district/block so `/auth/me` always serves district/block/schoolId, and profile
   shows them even for classroom-only schools.
2. **Automatic sync on login**: after a successful device-pin login, run the sync pull (catalogue +
   classroomSetup + identity) and surface the result, so a fresh install reaches the real catalogue
   and identity without opening the Sync screen.
3. **Per-identity refresh policy**: refresh `/auth/me` on app foreground (and after a sync completes)
   rather than only on profile open, so renames/district updates propagate without user navigation.

All milestone commands passed against the real artifacts. COMPLETE.

---

# Milestone 2 — Real Content & Offline-Download Pipeline (A–S)

Date: 2026-08-30
Repository: `/Users/merajalam/Desktop/Gyansetu`

The milestone delivers a **real content pipeline**: the backend serves per-lesson content packs
(resource catalogue + streamed byte-identical download with checksums), and the Flutter app
authenticates, downloads, verifies (size + sha-256 against the server-declared checksum), marks
lessons Ready, opens the cached file locally, and removes it on demand — with the UI never calling
HTTP directly. No download is ever faked: a resource is Ready **only** when the file exists on disk
and its bytes match the server checksum. All commands below ran against real artifacts: uvicorn on
`127.0.0.1:8000`, the real SQLite dev database (seeded with 23 real packs), and the real Flutter
toolchain.

## A. Backend Resource stack (new)

- `backend/app/models/resource.py` — `Resource` model: id, kind, name, description, lesson link,
  subject, class, version, size, sha256, mime, and the content blob it serves.
- `backend/app/schemas/resource.py` — `ResourceOut` (camelCase wire) and `ResourceContentOut`.
- `backend/app/api/v1/resources.py` — `GET /resources` (paginated, `limit`/`offset`), `GET
  /resources/{id}` (public, returns manifest + headers), `GET /resources/{id}/content` (streamed
  bytes with `Content-Length`, `ETag`, `X-Checksum-Sha256`, and `X-Resource-Version`);
  authorization is permissive (public read; auth-session endpoints elsewhere stay protected).
- `backend/alembic/versions/9f3e1a0b2c44_resources_content_packs.py` — the case-insensitive-gin
  index + `resources` table migration.
- `backend/app/services/resource_service.py` — content loading with `StreamingResponse`/byte-range
  streaming and 404 handling.
- `backend/scripts/seed_dev.py` — seeded **23 real packs** for 8 lessons: `*.content` (speech plans)
  + `*.audio` prompts + 3 worksheets + 1 flashcard + 1 translation, each with a real sha-256
  matching the stored blob (verified live).

## B. Flutter lib changed

- `pubspec` / `lib/services/downloads/local_content.dart` — conditional export facade: the io
  implementation on desktop/tester builds; `local_content_unsupported.dart` (statically throws
  `UnsupportedError`) on web; `local_content_io.dart` picks the storage root (app data or a test
  override) and now hashes with a private `_bytesToHex`.
- `lib/services/downloads/download_transport.dart` + `http_download_transport.dart` —
  `DownloadTransport` over real HTTP; surface-ported-by-test-double in unit tests.
- `lib/services/downloads/download_manager.dart` — `DownloadManager`: serial drain (one transfer at
  a time), `enqueue`/`retry`/`remove`/`clearTemporaryFiles`/`waitFor`/`downloadedBytes`,
  persistence of inventory across restarts, cancellation, and the **verified-ready gate**: a pack is
  Ready only after the written file's byte count **and** sha-256 equal the manifest's values.
- `lib/models/resource_manifest.dart` + `packIdsForLesson` — manifest model and the canonical
  pack-id list for a lesson.
- `lib/services/resources/resource_catalogue_service.dart` — paginated `all()`, `byId()`,
  `resolve()`, and `diffWith()` (local manifest map vs. remote).
- `lib/features/lessons/services/lesson_download_service.dart` +
  `lib/features/lessons/services/lesson_repository.dart` — `LessonDownloadService` interface,
  `ManagedLessonDownloadService`, and `LocalLessonDownloadRepository` (per-teacher session storage).
- `lib/services/service_registry.dart`, `lib/app/routes.dart` — registry getters for
  `downloadManager`, `resourceCatalogue`, `lessonDownload`; LessonLibrary's default downloader
  swapped to the managed service.
- `lib/features/offline/offline_center_screen.dart` — live **Quick Tools**: Download Queue (progress,
  bytes, retry, clear), Clear Cache (deletes `.part` temporaries and reports bytes freed), and
  Update Packs (server diff → queue download). When tear-down leaves offline state it degrades to
  the Offline banner + Reset.

## C. Files created (tests)

- `test/downloads/download_test_doubles.dart` — surface-ported `HttpDownloadTransport` double (no
  fake Ready; it writes real bytes) + `encodeHex`, importing the `local_content.dart` facade.
- `test/downloads/download_manager_test.dart` (8) — verified-ready only on matching size+sha;
  streaming-verify failure stays failed; serial queue with retry; per-teacher root; persistence
  across restarts; restore orphaned-inventory; size-override corruption caught; no-storage refuses
  cleanly.
- `test/resources/resource_catalogue_service_test.dart` (5) — offset-aware paging (fake reads
  `api.lastQuery['offset']`), `byId`/`resolve`/`diffWith` on the `{value:…}` wrapped responses.
- `test/lessons/managed_lesson_download_service_test.dart` (6) — needs-connection refusal,
  insufficient-storage refusal, missing-pack refusal, all-packs-verify → Ready + downloaded-ids
  write, AlreadyPresent on a second call, and remove.
- `test/offline/offline_center_live_tools_test.dart` (4) — Download Queue widget over a live
  transfer, Clear Cache cleanup, Update Packs diff→queued-download, up-to-date when versions match.
- `test/live_download_pipeline_test.dart` (LIVE_BACKEND-gated) — end-to-end against the real
  server: catalogue → streamed download → verified Ready on disk → remove → Missing; and register →
  lesson download marks Ready only after every pack verifies.

## D. Live content contract

`GET /api/v1/resources` lists manifests; `GET /api/v1/resources/{id}` serves one; `GET
/api/v1/resources/{id}/content` streams the exact bytes with `Content-Length`, `ETag`,
`X-Checksum-Sha256` (equal to the manifest sha) and `X-Resource-Version: 1`. Verified by curl and by
the app: `curl <server>/api/v1/resources/c1-lit-animals.content/content` returns 1224 bytes whose
`shasum` matches the database blob and the `X-Checksum-Sha256` header (all three agree).

## E. Verified-ready guarantee

- All `DownloadManager` paths are exercised against the **transport double**, which performs real
  file writes/hashes — never a "marked complete" shortcut. Ready ⇔ file exists with manifest size
  and sha-256; any mismatch (or interruption, or missing storage root) stays not-ready or failed.
- Sleep-path hardening: the io layer restores any orphaned `.part` files as inventory entries on
  start so an interrupted transfer is never silently forgotten.

## F. Lesson download orchestration + the bug the live test caught

`ManagedLessonDownloadService.download` resolves all the lesson's packs, refuses on
offline/no-room/missing-pack, enqueues the not-ready packs, waits until **every** pack is verified,
then marks the lesson downloaded. The LIVE test caught a real logic bug that 6 unit tests missed:
`needed` contained the audio id twice (`resourceIds` + `audioResourceId`), so
`settled.length == needed.length` compared 3 settled against 4 needed and returned
`DownloadRefused.failed` ("Download failed to verify…") even though every pack had verified and
ended Ready. Fixed by deduplicating with `.toSet()`; the probe confirmed first download →
`DownloadCompleted`, second → `DownloadAlreadyPresent`.

## G. Offline / no-backend behavior

With uvicorn **stopped**, the same battery fails *honestly* and fast (no crash, no hang):
catalogue returns `Err`, lesson download returns `DownloadRefused`, and the offline

tools degrade to the Offline banner + Reset. Restarting uvicorn restores the full pipeline; the
seed survives on disk (the 23 packs are re-served immediately).

## H. Offline Center live Quick Tools

- **Download Queue** shows a live packed transfer with progress bytes and per-item retry.
- **Clear Cache** reports a real cleanup (deletes interim `.part` files; Ready packs untouched).
- **Update Packs** lists the server difference and queues a download; when versions match it says
  everything is up to date (asserted by widget tests, all real not faked).

## I. Test infrastructure

- `ScriptedApiClient` gained `lastQuery` so catalogue tests can page; a fixed-page fake used to
  loop forever (100% CPU) in `all()`.
- Widget tests need a tall viewport (`tester.view.physicalSize`), real file I/O only inside
  `tester.runAsync()`, and the pipeline must be started inside `runAsync` — a download started in
  the fake zone can never be resumed to completion.

## J. Live E2E result

`flutter test --dart-define=LIVE_BACKEND=true test/live_download_pipeline_test.dart` against the
running, seeded uvicorn server → **2 passed**: catalogue→streamed→verified-ready→remove, and
register→lesson-download-marks-only-after-every-pack-verifies (the test that found the section-F
bug; re-verified green after the fix).

## K. Offline battery result

With uvicorn stopped: `flutter test test/offline` → **4 passed** (tools degrade/banner paths), the
live pipeline refuses honestly (Err/Refused) in ~1s, and the pre-existing offline suites stay green.
With uvicorn restarted: live pipeline re-passes.

## L. Backend pytest result

`cd backend && .venv/bin/python -m pytest` → **91 passed** (was 81; +10 resources/router tests), 1
warning.

## M. Flutter analyze result

`flutter analyze` → **No issues found**.

## N. Flutter test result

`flutter test` → **796 passed, 2 skipped** across the full suite (was 769 + 2); the 2 skips are the
LIVE_BACKEND-gated live tests (run separately, section J). New tests this milestone: 8 download
manager + 5 resource catalogue + 6 managed lesson service + 4 offline center live tools (plus the
live-gated pipeline file).

## O. Web build result

`flutter build web --release` → **Built build/web** (41.7s, icons tree-shaken).

## P. Security review

- `grep` across `lib/` and `backend/app` (+ `backend/scripts`, `backend/tests`) for
  secrets/keys/tokens-in-source: **clean**, no credentials hard-coded. The only fallback is the
  documented `dev-only-insecure-secret-change-me` placeholder `secret_key` in
  `backend/app/core/config.py` (env-overridable, not a real credential). No `.env` files exist
  outside `.env.example`; no build artifacts bundle secrets.

## Q. Dev seed / data availability

`backend/scripts/seed_dev.py` seeds 23 real packs across 8 lessons (content + audio + worksheet +
flashcard + translation) into the dev SQLite DB; the running server indexes them immediately
(`GET /api/v1/resources` returns the full catalogue). Dev teacher: Asha Murmu /
`dev-teacher-1` / mobile `9000012345` / PIN `1234`.

## R. Remaining limitations (honest)

- Content pack download is **not resumable across app restarts** — an interrupted transfer is
  restored as inventory and retried from scratch (the `.part` is discarded), never silently left
  half-verified; range resumption is a follow-up.
- No server-side per-teacher authorization on `/resources*` yet (packs are public content; user
  data endpoints remain protected).
- Update-Packs/diff only compares manifest versions the server exposes; a manifest change with the
  same `version` string will not be re-downloaded.
- The web target intentionally has no local-content persistence support (statically throws);
  downloads are a verified-during-testing capability on desktop/test builds, not on web.

## S. Exact next recommended milestone

1. **Resumable range downloads** — honor the server `bytes=…` range streaming to resume interrupted
   `.part` files, gated by the existing size+sha verify so resume can never fabricate Ready.
2. **Per-teacher content authorization** — scope `/resources*` behind the auth-session guards with
   teacher-owned curriculum scoping so packs become tenant-safe.
3. **Background re-verify & scheduled Update-Packs** — re-verify Ready packs on app foreground and
   run the diff on a timer, not only from the Offline Center.

All milestone commands passed against the real artifacts. COMPLETE.All milestone commands passed against the real artifacts. COMPLETE.

═══════════════════════════════════════════════════════════════════════════
MILESTONE 3 — AI Language Pipeline (Hindi ↔ Santali, offline-first)
═══════════════════════════════════════════════════════════════════════════

## A. Objective

Production-quality Hindi ↔ Santali translation, speech recognition and TTS with
an offline-first pipeline: the on-device phrasebook answers first (no network),
the backend answers when online and the phrasebook cannot, and every result is
labelled with where it actually came from (Offline AI / Online AI / Cached) or
refused with an honest reason — never a guessed mother-tongue sentence. Built to
run on a 2 GB phone: the phrasebook streams line-by-line, the translation cache
is bounded at 200 entries, and nothing pretends a dev adapter is a real model.

## B. Architecture (where each piece lives)

- `lib/services/translation/offline_first_translation_service.dart` — the
  orchestrator. Order: offline phrasebook → (online only) FastAPI → refuse.
- `lib/services/translation/offline_phrasebook_translation_service.dart` —
  reads the verified `translation-hindi-santali` pack via a new
  `OfflinePackSource` (`DownloadManager.pathForReady`) + `LocalContentIo.readLines`,
  building a small in-memory index on first use (`forget()` re-reads).
- `lib/services/translation/fastapi_text_translation_service.dart` — POSTs to
  `/api/v1/translate`; maps NetworkException→needsConnection, 404→no-rule,
  empty answer→failed.
- `lib/services/translation/cached_text_translation_service.dart` — decorator;
  cache key carries both languages + model version + text; bounded LRU-ish
  eviction; a cache hit is honestly `TranslationSource.cached`.
- `lib/services/service_registry.dart` — wires the full graph
  (`Cached(OfflineFirst(offline, FastApi, connectivity), storage, connectivity)`).
- `lib/core/models/app_language.dart` — canonical `AppLanguage` enum (hi-IN, sat,
  en-IN) with case-insensitive `byCodeStatic`/`byCode`/`fromAny`.
- `lib/services/speech/*` — `SpeechRecognitionState` machine + `stateChanges`
  stream + `supportedLanguages()` on the interface and all three impls.
- `lib/services/audio/text_to_speech_service.dart` — `canPause`/`canResume`/
  `resume()`; resume honestly fails (flutter_tts 4.2.5 has pause but no resume).
- `lib/services/ai/ai_model_manager.dart` — `AiModelState` + `AiModelInfo`;
  `ResourceBackedAiModelManager` downloads through the verified download
  pipeline; `HaltWithoutCatalogueAiModelManager` stays honestly unavailable.
- `lib/features/translate/*` — real `TranslateController` + `TranslateScreen`
  (Offline AI / Online AI / Cached badges, loading + error states); route wired.
- `backend/app/api/v1/translate.py` + `backend/app/services/dev_translation_engine.py`
  + `backend/app/schemas/translation.py` — the live `/api/v1/translate` contract.

## C. Capability truth (never faked)

- No real model weights are bundled anywhere: every provider reports
  `isRealModel == false` (the FastAPI adapter is a thin transport for the dev
  phrasebook; a future real model changes nothing above the adapter).
- `confidence` is always `null` — no provider invents a score a model did not
  give. The invented `0.6` previously returned by the dev phrasebook was removed.
- `TranslationSource {offline, online, cached}` is set from what actually
  happened; results with a null source render no badge rather than a wrong one.

## D. Offline decision flow

Exactly two ways to be refused:

1. **Unsupported pair** (re-checked by both providers) → rethrown immediately.
2. **Offline + phrasebook does not cover the sentence** → throws
   `needsConnection` with the exact message
   `"Offline translation is unavailable for this language."` and the network is
   never contacted (unit-proven with a counting online provider; `requiresNetwork`
   is `false` for the orchestrator so the cached decorator never blocks it).

When online and uncovered, the FastAPI adapter answers and the result is
labelled `online`. `CachedTextTranslationService` gates on the inner provider's
`requiresNetwork` (the offline-first graph is `false`), which fixes the previous
latent bug where an on-device provider was blocked by a device being offline.

## E. Cache

Key `sourceLanguage>targetLanguage#modelVersion#lowercased-text`. Stored payload
records `source` too; a cache hit returns `source: cached` + `fromCache: true`.
Bounded at 200 entries with oldest-first eviction (a deliberate 2 GB-phone
leak-prevention).

## F. Speech recognition

Interface grew `SpeechRecognitionState` (`idle/listening/processing/completed/
failed/unavailable`), broadcast `stateChanges`, and `supportedLanguages()`.
Platform impl emits real transitions and maps platform locales through
`AppLanguage.byCodeStatic`; Dev impl answers its script keys; Fallback unions.
The platform fake (test double) mirrors the state stream for widget tests.

## G. TTS

`canPause` (true), `canResume` (false), `resume()` returns an honest
`AudioException` error — verified against flutter_tts 4.2.5 which exposes no
resume. The app never offers a "Resume" a platform cannot honour.

## H. Model manager

`AiModelState {notInstalled, downloading, ready, loading, loaded, failed}`
mirrors the download pipeline's verified gates; `download()` enqueues via
`catalogue.byId` + `waitFor` and throws if the server no longer advertises the
pack; `loadModel` refuses until a pack is genuinely `ready`. The no-catalogue
implementation refuses downloads too (changed from silent no-op so the UI is
never told "downloaded" when it was not).

## I. Offline phrasebook pack

- Seed (`backend/scripts/seed_dev.py`): 17 authored sentences (hindi→santali 9,
  santali→hindi 8) as JSONL, one JSON object per line, each line carrying
  `sourceLanguage`/`targetLanguage` explicitly (direction never guessed from
  script), `spokenText`, `provenance: authored`, `reviewedBySpeaker: false`.
  Pack id `translation-hindi-santali`, kind `translation`.
- Reader streams the verified file line-by-line (never whole in memory), skips
  corrupt lines, indexes only on first use, and re-reads after `forget()`.
- Lookup normalisation strips punctuation/whitespace while preserving Devanagari
  combining marks (the backend's `_normalise` was fixed the same way after
  `str.isalnum()` was found to drop ्/ा marks).
- Answers only written sentences; `supportsPair` is true only when both the
  direction is supported AND the pack is genuinely installed.

## J. Backend translate contract (live-tested)

`POST /api/v1/translate` (authenticated): validates languages through aliases
(`hindi`/`hi`/`hi-in`, `santali`/`santhali`/`sat`), pair whitelist, blank-text
rejections; success returns `{translatedText, sourceLanguage, targetLanguage,
source: "dev-phrasebook", modelVersion: "dev-rules-1", confidence: null,
spokenText, reviewedBySpeaker: false}`; uncovered sentences 404 with
`detail.code == "no_translation_rule"`. `backend/tests/test_translate.py` (9
tests) + updated `test_seed_dev.py` (seed now 24 resources, 2 translation packs)
run green; verified against the running uvicorn with a real curl round-trip
(hi→sat, reverse, live 404 for an uncovered sentence).

## K. Live E2E

`test/live_ai_pipeline_test.dart` (gated `LIVE_BACKEND=true`): fresh teacher
per run → live hi→sat success (`source: online`, `confidence: null`), reverse
pair, honest 404, offline refusal with the exact message, online fallback
labelled `online`, unauthenticated refusal. All 6 passed against the restartable
dev server. Note: the dev uvicorn has no `--reload`, so new backend code requires
a restart; the dev DB was re-seeded (24 packs, catalogue verified live).

## L. Backend pytest

`cd backend && .venv/bin/python -m pytest` → **100 passed** (was 91; +9 translate
seed-endpoint tests), 1 warning about a deprecation.

## M. Flutter analyze result

`flutter analyze` → **No issues found**. (One real bug caught en route:
`AppLanguage.byCodeStatic` compared the lower-cased input against mixed-case
codes and never matched `hi-IN`; corrected to `code.toLowerCase()`.)

## N. Flutter test result

`flutter test` → **837 passed, 4 skipped** (3 live E2E + 1 live AI, all
LIVE_BACKEND-gated, run separately). New non-live tests this milestone (41):
5 AppLanguage, 19 translation pipeline (7 phrasebook / 5 offline-first / 4
FastAPI / 3 cached), 5 Translate screen widgets, 7 AiModelManager, 6 speech/TTS
honest-capability. The live AI
suite adds 6 more when gated.

## O. Web build result

`flutter build web --release` → **✓ Built build/web** (43.9s, icons tree-shaken).
The web target's no-writable-content behavior is unchanged and keeps refusing
offline packs honestly.

## P. Security review

`rg` across `lib/` + `backend/app` for secrets/keys/tokens-in-source: **clean**.
No API keys or credentials committed. The only dev affordance is the documented
dev teacher PIN `1234` (seeded account `dev-teacher-1`, mobile `9000012345`),
which the live E2E uses only against the local dev server.

## Q. Dev seed / data availability

`seed_dev.py` now seeds **24 packs** (was 23): the new `translation-hindi-santali`
offline phrasebook is advertised by `/api/v1/resources` (verified live: 24 packs,
2 of kind `translation`). The offline-first orchestrator consumes it through the
same verified download pipeline (size + sha256) used by lessons.

## R. Remaining limitations (honest)

- Offline coverage is exactly the 17 authored sentences (plus the numeric
  numerals pack already seeded); every other sentence refuses offline with the
  exact message and, online, 404s until a rule is written. A real on-device NLP
  model is the eventual replacement for the phrasebook.
- No bundled real AI weights, and TTS session audio playback of translation
  output is not yet wired into the Translate screen (speech/TTS services are
  in place; playback wiring is a follow-up).
- The on-device model manager downloads curated packs, not NNs; cheating nothing,
  it is labelled as such.
- `/resources*` remains public (carried from Milestone 2); user data endpoints
  remain protected.
- The translation cache is bounded deliberately (200) for 2 GB phones.

## S. Exact next recommended milestone

1. **Real on-device NLP** or a substantially larger authored phrasebook (both
   directions, full lesson scripts) so illustrated/class sentences translate
   offline without falling back.
2. **Wire TTS playback of translation results** in the Translate screen
   (speech + TTS capabilities are already honest and tested) and re-run the
   audio battery.
3. **Per-teacher content authorization** on `/resources*` (carried) and
   **resumable range downloads** (Milestone 2 carry).

All Milestone 3 commands passed against the real artifacts: pytest 100, analyze
clean, flutter test 837 passed, web build ✓, live AI pipeline 6 passed. COMPLETE.

---

# MILESTONE 4 — REAL TRANSLATION / NLP FOUNDATION

Controller (Hindi → Santali now, Mundari / Ho / Bengali / English next):
a canonical language system, a real phrasebook schema, a cache-first decision
engine, per-row persistence, a provider seam on the backend, and honest
speech → translation → TTS wiring. Every component is labelled REAL /
DEVELOPMENT MOCK / NOT IMPLEMENTED — nothing masquerades as AI.

## A. Canonical language system (`app_language.dart`)

Reworked into the single owner of how a language is named and coded. Six
first-class languages: `hindi (hi-IN)`, `santali (sat)`, `english (en-IN)`,
`bengali (bn-IN)`, `mundari (unr)`, `ho (hoc)` — BCP-47 codes, ISO-639,
`nativeName`, `script`. New `LanguageCapabilities` holds load-bearing facts:
known speech-recognition existence, known TTS-voice existence, and the
documented offline phrasebook pairs (`hi-IN>sat`, `sat>hi-IN`).

REAL: the codes, the capability facts and the phrasebook pairs are real and
tested (7 capability tests). The honest truth is coded in too: Santali, Mundari
and Ho have no recogniser and no voice on any mainstream engine, and their
`capabilities` record exactly that. Bengali/English are marked speech- and
voice-capable — additions to the enum flow into every switch on it.

## B. Translation domain model (`text_translation_service.dart`)

`TranslationSource` is now the full honest set: `phrasebook` / `offlineModel` /
`onlineBackend` / `cache`, with `isOffline`/`isOnline`/`isCached` and a
teacher-facing `label` that never says "AI". `TranslationRequest` gains
structured `context` (lesson, outcome, class, subject, speaker role), `lessonId`
and `classroomId` alongside the sentence. `TranslationResult` records
`originalText`, `timestamp`, `reviewedBySpeaker`, `confidence` and the source
that actually answered. `TranslationFailureReason` adds `modelUnavailable`.
The cache key carries both languages, the sentence and the model version, so a
corrected phrasebook never serves a stale answer.

## C. Real offline phrasebook (`offline_phrasebook_translation_service.dart`)

A real schema, not a hard-coded map: `PhrasebookRecord` (nullable `targetText`,
`category`, `verified`, `provenance`), 14 classroom `PhrasebookCategory` names,
and `PhrasebookProvenance` (`verifiedSource` vs `authoredDevelopment`). The
reader streams the pack JSONL line-by-line into a small in-memory index and
**never answers from a placeholder record** — a row with a null mother-tongue
form is skipped, so a placeholder is never presented as a translation.

DEVELOPMENT MOCK: every entry currently aboard is `provenance=authored-development`,
`verified=false`, and the UI says so. No authoritative Santali dataset exists in
this repository (verified by exploration this milestone), so honesty is in the
schema and the labels, not in inventing data.

## D. Cache-first decision engine (`offline_first_translation_service.dart`)

One place owns the priority now, shared by every screen through the registry:

```
cache → phrasebook → offline model → online backend → refused offline
```

`OfflineFirstTranslationService` gained an `offlineModel` slot (see F) between
the phrasebook and the network. A phrasebook miss falls to the model; a model
that is missing or failed falls through rather than erroring; offline with
neither → the exact "Offline translation is unavailable for this language."
refusal with no network call; online → the online provider, and whatever it
says is what happened.

## E. Per-row cache (`cache/translation_cache_store*.dart`)

`CachedTranslationEntry` + `TranslationCacheStore` interface:
`MemoryTranslationCacheStore` (tests + the honest web/memory fallback) and
`SqfliteTranslationCacheStore` (io targets). One SQLite row per entry — the full
cache is never decoded into RAM — with oldest-first trimming inside the store
and a deliberate bound of 200 rows. `CachedTextTranslationService` now persists
at the row level and rehydrates a hit with its original `TranslationSource`,
so a cached answer is labelled Cached, never Phrasebook or Online.

REAL: SQLite persistence on devices; measured (below). NOT IMPLEMENTED: nothing
more — the store is the whole feature.

## F. Offline-model slot + single-model policy (`offline_model_translation_service.dart`, `ai_model_manager.dart`)

`OfflineModelTranslationService` sits in the decision engine between phrasebook
and network. Honest by construction: no real on-device NLP model ships in this
build, so `supportsPair` is false while no verified pack is installed,
`translate` refuses with `modelUnavailable`, and the engine falls through to the
network exactly as for any uncovered sentence. `AiModelManager.loadModel` now
enforces one loaded model in memory (clear-then-add; `loadedCount` test hook) —
the 2 GB rule for whatever neural weights land later.

NOT IMPLEMENTED: a real translation engine. Tested honest (6 tests: unavailable
refusals, pair gating, decision-engine fall-through).

## G. Translate screen: honest badges, voice in, speech out

Badges now label the answer by its real source — `Phrasebook` / `Offline` /
`Online` / `Cached` — and never "AI" for a phrasebook or cache. A mic button
opens the recogniser through `ServiceRegistry.speech` (FallbackSpeechRecognitionService
wrapping the device recogniser); a language nothing can recognise reports so
instead of opening a dead microphone. A speaker button reads the result through
`ServiceRegistry.tts` (PlatformTextToSpeechService); a language with no voice
reports so instead of reading the wrong language aloud. Responses below 360 px
to 900 px lay out without overflow (tested at 360 and 800).

## H. Live Classroom: provenance survives the session

`ConversationTurn.source` records where each translation came from; it
round-trips through `toJson`/`fromJson`, and `voice_conversation_service` stamps
the turn when translation completes. The result timeline titles the answer line
by its honest source — `GyanSetu Phrasebook — Santali Translation`, never
"GyanSetu AI" for an answer a phrasebook produced. Development phrasebook results
show an unreviewed caption.

## I. Backend provider seam (`translation_provider.py`)

`TranslationProvider` (Protocol: `source`, `model_version`,
`reviewed_by_speaker`, `translate`) is the seam where a real model plugs into
`POST /api/v1/translate`. `get_translation_provider()` hands out
`DevelopmentTranslationProvider` today (DEVELOPMENT MOCK, same rule table as
before, now a protocol implementation with per-entry `category`); the router,
schema and device cache-key handling do not change when a real model lands.
Schema already carries `context`, `source`, `confidence`, `reviewed_by_speaker`.
Backend pytest re-ran green after the refactor.

## J. Structured seed dataset (`seed_dev.py`)

The phrasebook pack is now schema-structured: every line carries a `category`
(one of the 14), `provenance=authored-development`, `reviewedBySpeaker=false`,
`verified=false`, and the 6 new **placeholder records** (greetings,
encouragement, instructions, colors, basic actions, safety) with a null
`targetText` — the dataset declares what the classroom needs without pretending
to know the mother-tongue form. 24 authored entries total. Re-seeded and
verified live against the restarted server.

## K. Live E2E

Restarted uvicorn (no `--reload` in dev) with the refactored translate module,
then ran the gated suites against the live server:
- `live_backend_test` + `live_ai_pipeline_test` → **7 passed** (hi→sat live,
  reverse pair, honest 404, offline refusal exact message, online fallback
  labelled `online`, unauthenticated refusal, auth round-trip).
- `live_e2e_test` → **3 passed** (auth, profile identity, sync round-trip).

## L. Backend pytest

`cd backend && .venv/bin/python -m pytest` → **100 passed** on the refactored
provider code (dev engine becomes a Protocol implementation; route now composes
through the factory). 1 known deprecation warning, unchanged.

## M. Flutter analyze result

`flutter analyze` → **No issues found.** (One repair en route: a stray edit had
left the TTS service's class fields inside an unclosed method after the
capability change; restored to a single clean `isLanguageAvailable`.)

## N. Flutter test result

`flutter test` → **859 passed, 4 skipped** (3 live E2E + 1 live AI, gated; run
separately above). New non-live tests this milestone: **22** — 14 translation
milestone (offline-model honours + decision-engine fall-through + per-row cache
store + canonical capability honesty + ConversationTurn provenance round-trip)
and 7 Translate screen (honest badges, mic wiring, no-recogniser honesty, TTS
refused/speaks, responsive widths), plus 1 result-timeline provenance test. The
suite grew 837 → 859 without breaking a single prior assertion (the three
changed assertions are the honesty-label updates, rewritten for the new titles).

## O. Web build result

`flutter build web` → **✓ Built build/web**. The web target keeps its honest
no-writable-content behavior; the cache falls back to the session-only memory
store there via the conditional export.

## P. Security review

`grep` across `lib/` and `backend/app` for secrets/keys in source: **clean**. No
API keys or credentials committed. Only dev affordance remains the documented
dev teacher PIN `1234` (seeded `dev-teacher-1`, mobile `9000012345`), used by
live tests against the local server only.

## Q. Measured performance (2 GB-device paths)

Measured with a throwaway benchmark harness (run directly, then removed; not in
the suite) on this machine; reported as measured, not claimed:
- Phrasebook index build, 5,000-entry pack (25× the shipped dataset): cold
  ~88–139 ms; warm lookup ~0.07–0.5 ms. The shipped pack is ~24 rows, so real
  cold cost is far lower; the streaming reader is not material either way.
- Cache store, 200-entry capacity: write ~1.0 ms, read ~0.8 ms, trim ~0.07 ms.
- The 2 GB rules are structural, not aspirational: one model in RAM, per-row
  cache I/O, streamed phrasebook reads, bounded 200-row cache.

## R. Remaining limitations (honest)

- Everything labelled above stays true: phrasebook = DEVELOPMENT MOCK (24
  authored records, none speaker-verified; placeholders never answered from),
  offline model = NOT IMPLEMENTED (honest `modelUnavailable`), online = the
  development rule table served through the provider seam, no NLP model runs
  anywhere.
- Real TTS playback of translation output exists in the translate screen only
  for languages with a genuine voice (Hindi, English, Bengali); the tribal
  languages have none on any engine and the speaker control reports that.
- `/resources*` remains public (carried); user data endpoints stay protected.
- Real conversational NLP (anything beyond the phrasebook) is deliberately a
  NOT-IMPLEMENTED seam, not a fake.

## S. Exact next recommended milestone

1. **Authoritative Santali (and Mundari/Ho) dataset + a substantially larger
   verified phrasebook** — the schema, loader, labels and decision engine are
   ready; what is missing is sourced speaker-verified data, not more code.
2. **Real on-device transformer or server-side MT** behind the two seams
   (`OfflineModelTranslationService.translate`, `TranslationProvider`) — swap
   the engines in, keep the honesty labels, register `isRealModel = true`.
3. **Server-side translation model + per-teacher content authorization on
   `/resources*`** (carried) and **resumable range downloads** (carry).

All Milestone 4 commands passed against the real artifacts: analyze clean,
flutter test 859 passed (4 gated), backend pytest 100, live AI 7 + live E2E 3,
web build ✓, security scan clean, performance measured. COMPLETE.

# MILESTONE 5 — REAL SANTALI TRANSLATION DATA + PRODUCTION PIPELINE (A–Q)

Objective: turn "the phrases are real" into "the *data path* is real" — a
repeatable ingestion pipeline for authoritative language data, an honest record
model that carries provenance/verification, an indexed on-device phrasebook that
fits the 2 GB rule, env-selected server providers, quality-controlled source
labels, and hard regression across both stacks. It is a **boundary, not a
generator**: where an authoritative dataset or model does not exist, the stage
is built AND the gap is reported, never fabricated.

## A. Data audit, no data modified

Ran a read-only audit of every translation source in the repo. Findings, all
verified and none changed:

- **Verified translations: 0.** No record anywhere carries a true
  `verified`/`verifiedSource` marker.
- **Authored-but-unverified phrasebook: 18 answerable entries** (10 hi→sat,
  8 sat→hi) in the dev pack, plus **5 numerics** in the `translations` table
  (provenance `authored`). All 24 phrasebook lines + 5 numerals are
  DEVELOPMENT data with `reviewedBySpeaker = false`.
- **6 placeholders** (null `targetText`, hi→sat, never answered — never
  presented as a translation).
- **No real model.** `translation-model-hindi-santali` is a constant name;
  there are no weights on this machine or any server. Nothing in the app ever
  claims an NLP model runs.
- Conclusion: **nothing may be presented as real/verified today**; every
  screen already labels unreviewed phrasebook output as a development entry.

## B. Canonical record model (`backend/app/schemas/translation_record.py`)

`TranslationRecord` is now the single canonical shape for every translation
anywhere (pack, table, import, API): `id`, `source_language`, `target_language`,
`source_text`, `target_text` (nullable), `spoken_text`, `category`, `context`,
`dialect`, `verified`, `provenance`, `version`, `created_at`, `updated_at`.

- `PHRASEBOOK_CATEGORIES` frozenset (18 wire names incl. `answers`,
  `environment`, `basicMathematics`, `basicScience`).
- `normalise_translation_source_text()` strips punctuation/case for the natural
  key; `build_translation_record_id()` = `pb-` + sha1(`pair|normalised`)[:12],
  so the same sentence always yields the same id.
- Validators enforce honesty: pair must be in `TRANSLATION_PAIRS`; category
  must be known; **verified requires a non-development provenance** (`authored`,
  `authored-development`, `unknown`, or blank can never mark verified); a
  placeholder can never be verified; version ≥ 1.
- `to_pack_json()` emits camelCase + `reviewedBySpeaker` + ISO datetimes
  (was not JSON-serializable before — fixed).

## C. Ingestion pipeline (`backend/scripts/import_translations.py`)

Repeatable, strict, idempotent CLI that turns CSV / JSON / JSONL into the
canonical pack.

- `--input` repeatable; `--write` (default `data/generated/translations_import.jsonl`);
  `--replace` overwrites.
- **Strict abort**: any invalid row stops the whole import before a single line
  is written (exit 2, with the row and reason). Malformed files raise a clean
  `ImportValidationError`, never a traceback crash (a bare `KeyError` in the
  previous JSON-branch is gone; `.jsonl` input is now first-class so the importer
  re-swallows its own output exactly).
- **Idempotent**: natural-key (pair, normalised source), first-wins; re-runs
  insert 0. `--replace` rebuilds deterministically.
- Unverified rows are stored **unverified only**. Verified rows survive only
  with a real provenance (`examinedStandard` in tests) and a written
  mother-tongue form.
- Verified end-to-end: CSV happy-path (2 unverified + 2 sourced-verified with
  `reviewedBySpeaker: true`), JSONL round-trip (output → input identical), and
  the whole-import abort on one bad row, all against `data/generated/`.

## D. Env-selected server provider (`GYANSETU_TRANSLATION_PROVIDER`)

`backend/app/core/config.py` adds `translation_provider` (default `dev`, so a
stock deploy never silently changes behaviour). `get_translation_provider(name)`
returns the engine or raises `RuntimeError … not implemented` for any unknown
name — a real provider plugs in by name and reads its key from env
(`backend/.env.example` documents `GYANSETU_TRANSLATION_PROVIDER=dev`). The
dev engine remains an explicit dev rule table (`dev-rules-1`), never an NLP
claim. Live check: `GET /api/v1/translate` answers the known sentence with
`reviewedBySpeaker: false` and refuses an unknown one via `no_translation_rule`
— no fabrication.

## E. Indices & 2 GB-device storage (`lib/services/translation/phrasebook_index/`)

The phrasebook reader no longer holds the pack in RAM. It streams the JSONL one
line at a time on first use into a `PhrasebookIndexStore`:

- `SqflitePhrasebookIndexStore` on io targets: table `phrasebook_index(pair,
  norm_key, record_json, PK pair+norm_key)`, one row per record, single-row
  SELECT, `ConflictAlgorithm.replace`; web falls back to a memory store via the
  conditional-export shim. Wired into `ServiceRegistry` as
  `phrasebookIndexStore` (`devicePhrasebookIndexStore`), injectable.
- 5000-row synthetic run: every key resolves in one row read (memory-safe by
  construction). `forget()` clears; `rebuild` re-streams.

## F. Decision engine + labels (honesty on screen)

Decision graph from Milestone 4 unchanged (cache → phrasebook → offline-model →
online → honest refusal; no network call when explicitly offline). Quality
labels upgraded on the translate screen via `TranslationSource.displayLabel()`:
phrasebook+reviewed → **Verified phrase**, phrasebook → **Phrasebook**,
offline-model → **Offline model**, online → **Online translation**, cached →
**Cached**. `label` (used by conversation titles like "GyanSetu Phrasebook —
Santali Translation") is untouched. Unreviewed results keep the
"Development phrasebook entry — not yet verified by a speaker." caption.

## G. Verified ≠ trusted (reader-side enforcement)

`PhrasebookRecord.fromJson` is hostile-file-proof:
- `verified` is true only when `verified == true` **and** `targetText` present
  **and** provenance is `verifiedSource`. A file stamping `verified: true` on a
  development record or a placeholder is forced unverified.
- Provenance maps: `verifiedSource` carries through; `authored` /
  `authored-development` / anything unknown → `authoredDevelopment`.
- `translate()` answers only records with `canAnswer`; a placeholder is stored
  (so it is counted) but never answered from — the exact
  `notConfigured` refusal as before.

## H. Server record echo (`/api/v1/translations`)

The 5 numeral rows now come back through the API with `provenance: authored`,
`reviewedBySpeaker: false`, `version: 1` — the audit is visible, not buried.

## I. Engine/user-visible source metadata

`TranslationResult` still carries `source`, `modelVersion`, `spokenText`
(Devanagari for a voice), and `reviewedBySpeaker`; the dev provider never emits
a fabricated `confidence`. The server refuses with an explicit rule code and a
plain-language message rather than an invented sentence.

## J. Backend tests (Milestone 4: 100 → Milestone 5: 123)

`test_import_translations.py` (19 tests): unverified-only import, sourced-verified
pass-through, verified-without-provenance rejected, verified-placeholder
rejected, placeholders stay null, punctuation/case dedup, unknown language,
unsupported pair, mundari recognised-but-refused, unknown category, blank source,
idempotency, `--replace`, JSON `translations` list, **JSONL canonical shape**,
**malformed-JSON clean error**, whole-import abort, canonical schema fields,
version-honesty. `test_translation_provider.py` (4): dev default, by-name,
unknown fails loud, blank falls back.

## K. Flutter tests (Milestone 4: 859 → Milestone 5: 874, all green)

`test/translation/phrasebook_index_test.dart` (11): index-store one-row-per-key +
5000-row synthetic surface, fromJson never over-claims verification (dev stamp,
placeholder stamp, sourced-unverified), verified sourced record answers
`reviewedBySpeaker: true`, id/context/dialect/version ride the index, placeholders
stored-but-never-answered (counted), dev record stays unreviewed, `forget()`
clears storage. `test/translate/translate_screen_test.dart`: **Verified phrase**
badge, unverified keeps **Phrasebook** + warning, **Offline model** badge,
**Online translation** badge, Retry control (retries the exact sentence), all six
regression widths 360/375/390/412/600/900.

## L. Retry + responsive screen (Part 9)

A dedicated Retry on the error state calls `_controller.translate(_input.text)`
again (the teacher's exact sentence), with a layout-tested width set chosen to
cover small Androids and large tablets.

## M. Speech pipeline honesty (carried, unchanged)

Stays truthful: on-device recogniser list unchanged; the tribal languages have
no voice anywhere, and the speaker control says so instead of falling back to a
wrong-pronounced written text; the target (Devanagari `spokenText`) is only read
when a real voice exists.

## N. Model slot (Phase 6) — NOT IMPLEMENTED, MODEL REQUIRED

The design is complete and honest: `AiModelInfo` exposes `id/version/
sizeBytes/sha256`; the download pipeline verifies size + checksum; the decision
engine routes to `OfflineModelTranslationService` (which returns the honest
`modelUnavailable`); `isRealModel` is `false`; `get_translation_provider`
refuses unknown engine names. **There are no real weights anywhere and nothing
fraudulent is claimed.** A real model swaps in behind these seams.

## O. Security review

Same grep scan as Milestone 4 across `lib/` and `backend/app` for secrets
(sk-…, AWS keys, api_key literals, private keys, GitHub tokens): **clean**. No
`backend/.env` exists or is committed; only the documented dev teacher PIN
remains for local live tests.

## P. Live end-to-end (dev server restarted on the new Settings)

Restarted `uvicorn` (the old process predated the new Settings) and verified:
`/health` 200; login `identifier`/`password` under `/api/v1`; the known sentence
translates via the dev rule engine with `reviewedBySpeaker: false` and a spoken
form; an unknown sentence returns `no_translation_rule` with the exact
"MUST NOT be invented" message; `/api/v1/translations` echoes the 5 numerals as
`authored/unreviewed`.

## Q. Remaining limitations (honest) + next milestone

- Everything above stays real: phrasebook = **DEVELOPMENT MOCK** (24 authored,
  none speaker-verified, placeholders never answered from), offline model =
  **NOT IMPLEMENTED**, online = dev rule table through the provider seam, no NLP
  model runs anywhere. The labels that could over-claim are forced honest at
  BOTH the model layer (`verified`/provenance rules) and the screen layer
  (`displayLabel`).
- **DATA REQUIRED FROM PROJECT OWNER**: an authoritative Hindi↔Santali dataset
  (speaker-verified phrase pairs with context/dialect/version) is the only thing
  between this pipeline and a real production phrasebook. Run it through
  `python -m scripts.import_translations --input verified-santali.jsonl
  --write data/generated/translations_import.jsonl`, re-seed, and the app serves
  it. (Secondary: Mundari/Ho datasets; the schema already accepts them.)
- **MODEL REQUIRED**: a real on-device or server-side translation model behind
  `OfflineModelTranslationService` / `TranslationProvider` to cover anything the
  teacher says (all wiring, honesty labels and `isRealModel` seam are ready).
- Next recommended milestone, in order: (1) authoritative Santali + larger
  verified phrasebook through the new pipeline; (2) real MT behind the two
  seams; (3) server-side model + per-teacher authorization on `/resources*`
  (carried) and resumable range downloads (carry).

All Milestone 5 commands passed against the real artifacts: analyze clean,
flutter test 874 passed (4 gated skipped), backend pytest 123, live translate +
translations E2E green, web build ✓, security scan clean, importer round-trip
verified. COMPLETE.

---
# Milestone 6: Real Hindi↔Santali Dataset + Translation Model Evaluation

Milestone 6 goal (from the work plan): adopt a real Hindi↔Santali parallel
corpus, wire a real translation model behind the existing `TranslationProvider`
seam, measure it, and report honestly — classifying every claim as REAL /
DEVELOPMENT MOCK / NOT IMPLEMENTED / BLOCKED.

The headline result, stated up front and repeated at line level below: **no
piece of the real data pipeline could be run**, because the COILD-MT-Corpus
HIN-SAT pair and the IndicTrans2 checkpoint are both gated on Hugging Face and
no account and no token exist on this machine. Everything *around* the real
data — acquisition, validation/split, evaluation, model provider, honest API
contract — is built, wired, and fixture-tested, so the moment the project owner
accepts the terms and supplies a token, the pipeline runs end-to-end without a
code change. Per the hard safety rule, nothing was fabricated and no gate was
bypassed.

## Provenance & honesty

- Dataset: `ainlpml-iitp/COILD-MT-Corpus` (HIN-SAT subset, 20,603 pairs), CC BY
  4.0, **gated** — logged in `backend/data/SOURCES.md`.
- Model: `ai4bharat/indictrans2-indic-indic-dist-320M` (320 M params, MIT,
  **gated**), supports Santali `sat_Olck` natively.
- No HF account / token on this machine (verified live: `no hf`, no
  `~/.cache/huggingface/token`, no `huggingface_hub`).

## Work delivered this milestone

### 1. Acquisition script (BLOCKED by gate, code REAL)
`backend/scripts/acquire_coild_hin_sat.py` — stdlib-only (urllib), resumable,
ferches *only* `HIN-SAT/Hindi.txt` + `HIN-SAT/Santali.txt` (never the ~849 MB
repo), writes `checksums.sha256` + `retrieval.json`, honours
`GYANSETU_HF_TOKEN`/`HF_TOKEN`/`--token`, **exits 3 with an honest message on
gating** and never bypasses. Verified live: 401 → exit 3.
- **REAL**: script + provenance log.
- **BLOCKED**: actual download (gated, no token).

### 2. Validation / split pipeline (BLOCKED by data, code REAL)
`backend/scripts/prepare_hin_sat.py` — UTF-8 parse, alignment gate (mismatch =
loud exit 1, never truncates a side), empty/dedup/length cleanup, deterministic
80/10/10 split with no cross-partition leakage, writes `train/valid/test.{hi,sat}`
+ `dataset_report.json` + `DATASET_REPORT.md`. Validated on a COILD-shaped
fixture: 107 raw → 104 clean; splits 83/10/11; same seed → byte-identical;
alignment mismatch → exit 1; blocked → zero-row honest report.
- **REAL**: pipeline + fixture validation.
- **BLOCKED**: the real-data report (no data).

### 3. Model provider (REAL seam, BLOCKED model)
`backend/app/services/indic_trans2_translation_provider.py` — implements the
`TranslationProvider` ABC: lazy honest load (gated/missing deps → loud
RuntimeError, never silent fallback), `is_real_model=True`,
`reviewed_by_speaker=False`, `confidence=None`, `spoken_text=None` (Ol Chiki
cannot be read aloud). Registered as `indic_trans2` in the factory; injected
loader seam makes it unit-testable without downloading the checkpoint.
- **REAL**: provider + 4 unit tests (injected fakes).
- **BLOCKED**: loading the actual checkpoint (deps + gating).

### 4. Honest API contract (REAL)
- `normalise_translation_language` now folds IndicTrans2's own codes
  `hin_Deva`→`hindi`, `sat_Olck`→`santali` (additive to existing aliases).
- `TranslateResponse.is_real_model: bool` (default `False`); the device shows an
  "AI translation" badge **only** when the backend sets it true for a real
  model run. Dev provider returns false. Confidence stays null / spoken_text
  null / reviewed false for model output.
- Verified live: `POST /api/v1/translate` with `hin_Deva`/`sat_Olck` folds and
  returns `isRealModel:false` for the dev provider.

### 5. Flutter honest AI label (REAL)
`TranslationResult` gained additive `engineName` + `engineIsRealModel`; the
FastAPI service relays the backend's `source` and `isRealModel` verbatim; the
badge shows "AI translation • <engine>" only when `engineIsRealModel` is true.
New widget test locks it: a real-model answer shows the AI badge, dev/online
answers never do. Existing labels unchanged.

### 6. Evaluation harness (REAL harness, BLOCKED measurement)
`backend/scripts/evaluate_hin_sat.py` — measures the Hindi→Santali test split
with sacrebleu BLEU + chrF and per-sample latency, writes
`evaluation_metrics.json` (only `measured:true` with a real run) and
`evaluation/sample_translations.json` (every sample `human_review_required:
true`). Three-state tested live: dataset-blocked (exit 3), model-blocked (exit
2), measured via external predictions (exit 0, metrics written). The committed
`evaluation/` artifacts are the honest **blocked** report.
- **REAL**: harness + honest blocked report in `evaluation/`.
- **BLOCKED**: actual BLEU/chrF/latency (no data + no model).

### 7. Model resource analysis (REAL recommendation, UNMEASURED numbers)
`docs/model_resource_analysis.md` — estimates FP32/16/8/4 footprint for
`...-dist-320M`, concluding FP32 doesn't fit a 2 GB device, quantisation isn't
ship-ready, so **GyanSetu translates server-side**; the device keeps its offline
cache + curated phrasebook. **No on-device model.** The 2 GB feasibility number
is labelled **estimate, not measured** — a claim only becoming REAL after a
device measurement.

## Test & regression totals (all commands green)

- Backend: **pytest 128 passed** (was 123; + alias, provider, is_real_model,
  IndicTrans2 unit tests).
- Flutter: **875 passed / 4 skipped**, analyze clean, `build web` ✓.
- Live E2E: **3/3 passed** against the running server.
- Security scan: clean; no token in source; `.env` untracked.

## Answers to the 22 milestone questions

**Data**
1. Dataset source/version/citation — **BLOCKED** (gated; provenance written in
   `backend/data/SOURCES.md`, exact citation copy by owner at acquisition).
2. Real file format + column alignment — **BLOCKED** (script targets
   `HIN-SAT/Hindi.txt`/`Santali.txt`, 1:1 lines; no real file).
3. Clean/prepare pipeline + duplicate/empty decision — **REAL** (fixture-validated
   `prepare_hin_sat.py`, zero-row honest report when blocked).
4. Provenance (license, source, retrieval date, revision) — **REAL** in
   `backend/data/SOURCES.md`.
5. Aligned train/valid/test + leakage rule — **REAL** logic, **BLOCKED** data;
   dedupe-before-split guarantees no source sentence spans splits.
6. Real-data report public/longest/blank/dup counts — **BLOCKED** (fixture
   numbers only, clearly labelled).

**Model/evaluation**
7. Model + exact checkpoint id + why — **REAL** reselected:
   `ai4bharat/indictrans2-indic-indic-dist-320M` (smallest Indic-Indic, native
   `sat_Olck`).
8. Model actually loaded — **BLOCKED** (gated + no deps/token).
9. Latency/RAM measured — **NOT IMPLEMENTED / BLOCKED** (harness returns exit 2
   before measuring without the model; numbers in the doc are labelled
   estimates).
10. BLEU/chrF measured with code — **BLOCKED** (harness + sacrebleu wired,
    gated on a real checkpoint).
11. Real model vs dev phrasebook comparison — **NOT IMPLEMENTED** (no baseline
    to compare; seams ready).
12. Sample translations reviewed — **REAL** mechanism (`sample_translations.json`
    with `human_review_required:true`), **BLOCKED** content (no predictions).

**Pipeline / honesty**
13. Translation served by real model behind the seam — **REAL** seam + provider,
    **BLOCKED** model; dev provider still default.
14. API returns honest provenance (real vs dev) — **REAL**: `is_real_model`,
    `source`, `model_version`, explicit `confidence=null`.
15. Device labels "AI translation" only for real model — **REAL** (Flutter +
    widget test).
16. Confidence/reviewed correctness (no fabrication) — **REAL**: confidence
    null, reviewed false, spoken_text null for model output.
17. Offline cache + offline reuse + offline decision — **REAL** (cache key
    includes `model_version`, so no cross-provider staleness); server-side
    decision documented.
18. Performance targets documented — **REAL** doc
    (`docs/model_resource_analysis.md`), **UNMEASURED** numbers labelled as such.
19. Deterministic/reproducible pipeline — **REAL** (fixed seed, byte-identical
    split, checksums sidecar).
20. All tests + full regression — **REAL** (backend 128, Flutter 875/4, build
    web, live E2E 3/3, security scan).
21. Escalation path for blocked acquisition — **REAL** (exit-code contract:
    gated=3, other=2, alignment=1; explicit owner instructions; SOURCES note).
22. Milestone needs a real measured BLEU — **BLOCKED**; everything required to
    produce that baseline runs once the owner supplies a token on
    `ainlpml-iitp/COILD-MT-Corpus` and `ai4bharat/...-dist-320M`.

## Next-milestone recommendation (in order)
1. **Owner unlocks the gate** — accept the dataset + model terms, paste the
   canonical citations into `backend/data/SOURCES.md`, run `acquire_coild_hin_sat.py`
   then `prepare_hin_sat.py`, then `evaluate_hin_sat.py` to produce the first
   real BLEU/chrF baseline and review the `sample_translations.json`.
2. Backend: enable `GYANSETU_TRANSLATION_PROVIDER=indic_trans2`, install
   torch/transformers/IndicTransToolkit/sacrebleu alongside (all optional now).
3. Only after a measured baseline: reconsider on-device quantisation if it
   meets a measured 2 GB budget — no earlier.

All Milestone 6 commands passed against the real artifacts: analyze clean,
flutter test 875 passed (4 gated skipped), backend pytest 128, live E2E 3/3,
web build ✓, security scan clean, acquisition/eval exit-code contract verified
live (3 = gated, 2 = model blocked, fixtures = measured). Real data/model
measurement remains **BLOCKED** pending the owner's Hugging Face token.
COMPLETE.

---
# CURRENT CONTINUATION — REAL ONNX TRANSLATION RUNTIME

Date: 2026-08-30

This section supersedes Milestone 6's earlier runtime statement that no model
could run on this machine. The COILD dataset status is unchanged and remains
blocked; this continuation uses the already available ONNX model artifact and
does not retry dataset acquisition.

## A. Real model path

- `backend/app/services/indic_trans2_translation_provider.py` now loads
  `TigreGotico/indictrans2-indic-indic-dist-320M-onnx` from its `int8/` export
  through Optimum and ONNX Runtime on CPU.
- Loading remains lazy and process-wide cached. The previous Transformers path
  remains available for an explicitly supplied compatible non-ONNX model id.
- `GYANSETU_TRANSLATION_PROVIDER=dev` remains the safe default. Real inference
  is enabled explicitly with `GYANSETU_TRANSLATION_PROVIDER=indic_trans2`.
- Provenance is the configured model id; real responses set `isRealModel=true`,
  `confidence=null`, `reviewed=false`, and `spokenText=null`.

## B. Verified behavior

- Direct provider inference: real Hindi -> Santali and Santali -> Hindi output,
  both with `is_real_model=True`.
- Live API route tests with `LIVE_AI=true`: **2 passed, 1 intentionally skipped**
  (the forced-unavailable case is skipped when the live model run is enabled).
- The live checks exercise both `/api/v1/translate` and the legacy
  `/api/v1/translation/translate` route and verify real provenance.

## C. Regression results

- Backend: `pytest` **146 passed, 2 skipped**, 1 known Starlette/httpx
  deprecation warning.
- Flutter: `flutter test` **875 passed, 4 skipped**.
- Flutter analyze: **No issues found**.
- Web: `flutter build web --release` **succeeded**. The existing
  `flutter_tts` Wasm dry-run warnings do not prevent the build.

## D. Still blocked or development-only

- COILD HIN-SAT acquisition and real-data BLEU/chrF evaluation remain blocked
  by Hugging Face access; no dataset claim or evaluation score was added.
- The development phrasebook remains authored and unverified. Real model output
  is also not speaker-verified by this application.
- Model files are not committed; deployment must provide the configured model
  artifact or receive the explicit `model_unavailable` response.
