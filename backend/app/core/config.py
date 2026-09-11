"""Application configuration.

Every value is overridable through environment variables prefixed with
``GYANSETU_`` (e.g. ``GYANSETU_DATABASE_URL``) or a ``.env`` file placed in the
backend directory. See ``.env.example`` for the full list.

Nothing here is secret-independent: ``secret_key`` must be set to a strong,
stable value in any real deployment.
"""

from __future__ import annotations

from functools import lru_cache

from pydantic import AliasChoices, Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_prefix="GYANSETU_",
        extra="ignore",
        case_sensitive=False,
    )

    # -- Core -------------------------------------------------------------
    app_name: str = "Gyansetu Backend"
    version: str = "0.1.0"
    env: str = "development"

    # -- Database ----------------------------------------------------------
    # Dialect-agnostic. PostgreSQL is the production target; SQLite keeps local
    # development and the test-suite self-contained (no server required).
    database_url: str = "sqlite:///./gyansetu_dev.db"
    echo_sql: bool = False

    # -- Auth / tokens -----------------------------------------------------
    secret_key: str = "dev-only-insecure-secret-change-me"
    algorithm: str = "HS256"
    token_issuer: str = "gyansetu-backend"
    access_token_expires_minutes: int = 60 * 24 * 7  # one week

    # -- Password hashing --------------------------------------------------
    password_hash_algorithm: str = "pbkdf2_sha256"
    password_hash_iterations: int = 210_000

    # -- CORS --------------------------------------------------------------
    # Comma separated list, e.g. "http://localhost:5173,https://app.example.in"
    cors_origins: str = "*"

    # -- Translation ---------------------------------------------------------
    # Which backend translation provider `/api/v1/translate` uses, selected by
    # environment variable so a real model can be enabled without a code change
    # and without any API key living in source code. "dev" is the hand-written
    # phrasebook rule table. "indic_trans2" is the real model provider. Any
    # other value makes the app fail loudly rather than silently translate with
    # the wrong provider.
    translation_provider: str = "dev"

    # IndicTrans2 checkpoint to load when translation_provider == "indic_trans2".
    # This is the verified INT8 ONNX export; it runs through ONNX Runtime on CPU.
    # A compatible model id can be supplied without a code change.
    translation_model_id: str = (
        "TigreGotico/indictrans2-indic-indic-dist-320M-onnx"
    )

    # Token for gated Hugging Face resources (IndicTrans2). Read from
    # GYANSETU_HF_TOKEN or the standard HF_TOKEN in backend/.env only — never
    # hardcode one in source. huggingface_hub also reads HF_TOKEN itself; this
    # field guarantees the provider sees the token even if hub is not involved.
    huggingface_token: str | None = Field(
        default=None, validation_alias=AliasChoices("GYANSETU_HF_TOKEN", "HF_TOKEN")
    )

    # -- Voice (speech-to-speech) translation -----------------------------------
    # The public Adi Vaani ISTS endpoint the `/api/v1/translation/speech`
    # endpoint proxies. Public HTTP only; no key is read or forwarded. Values
    # are overridable through GYANSETU_ADIVAANI_TRANSLATE_URL and
    # GYANSETU_ADIVAANI_TRANSLATE_GENDER for a deployment that needs a change.
    adivaani_translate_url: str = "https://adivaani.tribal.gov.in/api/sts/translate"
    adivaani_translate_gender: str = "f"
    adivaani_translate_timeout_seconds: float = 90.0
    adivaani_max_audio_bytes: int = 15 * 1024 * 1024  # 15 MB of uploaded audio

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]

    @property
    def is_sqlite(self) -> bool:
        return self.database_url.startswith("sqlite")

    @property
    def is_production(self) -> bool:
        return self.env.strip().lower() == "production"


@lru_cache
def get_settings() -> Settings:
    return Settings()
