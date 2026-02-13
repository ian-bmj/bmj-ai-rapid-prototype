"""
Configuration management for the NYT Pod Scraper backend.

Loads configuration from a JSON file in the local data directory,
mimicking the S3 config storage pattern described in the architecture.
Provides sensible defaults for all settings so the application can
run out of the box in a local development environment.
"""

import json
import logging
import os
from pathlib import Path

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Path defaults
# ---------------------------------------------------------------------------
_BACKEND_DIR = Path(__file__).resolve().parent
_DATA_DIR = _BACKEND_DIR / "data"
_CONFIG_FILE = _DATA_DIR / "config" / "app_config.json"

# ---------------------------------------------------------------------------
# Default configuration
# ---------------------------------------------------------------------------
DEFAULT_CONFIG = {
    # -- directory layout (mirrors S3 bucket/prefix structure) ---------------
    "data_dir": str(_DATA_DIR),
    "audio_dir": str(_DATA_DIR / "audio"),
    "transcripts_dir": str(_DATA_DIR / "transcripts"),
    "summaries_dir": str(_DATA_DIR / "summaries"),
    "config_dir": str(_DATA_DIR / "config"),
    "emails_dir": str(_DATA_DIR / "emails"),

    # -- LLM provider settings -----------------------------------------------
    "llm_provider": "openai",          # openai | anthropic | google
    "llm_api_key": "",                  # set via env or config UI
    "llm_model": "gpt-4o",             # default model per provider
    "llm_models": {
        "openai": "gpt-4o",
        "anthropic": "claude-sonnet-4-20250514",
        "google": "gemini-2.0-flash",
    },

    # -- email / SMTP settings -----------------------------------------------
    "smtp_server": "smtp.gmail.com",
    "smtp_port": 587,
    "smtp_use_tls": True,
    "smtp_username": "",
    "smtp_password": "",
    "email_sender": "nyt-pod-scraper@bmj.com",
    "email_sender_name": "BMJ Pod Digest",

    # -- distribution lists ---------------------------------------------------
    "distribution_lists": {
        "daily": [],
        "weekly": [],
    },

    # -- scraper settings -----------------------------------------------------
    "scrape_interval_minutes": 60,
    "max_episodes_per_feed": 5,
    "download_audio": True,
    "auto_transcribe": False,
    "auto_summarize": False,
}


def _ensure_directories(config: dict) -> None:
    """Create all required data directories if they do not exist."""
    for key in ("data_dir", "audio_dir", "transcripts_dir",
                "summaries_dir", "config_dir", "emails_dir"):
        path = Path(config[key])
        path.mkdir(parents=True, exist_ok=True)


def load_config() -> dict:
    """Load configuration from disk, merging with defaults.

    The on-disk JSON file may contain a subset of keys; any missing
    keys are filled in from ``DEFAULT_CONFIG``.

    Returns:
        dict: The merged configuration dictionary.
    """
    config = dict(DEFAULT_CONFIG)

    # Override LLM API key from environment if available
    env_keys = {
        "OPENAI_API_KEY": "openai",
        "ANTHROPIC_API_KEY": "anthropic",
        "GOOGLE_API_KEY": "google",
    }
    for env_var, provider in env_keys.items():
        val = os.environ.get(env_var, "")
        if val:
            config["llm_api_key"] = val
            config["llm_provider"] = provider
            logger.info("Using LLM API key from environment variable %s", env_var)
            break

    # Merge with on-disk config (on-disk wins)
    if _CONFIG_FILE.exists():
        try:
            with open(_CONFIG_FILE, "r", encoding="utf-8") as fh:
                disk_config = json.load(fh)
            config.update(disk_config)
            logger.info("Loaded configuration from %s", _CONFIG_FILE)
        except (json.JSONDecodeError, OSError) as exc:
            logger.warning("Failed to read config file %s: %s", _CONFIG_FILE, exc)

    _ensure_directories(config)
    return config


def save_config(config: dict) -> None:
    """Persist the configuration dictionary to disk.

    Args:
        config: The configuration dictionary to save.
    """
    _ensure_directories(config)
    try:
        with open(_CONFIG_FILE, "w", encoding="utf-8") as fh:
            json.dump(config, fh, indent=2)
        logger.info("Configuration saved to %s", _CONFIG_FILE)
    except OSError as exc:
        logger.error("Failed to write config file %s: %s", _CONFIG_FILE, exc)
        raise


def get_config_value(key: str, default=None):
    """Convenience helper -- load config and return a single key.

    Args:
        key: The configuration key to look up.
        default: Value to return if the key is not present.

    Returns:
        The configuration value, or *default* if missing.
    """
    return load_config().get(key, default)
