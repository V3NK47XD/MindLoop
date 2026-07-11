import os
from pathlib import Path
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    PORT: int = 6769
    HOST: str = "0.0.0.0"
    GEMINI_API_KEY: str = ""
    GEMINI_MODEL: str = "gemma-4-31b-it"
    STORAGE_DIR: str = "./storage"

    @property
    def storage_path(self) -> Path:
        # Resolve relative to the backend package root (parent of app/)
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
        env_file = ".env"
        env_file_encoding = "utf-8"
        extra = "ignore"

settings = Settings()
