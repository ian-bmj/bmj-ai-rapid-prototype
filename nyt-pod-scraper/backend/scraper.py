"""
Podcast RSS feed scraper.

Parses RSS/Atom feeds via ``feedparser``, extracts episode metadata
(title, description, published date, audio URL, duration), and
downloads audio files to local storage.
"""

import hashlib
import logging
import os
import re
import time
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional
from urllib.parse import urlparse

try:
    import feedparser
except ImportError:
    feedparser = None  # type: ignore[assignment]

try:
    import requests
except ImportError:
    requests = None  # type: ignore[assignment]

import storage
from config import load_config

logger = logging.getLogger(__name__)

# Timeout for HTTP requests (connect, read) in seconds.
_REQUEST_TIMEOUT = (10, 120)

# Chunk size for streaming downloads (256 KB).
_DOWNLOAD_CHUNK = 256 * 1024


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _generate_episode_id(podcast_id: str, episode_title: str, pub_date: str) -> str:
    """Create a deterministic episode ID from podcast + episode metadata.

    Args:
        podcast_id: The parent podcast identifier.
        episode_title: Episode title string.
        pub_date: Published-date string.

    Returns:
        A short, URL-safe hexadecimal hash.
    """
    raw = f"{podcast_id}:{episode_title}:{pub_date}"
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:16]


def _parse_duration(value: Optional[str]) -> Optional[int]:
    """Parse an iTunes-style duration string into total seconds.

    Supports formats like ``"01:23:45"`` (h:m:s), ``"23:45"`` (m:s),
    or a plain integer of seconds.

    Args:
        value: The raw duration string from the feed.

    Returns:
        Duration in seconds, or ``None`` if parsing fails.
    """
    if not value:
        return None
    value = value.strip()

    # Pure numeric
    if value.isdigit():
        return int(value)

    parts = value.split(":")
    try:
        parts = [int(p) for p in parts]
    except ValueError:
        return None

    if len(parts) == 3:
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    if len(parts) == 2:
        return parts[0] * 60 + parts[1]
    return None


def _extract_audio_url(entry: dict) -> Optional[str]:
    """Extract the first audio enclosure URL from a feed entry.

    Args:
        entry: A single entry dict from ``feedparser``.

    Returns:
        The audio URL string, or ``None`` if no audio enclosure is found.
    """
    for link in entry.get("links", []):
        href = link.get("href", "")
        link_type = link.get("type", "")
        if "audio" in link_type or href.endswith((".mp3", ".m4a", ".wav", ".ogg")):
            return href

    for enc in entry.get("enclosures", []):
        href = enc.get("href", "") or enc.get("url", "")
        enc_type = enc.get("type", "")
        if "audio" in enc_type or href.endswith((".mp3", ".m4a", ".wav", ".ogg")):
            return href

    return None


def _safe_filename(name: str, max_length: int = 80) -> str:
    """Sanitise a string for use as a filename.

    Args:
        name: Raw name (e.g. episode title).
        max_length: Maximum character length for the result.

    Returns:
        A filesystem-safe string.
    """
    name = re.sub(r"[^\w\s-]", "", name)
    name = re.sub(r"[\s]+", "_", name.strip())
    return name[:max_length]


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def parse_feed(feed_url: str) -> Dict[str, Any]:
    """Parse a podcast RSS feed and return structured metadata.

    Args:
        feed_url: The URL of the RSS/Atom feed.

    Returns:
        A dict with keys ``podcast`` (metadata about the show) and
        ``episodes`` (a list of episode dicts).  Each episode dict
        contains: ``title``, ``description``, ``published``,
        ``audio_url``, ``duration_seconds``, ``guid``.
    """
    if feedparser is None:
        raise RuntimeError(
            "The 'feedparser' package is not installed. "
            "Run: pip install feedparser"
        )

    logger.info("Parsing feed: %s", feed_url)
    feed = feedparser.parse(feed_url)

    if feed.bozo and not feed.entries:
        logger.error("Feed parse error for %s: %s", feed_url, feed.bozo_exception)
        return {"podcast": {}, "episodes": []}

    podcast_meta = {
        "title": feed.feed.get("title", "Unknown Podcast"),
        "description": feed.feed.get("summary", feed.feed.get("subtitle", "")),
        "link": feed.feed.get("link", ""),
        "image": (feed.feed.get("image", {}) or {}).get("href", ""),
        "language": feed.feed.get("language", "en"),
    }

    episodes: List[Dict[str, Any]] = []
    for entry in feed.entries:
        audio_url = _extract_audio_url(entry)
        published_parsed = entry.get("published_parsed")
        if published_parsed:
            pub_dt = datetime(*published_parsed[:6], tzinfo=timezone.utc)
            pub_str = pub_dt.isoformat()
        else:
            pub_str = entry.get("published", "")

        ep = {
            "title": entry.get("title", "Untitled Episode"),
            "description": entry.get("summary", entry.get("subtitle", "")),
            "published": pub_str,
            "audio_url": audio_url,
            "duration_seconds": _parse_duration(
                entry.get("itunes_duration", entry.get("duration"))
            ),
            "guid": entry.get("id", entry.get("guid", "")),
        }
        episodes.append(ep)

    logger.info("Parsed %d episodes from %s", len(episodes), podcast_meta.get("title"))
    return {"podcast": podcast_meta, "episodes": episodes}


def download_episode(episode_url: str, output_path: str) -> str:
    """Download a podcast audio file.

    Uses streaming to handle large files without loading them entirely
    into memory.

    Args:
        episode_url: Direct URL to the audio file.
        output_path: Absolute filesystem path to save the file.

    Returns:
        The *output_path* on success.

    Raises:
        requests.HTTPError: If the download fails with a non-2xx status.
    """
    if requests is None:
        raise RuntimeError(
            "The 'requests' package is not installed. "
            "Run: pip install requests"
        )

    logger.info("Downloading episode: %s -> %s", episode_url, output_path)

    os.makedirs(os.path.dirname(output_path), exist_ok=True)

    resp = requests.get(episode_url, stream=True, timeout=_REQUEST_TIMEOUT)
    resp.raise_for_status()

    total = int(resp.headers.get("content-length", 0))
    downloaded = 0

    with open(output_path, "wb") as fh:
        for chunk in resp.iter_content(chunk_size=_DOWNLOAD_CHUNK):
            fh.write(chunk)
            downloaded += len(chunk)
            if total:
                pct = (downloaded / total) * 100
                if downloaded % (5 * _DOWNLOAD_CHUNK) == 0:
                    logger.debug("Download progress: %.1f%%", pct)

    logger.info("Downloaded %d bytes to %s", downloaded, output_path)
    return output_path


def scrape_podcast(podcast_config: Dict[str, Any]) -> Dict[str, Any]:
    """Run the full scrape pipeline for a single podcast.

    1. Parse the RSS feed.
    2. Identify new episodes (not already stored).
    3. Optionally download audio.
    4. Persist episode metadata to storage.

    Args:
        podcast_config: A dict containing at least ``id``, ``name``,
            ``feed_url``, and optional ``active`` flag.

    Returns:
        A summary dict with ``podcast_id``, ``new_episodes`` count,
        and ``errors``.
    """
    podcast_id = podcast_config["id"]
    feed_url = podcast_config.get("feed_url", "")
    if not feed_url:
        logger.warning("No feed URL for podcast %s", podcast_id)
        return {"podcast_id": podcast_id, "new_episodes": 0, "errors": ["No feed URL"]}

    if not podcast_config.get("active", True):
        logger.info("Podcast %s is inactive -- skipping", podcast_id)
        return {"podcast_id": podcast_id, "new_episodes": 0, "errors": []}

    cfg = load_config()
    max_episodes = cfg.get("max_episodes_per_feed", 5)

    result = {"podcast_id": podcast_id, "new_episodes": 0, "errors": []}

    try:
        feed_data = parse_feed(feed_url)
    except Exception as exc:
        logger.exception("Feed parse failed for %s", feed_url)
        result["errors"].append(str(exc))
        return result

    episodes = feed_data.get("episodes", [])[:max_episodes]

    # Load existing episodes index
    episodes_index = storage.get_object("config", f"episodes_{podcast_id}.json", as_json=True) or []
    existing_guids = {ep.get("guid") for ep in episodes_index if ep.get("guid")}

    for ep in episodes:
        if ep.get("guid") in existing_guids:
            continue

        episode_id = _generate_episode_id(podcast_id, ep["title"], ep["published"])
        ep["id"] = episode_id
        ep["podcast_id"] = podcast_id
        ep["status"] = "scraped"
        ep["transcript"] = None
        ep["summary"] = None
        ep["scraped_at"] = datetime.now(timezone.utc).isoformat()

        # Download audio if configured
        if cfg.get("download_audio") and ep.get("audio_url"):
            ext = os.path.splitext(urlparse(ep["audio_url"]).path)[1] or ".mp3"
            audio_key = f"{podcast_id}/{episode_id}{ext}"
            audio_path = os.path.join(cfg["audio_dir"], podcast_id, f"{episode_id}{ext}")
            try:
                download_episode(ep["audio_url"], audio_path)
                ep["audio_local_path"] = audio_path
                ep["audio_key"] = audio_key
            except Exception as exc:
                logger.error("Audio download failed for %s: %s", ep["title"], exc)
                result["errors"].append(f"Download failed: {ep['title']} -- {exc}")

        episodes_index.append(ep)
        result["new_episodes"] += 1
        logger.info("New episode stored: %s", ep["title"])

    # Persist updated index
    storage.put_object("config", f"episodes_{podcast_id}.json", episodes_index)

    # Update podcast metadata from feed if we have it
    if feed_data.get("podcast"):
        meta = dict(podcast_config)
        meta.update({
            "feed_title": feed_data["podcast"].get("title"),
            "feed_description": feed_data["podcast"].get("description"),
            "feed_image": feed_data["podcast"].get("image"),
            "last_scraped": datetime.now(timezone.utc).isoformat(),
            "episode_count": len(episodes_index),
        })
        storage.put_object("config", f"podcast_{podcast_id}.json", meta)

    return result


def scrape_all_podcasts(podcasts_config: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Scrape all configured podcasts.

    Args:
        podcasts_config: A list of podcast config dicts.

    Returns:
        A list of per-podcast result dicts (see :func:`scrape_podcast`).
    """
    results = []
    for pc in podcasts_config:
        try:
            res = scrape_podcast(pc)
            results.append(res)
        except Exception as exc:
            logger.exception("Unexpected error scraping podcast %s", pc.get("id"))
            results.append({
                "podcast_id": pc.get("id"),
                "new_episodes": 0,
                "errors": [str(exc)],
            })
    return results
