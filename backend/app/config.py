import os
from pathlib import Path
from pydantic_settings import BaseSettings

def get_env_file_path() -> Path:
    backend_root = Path(__file__).resolve().parent.parent
    return backend_root / ".env"

def ensure_env_file_exists() -> Path:
    env_path = get_env_file_path()
    if not env_path.exists():
        default_content = (
            "HOST=0.0.0.0\n"
            "PORT=6769\n"
            "GEMINI_API_KEY=\n"
            "GEMINI_MODEL=gemma-4-31b-it\n"
            "STORAGE_DIR=./storage\n"
        )
        env_path.write_text(default_content, encoding="utf-8")
    return env_path

# Ensure .env file exists on import
ensure_env_file_exists()

class Settings(BaseSettings):
    PORT: int = 6769
    HOST: str = "0.0.0.0"
    GEMINI_API_KEY: str = ""
    GEMINI_MODEL: str = "gemma-4-31b-it"
    STORAGE_DIR: str = "./storage"

    @property
    def storage_path(self) -> Path:
        backend_root = Path(__file__).resolve().parent.parent
        p = (backend_root / "storage").resolve()
        p.mkdir(parents=True, exist_ok=True)
        return p

    @property
    def temp_path(self) -> Path:
        p = (self.storage_path / "temp").resolve()
        p.mkdir(parents=True, exist_ok=True)
        return p

    class Config:
        env_file = str(get_env_file_path())
        env_file_encoding = "utf-8"
        extra = "ignore"

settings = Settings()
