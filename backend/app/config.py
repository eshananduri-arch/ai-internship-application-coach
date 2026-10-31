from functools import lru_cache
from pathlib import Path
from urllib.parse import urlparse
from pydantic import SecretStr, model_validator, Field
from pydantic_settings import BaseSettings, SettingsConfigDict

ROOT = Path(__file__).resolve().parents[1]

class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=ROOT / '.env', extra='ignore')
    app_env: str = 'development'
    app_origin: str = 'http://127.0.0.1:8010'
    database_url: SecretStr = SecretStr('')
    worker_database_url: SecretStr = SecretStr('')
    operator_database_url: SecretStr = SecretStr('')
    session_signing_key: SecretStr = SecretStr('')
    resume_encryption_key: SecretStr = SecretStr('')
    encryption_key_version: str = 'v1'
    admin_token: SecretStr = SecretStr('')
    cookie_secure: bool = False
    session_days: int = Field(default=30, ge=1, le=90)
    n8n_webhook_url: str = ''
    n8n_webhook_token: SecretStr = SecretStr('')
    n8n_timeout_seconds: int = Field(default=150, ge=5, le=600)
    n8n_idempotent: bool = False
    max_worker_concurrency: int = Field(default=2, ge=1, le=16)
    thread_idle_seconds: int = Field(default=10, ge=1, le=600)
    max_upload_bytes: int = Field(default=5242880, ge=1, le=5242880)
    db_pool_max: int = Field(default=6, ge=2, le=20)

    @model_validator(mode='after')
    def validate_secrets(self):
        if self.session_signing_key.get_secret_value() and len(self.session_signing_key.get_secret_value()) < 32:
            raise ValueError('SESSION_SIGNING_KEY must have at least 32 random characters')
        if self.n8n_webhook_url:
            url = urlparse(self.n8n_webhook_url)
            if url.username or url.password or url.fragment or not url.hostname:
                raise ValueError('Invalid coaching webhook URL')
            if url.scheme != 'https' and not (self.app_env == 'development' and url.scheme == 'http' and url.hostname in ('127.0.0.1', 'localhost')):
                raise ValueError('Coaching webhook must use HTTPS')
        if self.app_env == 'production':
            required = (self.database_url, self.session_signing_key, self.resume_encryption_key, self.admin_token)
            if not all(x.get_secret_value() for x in required) or not self.cookie_secure or not self.app_origin.startswith('https://'):
                raise ValueError('Production requires configured secrets, HTTPS and secure cookies')
        return self

    @property
    def coaching_configured(self):
        return bool(self.n8n_webhook_url and self.n8n_webhook_token.get_secret_value())

@lru_cache
def get_settings():
    return Settings()
