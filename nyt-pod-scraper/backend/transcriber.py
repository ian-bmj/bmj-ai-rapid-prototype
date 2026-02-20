"""
Audio transcription module.

Provides transcription via the OpenAI Whisper API, with a local
placeholder fallback when no API key is available.  The module is
designed so that additional providers (e.g. AWS Transcribe, local
Whisper) can be added with minimal changes.
"""

import logging
import os
from pathlib import Path
from typing import Optional

from config import load_config

logger = logging.getLogger(__name__)

# Maximum file size accepted by the OpenAI Whisper API (25 MB).
_WHISPER_MAX_BYTES = 25 * 1024 * 1024


def _validate_audio_path(audio_path: str) -> Path:
    """Validate that the audio file exists and return a Path object.

    Args:
        audio_path: Absolute or relative path to the audio file.

    Returns:
        Resolved :class:`pathlib.Path`.

    Raises:
        FileNotFoundError: If the file does not exist.
    """
    p = Path(audio_path).resolve()
    if not p.exists():
        raise FileNotFoundError(f"Audio file not found: {p}")
    return p


def transcribe_audio(audio_path: str, provider: str = "openai",
                     api_key: Optional[str] = None) -> str:
    """Transcribe an audio file using an external API.

    Currently the only supported provider is ``"openai"`` (Whisper).
    If no *api_key* is supplied the function attempts to read it from
    the application config or the ``OPENAI_API_KEY`` environment
    variable.

    Args:
        audio_path: Path to the audio file.
        provider: Transcription provider name.
        api_key: Optional API key override.

    Returns:
        The transcript text.

    Raises:
        FileNotFoundError: If the audio file is missing.
        ValueError: If the provider is not supported.
        RuntimeError: If no API key is available.
    """
    path = _validate_audio_path(audio_path)

    if provider != "openai":
        raise ValueError(
            f"Unsupported transcription provider: {provider!r}. "
            "Currently only 'openai' is supported."
        )

    return _transcribe_openai(path, api_key)


def _transcribe_openai(path: Path, api_key: Optional[str] = None) -> str:
    """Transcribe audio using the OpenAI Whisper API.

    Args:
        path: Resolved path to the audio file.
        api_key: Optional API key override.

    Returns:
        The transcript text.

    Raises:
        RuntimeError: If no API key is available or the API call fails.
    """
    # Resolve API key
    if not api_key:
        cfg = load_config()
        api_key = cfg.get("llm_api_key") or os.environ.get("OPENAI_API_KEY", "")

    if not api_key:
        logger.warning(
            "No OpenAI API key available -- returning placeholder transcript."
        )
        return _placeholder_transcript(path)

    file_size = path.stat().st_size
    if file_size > _WHISPER_MAX_BYTES:
        logger.warning(
            "Audio file %s is %d bytes (max %d). "
            "Consider splitting the file before transcription.",
            path, file_size, _WHISPER_MAX_BYTES,
        )

    try:
        from openai import OpenAI

        client = OpenAI(api_key=api_key)

        logger.info("Transcribing %s via OpenAI Whisper ...", path.name)
        with open(path, "rb") as audio_fh:
            response = client.audio.transcriptions.create(
                model="whisper-1",
                file=audio_fh,
                response_format="text",
            )

        transcript = response if isinstance(response, str) else str(response)
        logger.info(
            "Transcription complete: %d characters from %s",
            len(transcript), path.name,
        )
        return transcript

    except ImportError:
        logger.error("The 'openai' package is not installed.")
        raise RuntimeError("The 'openai' package is required for Whisper transcription.")
    except Exception as exc:
        logger.exception("OpenAI Whisper transcription failed for %s", path)
        raise RuntimeError(f"Transcription failed: {exc}") from exc


def transcribe_audio_local(audio_path: str) -> str:
    """Placeholder for local (on-device) transcription.

    In a future iteration this could use a local Whisper model via
    ``faster-whisper`` or similar.  For now it returns a descriptive
    placeholder so the rest of the pipeline can be exercised.

    Args:
        audio_path: Path to the audio file.

    Returns:
        A placeholder transcript string.
    """
    path = _validate_audio_path(audio_path)
    return _placeholder_transcript(path)


def _placeholder_transcript(path: Path) -> str:
    """Return a realistic-looking placeholder transcript.

    Args:
        path: The audio file path (used for metadata in the placeholder).

    Returns:
        A multi-line placeholder string.
    """
    size_mb = path.stat().st_size / (1024 * 1024) if path.exists() else 0

    return (
        f"[Placeholder transcript for: {path.name}]\n"
        f"[File size: {size_mb:.1f} MB]\n\n"
        "This is a placeholder transcript generated because no transcription "
        "API key was available at the time of processing. To generate a real "
        "transcript, configure an OpenAI API key in the application settings "
        "and re-run the transcription.\n\n"
        "In production this file would contain the full text output from the "
        "OpenAI Whisper speech-to-text model, which supports over 90 languages "
        "and handles a wide variety of audio conditions including background "
        "noise, multiple speakers, and domain-specific terminology."
    )
