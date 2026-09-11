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
    # The distilled 320M model is the smallest Indic-Indic checkpoint; the 1B
    # variant can be swapped in here without a code change.
    translation_model_id: str = "ai4bharat/indictrans2-indic-indic-dist-320M"

    # Token for gated Hugging Face resources (IndicTrans2). Read from
    # GYANSETU_HF_TOKEN or the standard HF_TOKEN in backend/.env only — never
    # hardcode one in source. huggingface_hub also reads HF_TOKEN itself; this
    # field guarantees the provider sees the token even if hub is not involved.
    huggingface_token: str | None = Field(
        default=None, validation_alias=AliasChoices("GYANSETU_HF_TOKEN", "HF_TOKEN")
    )

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