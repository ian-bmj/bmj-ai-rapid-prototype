"""
Flask API server for the NYT Pod Scraper.

Provides a RESTful JSON API consumed by the admin SPA, plus static-file
serving for the admin-app itself.  All persistent state is stored as
JSON files in the ``data/`` directory via :mod:`storage`.
"""

import json
import logging
import os
import sys
import uuid
from datetime import datetime, timezone, timedelta
from pathlib import Path

from flask import Flask, jsonify, request, send_from_directory, abort
from flask_cors import CORS

# Ensure the backend directory is on the Python path so sibling modules
# can be imported regardless of the working directory used to launch.
_BACKEND_DIR = Path(__file__).resolve().parent
if str(_BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(_BACKEND_DIR))

import config as app_config
import storage
import scraper
import transcriber
import summarizer
import email_generator

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(name)s  %(message)s",
)
logger = logging.getLogger("app")

# ---------------------------------------------------------------------------
# Flask application
# ---------------------------------------------------------------------------
app = Flask(
    __name__,
    static_folder=str(_BACKEND_DIR.parent / "admin-app"),
    static_url_path="",
)
CORS(app)

# Convenience: JSON responses should not be sorted or compacted
app.config["JSON_SORT_KEYS"] = False


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _now_iso() -> str:
    """Return the current UTC time as an ISO-8601 string."""
    return datetime.now(timezone.utc).isoformat()


def _load_podcasts() -> list:
    """Load the master podcasts list from storage."""
    data = storage.get_object("config", "podcasts.json", as_json=True)
    return data if isinstance(data, list) else []


def _save_podcasts(podcasts: list) -> None:
    """Persist the master podcasts list."""
    storage.put_object("config", "podcasts.json", podcasts)


def _load_episodes(podcast_id: str) -> list:
    """Load episodes for a single podcast."""
    data = storage.get_object("config", f"episodes_{podcast_id}.json", as_json=True)
    return data if isinstance(data, list) else []


def _save_episodes(podcast_id: str, episodes: list) -> None:
    """Persist episodes for a single podcast."""
    storage.put_object("config", f"episodes_{podcast_id}.json", episodes)


def _find_podcast(podcast_id: str):
    """Find a podcast by ID.  Returns (podcast_dict, index, podcasts_list) or None."""
    podcasts = _load_podcasts()
    for idx, p in enumerate(podcasts):
        if p.get("id") == podcast_id:
            return p, idx, podcasts
    return None, None, podcasts


def _find_episode(episode_id: str):
    """Search all podcasts for an episode by ID.

    Returns (episode_dict, episode_index, podcast_id, episodes_list) or Nones.
    """
    podcasts = _load_podcasts()
    for pc in podcasts:
        episodes = _load_episodes(pc["id"])
        for idx, ep in enumerate(episodes):
            if ep.get("id") == episode_id:
                return ep, idx, pc["id"], episodes
    return None, None, None, None


# ---------------------------------------------------------------------------
# Static file serving (SPA)
# ---------------------------------------------------------------------------

@app.route("/")
def serve_index():
    """Serve the admin-app index.html (SPA entry point)."""
    index_path = Path(app.static_folder) / "index.html"
    if index_path.exists():
        return send_from_directory(app.static_folder, "index.html")
    return jsonify({"message": "NYT Pod Scraper API is running. Admin app not yet built."}), 200


@app.route("/bmj-pat-lib/<path:path>")
def serve_pattern_library(path):
    """Serve BMJ pattern library files.

    The admin-app references ``../../bmj-pat-lib/`` which resolves to
    ``/bmj-pat-lib/`` in the browser.  This route serves those files
    from the actual pattern library directory.
    """
    pat_lib_dir = _BACKEND_DIR.parent.parent / "bmj-pat-lib"
    full = pat_lib_dir / path
    if full.exists() and full.is_file():
        return send_from_directory(str(pat_lib_dir), path)
    abort(404)


@app.route("/<path:path>")
def serve_static(path):
    """Serve static files from the admin-app directory."""
    full = Path(app.static_folder) / path
    if full.exists() and full.is_file():
        return send_from_directory(app.static_folder, path)
    # Fall back to index.html for SPA routing
    index_path = Path(app.static_folder) / "index.html"
    if index_path.exists():
        return send_from_directory(app.static_folder, "index.html")
    abort(404)


# ===================================================================
#  PODCASTS
# ===================================================================

@app.route("/api/podcasts", methods=["GET"])
def list_podcasts():
    """List all tracked podcasts."""
    podcasts = _load_podcasts()
    # Enrich with episode count
    for p in podcasts:
        episodes = _load_episodes(p["id"])
        p["episode_count"] = len(episodes)
    return jsonify(podcasts)


@app.route("/api/podcasts", methods=["POST"])
def add_podcast():
    """Add a new podcast to track.

    Body: ``{name, feed_url, category?, active?}``
    """
    data = request.get_json(force=True)
    if not data.get("name") or not data.get("feed_url"):
        return jsonify({"error": "name and feed_url are required"}), 400

    podcasts = _load_podcasts()
    new_podcast = {
        "id": uuid.uuid4().hex[:12],
        "name": data["name"],
        "feed_url": data["feed_url"],
        "category": data.get("category", "General"),
        "active": data.get("active", True),
        "added_at": _now_iso(),
        "last_scraped": None,
        "episode_count": 0,
        "feed_title": None,
        "feed_description": None,
        "feed_image": None,
    }
    podcasts.append(new_podcast)
    _save_podcasts(podcasts)

    logger.info("Added podcast: %s (%s)", new_podcast["name"], new_podcast["id"])
    return jsonify(new_podcast), 201


@app.route("/api/podcasts/<podcast_id>", methods=["GET"])
def get_podcast(podcast_id):
    """Get detailed information about a single podcast."""
    podcast, _, _ = _find_podcast(podcast_id)
    if not podcast:
        return jsonify({"error": "Podcast not found"}), 404
    episodes = _load_episodes(podcast_id)
    podcast["episode_count"] = len(episodes)
    return jsonify(podcast)


@app.route("/api/podcasts/<podcast_id>", methods=["PUT"])
def update_podcast(podcast_id):
    """Update podcast details (toggle active, edit name/url, etc.)."""
    podcast, idx, podcasts = _find_podcast(podcast_id)
    if not podcast:
        return jsonify({"error": "Podcast not found"}), 404

    data = request.get_json(force=True)
    allowed_fields = {"name", "feed_url", "category", "active"}
    for key in allowed_fields:
        if key in data:
            podcast[key] = data[key]
    podcast["updated_at"] = _now_iso()

    podcasts[idx] = podcast
    _save_podcasts(podcasts)
    logger.info("Updated podcast %s", podcast_id)
    return jsonify(podcast)


@app.route("/api/podcasts/<podcast_id>", methods=["DELETE"])
def delete_podcast(podcast_id):
    """Remove a podcast and all its episode data."""
    podcast, idx, podcasts = _find_podcast(podcast_id)
    if not podcast:
        return jsonify({"error": "Podcast not found"}), 404

    podcasts.pop(idx)
    _save_podcasts(podcasts)

    # Clean up episode data
    storage.delete_object("config", f"episodes_{podcast_id}.json")

    logger.info("Deleted podcast %s", podcast_id)
    return jsonify({"message": f"Podcast {podcast_id} deleted"})


@app.route("/api/podcasts/<podcast_id>/scrape", methods=["POST"])
def trigger_scrape(podcast_id):
    """Trigger a scrape for a single podcast."""
    podcast, _, _ = _find_podcast(podcast_id)
    if not podcast:
        return jsonify({"error": "Podcast not found"}), 404

    try:
        result = scraper.scrape_podcast(podcast)
        return jsonify(result)
    except Exception as exc:
        logger.exception("Scrape failed for %s", podcast_id)
        return jsonify({"error": str(exc)}), 500


# ===================================================================
#  EPISODES
# ===================================================================

@app.route("/api/podcasts/<podcast_id>/episodes", methods=["GET"])
def list_episodes(podcast_id):
    """List episodes for a podcast."""
    podcast, _, _ = _find_podcast(podcast_id)
    if not podcast:
        return jsonify({"error": "Podcast not found"}), 404

    episodes = _load_episodes(podcast_id)
    # Sort by published date, most recent first
    episodes.sort(key=lambda e: e.get("published", ""), reverse=True)
    return jsonify(episodes)


@app.route("/api/episodes/<episode_id>", methods=["GET"])
def get_episode(episode_id):
    """Get full episode detail including transcript and summary."""
    ep, _, podcast_id, _ = _find_episode(episode_id)
    if not ep:
        return jsonify({"error": "Episode not found"}), 404

    # Attach transcript text if stored
    if ep.get("transcript_key"):
        transcript = storage.get_object("transcripts", ep["transcript_key"])
        ep["transcript_text"] = transcript
    elif ep.get("transcript"):
        ep["transcript_text"] = ep["transcript"]

    # Attach summary data if stored
    if ep.get("summary_key"):
        summary_data = storage.get_object("summaries", ep["summary_key"], as_json=True)
        ep["summary_data"] = summary_data
    elif ep.get("summary"):
        ep["summary_data"] = ep["summary"]

    return jsonify(ep)


@app.route("/api/episodes/<episode_id>/transcribe", methods=["POST"])
def trigger_transcribe(episode_id):
    """Trigger transcription for a single episode."""
    ep, ep_idx, podcast_id, episodes = _find_episode(episode_id)
    if not ep:
        return jsonify({"error": "Episode not found"}), 404

    audio_path = ep.get("audio_local_path")
    if not audio_path or not Path(audio_path).exists():
        return jsonify({"error": "Audio file not found. Scrape the podcast first."}), 400

    try:
        cfg = app_config.load_config()
        transcript = transcriber.transcribe_audio(
            audio_path,
            provider="openai",
            api_key=cfg.get("llm_api_key"),
        )
    except RuntimeError:
        # Fall back to local placeholder
        transcript = transcriber.transcribe_audio_local(audio_path)
    except FileNotFoundError:
        return jsonify({"error": "Audio file not found on disk."}), 404

    # Store transcript
    transcript_key = f"{podcast_id}/{episode_id}.txt"
    storage.put_object("transcripts", transcript_key, transcript)

    # Update episode record
    ep["transcript_key"] = transcript_key
    ep["transcript"] = transcript[:500] + ("..." if len(transcript) > 500 else "")
    ep["status"] = "transcribed"
    ep["transcribed_at"] = _now_iso()
    episodes[ep_idx] = ep
    _save_episodes(podcast_id, episodes)

    logger.info("Transcribed episode %s", episode_id)
    return jsonify({
        "message": "Transcription complete",
        "transcript_length": len(transcript),
        "episode_id": episode_id,
    })


@app.route("/api/episodes/<episode_id>/summarize", methods=["POST"])
def trigger_summarize(episode_id):
    """Trigger LLM summarisation for a single episode."""
    ep, ep_idx, podcast_id, episodes = _find_episode(episode_id)
    if not ep:
        return jsonify({"error": "Episode not found"}), 404

    # Get full transcript
    transcript_text = None
    if ep.get("transcript_key"):
        transcript_text = storage.get_object("transcripts", ep["transcript_key"])
    if not transcript_text and ep.get("transcript"):
        transcript_text = ep["transcript"]
    if not transcript_text:
        return jsonify({"error": "No transcript available. Transcribe the episode first."}), 400

    try:
        cfg = app_config.load_config()
        result = summarizer.summarize_transcript(
            transcript_text,
            provider=cfg.get("llm_provider"),
            api_key=cfg.get("llm_api_key"),
            model=cfg.get("llm_models", {}).get(cfg.get("llm_provider")),
        )
    except Exception as exc:
        logger.exception("Summarisation failed for episode %s", episode_id)
        return jsonify({"error": f"Summarisation failed: {exc}"}), 500

    # Store summary
    summary_key = f"{podcast_id}/{episode_id}.json"
    storage.put_object("summaries", summary_key, result)

    # Update episode record
    ep["summary_key"] = summary_key
    ep["summary"] = result
    ep["status"] = "summarized"
    ep["summarized_at"] = _now_iso()
    episodes[ep_idx] = ep
    _save_episodes(podcast_id, episodes)

    logger.info("Summarised episode %s", episode_id)
    return jsonify({
        "message": "Summarisation complete",
        "episode_id": episode_id,
        "summary": result,
    })


# ===================================================================
#  DISTRIBUTION LISTS
# ===================================================================

@app.route("/api/distribution-lists", methods=["GET"])
def get_distribution_lists():
    """Get the daily and weekly distribution lists."""
    cfg = app_config.load_config()
    return jsonify(cfg.get("distribution_lists", {"daily": [], "weekly": []}))


@app.route("/api/distribution-lists", methods=["PUT"])
def update_distribution_lists():
    """Update distribution lists.

    Body: ``{daily: [...emails], weekly: [...emails]}``
    """
    data = request.get_json(force=True)
    cfg = app_config.load_config()
    dl = cfg.get("distribution_lists", {"daily": [], "weekly": []})

    if "daily" in data:
        dl["daily"] = data["daily"]
    if "weekly" in data:
        dl["weekly"] = data["weekly"]

    cfg["distribution_lists"] = dl
    app_config.save_config(cfg)

    logger.info("Updated distribution lists: daily=%d, weekly=%d",
                len(dl["daily"]), len(dl["weekly"]))
    return jsonify(dl)


# ===================================================================
#  EMAIL / DISTRIBUTION
# ===================================================================

def _build_daily_digest_data() -> dict:
    """Collect today's episode summaries and build daily digest input."""
    podcasts = _load_podcasts()
    today_summaries = []

    for pc in podcasts:
        if not pc.get("active", True):
            continue
        episodes = _load_episodes(pc["id"])
        for ep in episodes:
            summary = ep.get("summary")
            if summary and isinstance(summary, dict):
                today_summaries.append({
                    "podcast_name": pc.get("name", "Unknown"),
                    "episode_title": ep.get("title", "Unknown"),
                    "summary": summary.get("summary", ""),
                    "gist": summary.get("gist", ""),
                    "themes": summary.get("themes", []),
                    "key_quotes": summary.get("key_quotes", []),
                })

    if not today_summaries:
        return {
            "headline": "No New Summaries Available",
            "overview": "No podcast episodes have been summarised yet. Add podcasts and run the processing pipeline.",
            "common_themes": [],
            "alerts": [],
            "podcast_briefs": [],
            "date": datetime.now(timezone.utc).strftime("%A, %d %B %Y"),
        }

    # Try to generate via LLM, fall back to simple aggregation
    try:
        cfg = app_config.load_config()
        digest = summarizer.generate_daily_digest(
            today_summaries,
            provider=cfg.get("llm_provider"),
            api_key=cfg.get("llm_api_key"),
            model=cfg.get("llm_models", {}).get(cfg.get("llm_provider")),
        )
    except Exception as exc:
        logger.warning("Daily digest LLM call failed, using simple aggregation: %s", exc)
        digest = {
            "headline": "BMJ Daily Podcast Digest",
            "overview": f"Summary of {len(today_summaries)} podcast episodes.",
            "common_themes": list({t for s in today_summaries for t in s.get("themes", [])}),
            "alerts": [],
            "podcast_briefs": [
                {
                    "podcast_name": s["podcast_name"],
                    "episode_title": s["episode_title"],
                    "one_liner": s.get("gist", ""),
                }
                for s in today_summaries
            ],
        }

    digest["date"] = datetime.now(timezone.utc).strftime("%A, %d %B %Y")
    return digest


def _build_weekly_digest_data() -> dict:
    """Build weekly digest data from stored daily digests."""
    # For the prototype, gather all available summaries as a single week
    daily_digest = _build_daily_digest_data()
    try:
        cfg = app_config.load_config()
        weekly = summarizer.generate_weekly_digest(
            [daily_digest],
            provider=cfg.get("llm_provider"),
            api_key=cfg.get("llm_api_key"),
            model=cfg.get("llm_models", {}).get(cfg.get("llm_provider")),
        )
    except Exception as exc:
        logger.warning("Weekly digest LLM call failed: %s", exc)
        weekly = {
            "headline": "BMJ Weekly Podcast Intelligence",
            "executive_summary": daily_digest.get("overview", ""),
            "trending_themes": [
                {"theme": t, "trajectory": "steady", "summary": ""}
                for t in daily_digest.get("common_themes", [])
            ],
            "narrative_arcs": [],
            "recommended_actions": [],
        }

    now = datetime.now(timezone.utc)
    week_ago = now - timedelta(days=7)
    weekly["date_range"] = f"{week_ago.strftime('%d %B')} -- {now.strftime('%d %B %Y')}"
    return weekly


@app.route("/api/email/daily/preview", methods=["GET"])
def preview_daily_email():
    """Preview the daily digest email."""
    try:
        digest = _build_daily_digest_data()
        html = email_generator.render_daily_email(digest)
        path = email_generator.preview_email(html)
        return jsonify({
            "html": html,
            "preview_path": path,
            "digest_data": digest,
        })
    except Exception as exc:
        logger.exception("Failed to generate daily email preview")
        return jsonify({"error": str(exc)}), 500


@app.route("/api/email/weekly/preview", methods=["GET"])
def preview_weekly_email():
    """Preview the weekly digest email."""
    try:
        digest = _build_weekly_digest_data()
        html = email_generator.render_weekly_email(digest)
        path = email_generator.preview_email(html)
        return jsonify({
            "html": html,
            "preview_path": path,
            "digest_data": digest,
        })
    except Exception as exc:
        logger.exception("Failed to generate weekly email preview")
        return jsonify({"error": str(exc)}), 500


@app.route("/api/email/daily/send", methods=["POST"])
def send_daily_email():
    """Send the daily digest email to the daily distribution list."""
    cfg = app_config.load_config()
    recipients = cfg.get("distribution_lists", {}).get("daily", [])
    if not recipients:
        return jsonify({"error": "No recipients in daily distribution list."}), 400

    try:
        digest = _build_daily_digest_data()
        html = email_generator.render_daily_email(digest)
        result = email_generator.send_email(
            html, recipients,
            subject=f"BMJ Pod Digest: {digest.get('headline', 'Daily Digest')}",
        )
        return jsonify(result)
    except Exception as exc:
        logger.exception("Failed to send daily email")
        return jsonify({"error": str(exc)}), 500


@app.route("/api/email/weekly/send", methods=["POST"])
def send_weekly_email():
    """Send the weekly digest email to the weekly distribution list."""
    cfg = app_config.load_config()
    recipients = cfg.get("distribution_lists", {}).get("weekly", [])
    if not recipients:
        return jsonify({"error": "No recipients in weekly distribution list."}), 400

    try:
        digest = _build_weekly_digest_data()
        html = email_generator.render_weekly_email(digest)
        result = email_generator.send_email(
            html, recipients,
            subject=f"BMJ Pod Intel: {digest.get('headline', 'Weekly Briefing')}",
        )
        return jsonify(result)
    except Exception as exc:
        logger.exception("Failed to send weekly email")
        return jsonify({"error": str(exc)}), 500


# ===================================================================
#  CONFIGURATION
# ===================================================================

@app.route("/api/config", methods=["GET"])
def get_config():
    """Return the current application configuration.

    Sensitive fields (API keys, SMTP password) are masked in the
    response.
    """
    cfg = app_config.load_config()
    safe = dict(cfg)
    # Mask sensitive values
    if safe.get("llm_api_key"):
        safe["llm_api_key"] = safe["llm_api_key"][:8] + "..." + safe["llm_api_key"][-4:]
    if safe.get("smtp_password"):
        safe["smtp_password"] = "********"
    return jsonify(safe)


@app.route("/api/config", methods=["PUT"])
def update_config():
    """Update application configuration.

    Body: a JSON object with any subset of configuration keys.
    """
    data = request.get_json(force=True)
    cfg = app_config.load_config()

    allowed = {
        "llm_provider", "llm_api_key", "llm_model", "llm_models",
        "smtp_server", "smtp_port", "smtp_use_tls",
        "smtp_username", "smtp_password",
        "email_sender", "email_sender_name",
        "scrape_interval_minutes", "max_episodes_per_feed",
        "download_audio", "auto_transcribe", "auto_summarize",
    }

    for key in allowed:
        if key in data:
            cfg[key] = data[key]

    app_config.save_config(cfg)
    logger.info("Configuration updated")
    return jsonify({"message": "Configuration updated"})


# ===================================================================
#  DEMO DATA SEED
# ===================================================================

@app.route("/api/demo/seed", methods=["POST"])
def seed_demo_data():
    """Seed realistic demo data for testing the admin app.

    Creates 4 podcasts, each with 2-3 episodes that have transcripts,
    summaries, gists, and themes.  The content is tailored to BMJ
    editorial interests: health policy, medical evidence, public
    health, and the media landscape.
    """
    logger.info("Seeding demo data ...")

    now = datetime.now(timezone.utc)

    # ------------------------------------------------------------------
    # Podcasts
    # ------------------------------------------------------------------
    podcasts = [
        {
            "id": "pod_healthwatch",
            "name": "HealthWatch Weekly",
            "feed_url": "https://feeds.example.com/healthwatch",
            "category": "Health Policy",
            "active": True,
            "added_at": (now - timedelta(days=30)).isoformat(),
            "last_scraped": (now - timedelta(hours=6)).isoformat(),
            "episode_count": 3,
            "feed_title": "HealthWatch Weekly",
            "feed_description": "In-depth analysis of UK and global health policy, NHS reform, and public health challenges from leading health journalists.",
            "feed_image": None,
        },
        {
            "id": "pod_medmyths",
            "name": "Medical Myths Debunked",
            "feed_url": "https://feeds.example.com/medmyths",
            "category": "Medical Science",
            "active": True,
            "added_at": (now - timedelta(days=28)).isoformat(),
            "last_scraped": (now - timedelta(hours=8)).isoformat(),
            "episode_count": 3,
            "feed_title": "Medical Myths Debunked",
            "feed_description": "Scientists and clinicians tackle health misinformation, viral claims, and contested medical evidence head-on.",
            "feed_image": None,
        },
        {
            "id": "pod_westminster",
            "name": "Westminster Health Briefing",
            "feed_url": "https://feeds.example.com/westminster-health",
            "category": "Politics & Health",
            "active": True,
            "added_at": (now - timedelta(days=25)).isoformat(),
            "last_scraped": (now - timedelta(hours=3)).isoformat(),
            "episode_count": 2,
            "feed_title": "Westminster Health Briefing",
            "feed_description": "Political correspondents decode how government policy, parliamentary debates, and party politics shape the UK health landscape.",
            "feed_image": None,
        },
        {
            "id": "pod_globalhealth",
            "name": "Global Health Dispatch",
            "feed_url": "https://feeds.example.com/global-health",
            "category": "Global Health",
            "active": False,
            "added_at": (now - timedelta(days=20)).isoformat(),
            "last_scraped": (now - timedelta(days=3)).isoformat(),
            "episode_count": 2,
            "feed_title": "Global Health Dispatch",
            "feed_description": "WHO correspondents and field epidemiologists report on pandemics, health equity, and international health governance.",
            "feed_image": None,
        },
    ]
    _save_podcasts(podcasts)

    # ------------------------------------------------------------------
    # Episodes -- HealthWatch Weekly
    # ------------------------------------------------------------------
    hw_episodes = [
        {
            "id": "ep_hw_001",
            "podcast_id": "pod_healthwatch",
            "title": "NHS Workforce Crisis: The 2026 Staffing Plan Under Scrutiny",
            "description": "We examine the government's long-awaited NHS workforce strategy, speaking to frontline clinicians, health economists, and the Health Secretary's senior adviser.",
            "published": (now - timedelta(days=1)).isoformat(),
            "audio_url": "https://example.com/audio/hw001.mp3",
            "duration_seconds": 2520,
            "guid": "hw-ep-001",
            "status": "summarized",
            "scraped_at": (now - timedelta(days=1)).isoformat(),
            "transcribed_at": (now - timedelta(hours=20)).isoformat(),
            "summarized_at": (now - timedelta(hours=18)).isoformat(),
            "audio_local_path": None,
            "transcript_key": "pod_healthwatch/ep_hw_001.txt",
            "transcript": "The NHS workforce plan released last week proposes expanding medical school places by 40% over the next decade...",
            "summary_key": "pod_healthwatch/ep_hw_001.json",
            "summary": {
                "summary": "The episode dissects the government's new NHS workforce strategy, which pledges a 40% increase in medical school places and a major expansion of physician associate roles. Health economist Professor Sarah Chen argues the plan underestimates the cost of training infrastructure, while BMA council chair Dr Adeola Mensah warns that without immediate measures to improve retention, new graduates will simply leave for better-paying systems abroad. The Health Secretary's adviser, James Lockhart, defends the timeline, pointing to parallel investment in digital health and AI diagnostics to reduce clinician workload. Notable tension emerges between those who see physician associates as a pragmatic solution and senior clinicians who argue the roles lack sufficient clinical oversight. The programme also covers the Royal College of Nursing's response, which describes the plan as 'a decade too late and a billion short'.",
                "gist": "Government NHS workforce plan faces criticism for slow timelines and underestimated costs despite ambitious training expansion.",
                "themes": ["NHS", "Health Policy", "Workforce Planning", "Medical Education", "Health Economics"],
                "key_quotes": [
                    "We are essentially asking today's patients to wait a decade for tomorrow's doctors. -- Prof. Sarah Chen",
                    "The retention crisis is the elephant in the room. You can train all the doctors you want, but if they leave within five years, you've solved nothing. -- Dr Adeola Mensah",
                    "Digital health isn't a replacement for clinicians, but it can free up 30% of a GP's time spent on administrative tasks. -- James Lockhart",
                ]
            },
        },
        {
            "id": "ep_hw_002",
            "podcast_id": "pod_healthwatch",
            "title": "Mental Health Act Reform: What Changes and What Doesn't",
            "description": "A deep dive into the proposed Mental Health Act reforms, with analysis of what they mean for patients, clinicians, and the justice system.",
            "published": (now - timedelta(days=4)).isoformat(),
            "audio_url": "https://example.com/audio/hw002.mp3",
            "duration_seconds": 1980,
            "guid": "hw-ep-002",
            "status": "summarized",
            "scraped_at": (now - timedelta(days=4)).isoformat(),
            "transcribed_at": (now - timedelta(days=3, hours=20)).isoformat(),
            "summarized_at": (now - timedelta(days=3, hours=18)).isoformat(),
            "audio_local_path": None,
            "transcript_key": "pod_healthwatch/ep_hw_002.txt",
            "transcript": "The Mental Health Act 1983 has long been criticised for its disproportionate impact on Black communities...",
            "summary_key": "pod_healthwatch/ep_hw_002.json",
            "summary": {
                "summary": "This episode analyses the draft Mental Health Act reforms, focusing on the removal of learning disability and autism as grounds for detention, new patient choice provisions, and the introduction of statutory advance directives. Psychiatrist Dr Femi Adeyemi explains that while the reforms address longstanding racial disparities in sectioning rates, the proposed community treatment order changes may create new gaps in crisis care. Legal expert Professor Ruth Meredith notes the tension between patient autonomy and public safety, particularly in forensic settings. The episode highlights that despite three years of consultation, key questions about funding for community mental health services remain unanswered, which campaigners say will undermine the legislation's impact.",
                "gist": "Mental Health Act reforms address racial disparities but risk creating care gaps without adequate community funding.",
                "themes": ["Mental Health", "Health Policy", "Racial Disparities", "Patient Rights", "NHS"],
                "key_quotes": [
                    "The Act finally acknowledges what decades of data have shown: Black men are four times more likely to be sectioned than their white counterparts. -- Dr Femi Adeyemi",
                    "Rights on paper mean nothing without services on the ground. -- Mind CEO spokesperson",
                ]
            },
        },
        {
            "id": "ep_hw_003",
            "podcast_id": "pod_healthwatch",
            "title": "Obesity Strategy 2.0: Beyond the Sugar Tax",
            "description": "With childhood obesity rates still climbing, we ask whether the government's refreshed obesity strategy goes far enough.",
            "published": (now - timedelta(days=7)).isoformat(),
            "audio_url": "https://example.com/audio/hw003.mp3",
            "duration_seconds": 2280,
            "guid": "hw-ep-003",
            "status": "summarized",
            "scraped_at": (now - timedelta(days=7)).isoformat(),
            "transcribed_at": (now - timedelta(days=6, hours=20)).isoformat(),
            "summarized_at": (now - timedelta(days=6, hours=18)).isoformat(),
            "audio_local_path": None,
            "transcript_key": "pod_healthwatch/ep_hw_003.txt",
            "transcript": "Five years on from the sugar levy, childhood obesity in England shows no sign of declining...",
            "summary_key": "pod_healthwatch/ep_hw_003.json",
            "summary": {
                "summary": "The episode reviews the government's updated obesity strategy, which introduces advertising restrictions for HFSS foods before 9pm, mandatory calorie labelling in all food outlets, and a new GLP-1 receptor agonist prescribing programme for high-risk patients. Public health professor Dame Sally Holroyd argues that the strategy still lacks teeth on junk food pricing and industry reformulation targets. The programme explores the GLP-1 prescribing expansion, noting that while drugs like semaglutide show remarkable efficacy, the annual per-patient cost of around 2,500 GBP raises questions about NHS affordability at scale. A food industry representative argues that the advertising restrictions will disproportionately harm smaller producers while multinational brands simply shift to digital channels outside regulation.",
                "gist": "Updated obesity strategy introduces advertising bans and GLP-1 prescribing but critics question industry accountability and NHS costs.",
                "themes": ["Public Health", "Obesity", "Health Policy", "Pharma Industry", "Health Economics", "NHS"],
                "key_quotes": [
                    "You cannot tackle obesity with prescription pads alone. This needs a fundamental restructuring of the food environment. -- Dame Sally Holroyd",
                    "At 2,500 per patient per year, prescribing our way out of the obesity crisis would bankrupt the drugs budget. -- NHS England clinical director",
                ]
            },
        },
    ]

    # ------------------------------------------------------------------
    # Episodes -- Medical Myths Debunked
    # ------------------------------------------------------------------
    mm_episodes = [
        {
            "id": "ep_mm_001",
            "podcast_id": "pod_medmyths",
            "title": "Ivermectin in 2026: Why the Myth Persists",
            "description": "Three years after the major trials reported, ivermectin for COVID remains a viral claim. We trace the information ecosystem keeping it alive.",
            "published": (now - timedelta(days=2)).isoformat(),
            "audio_url": "https://example.com/audio/mm001.mp3",
            "duration_seconds": 1860,
            "guid": "mm-ep-001",
            "status": "summarized",
            "scraped_at": (now - timedelta(days=2)).isoformat(),
            "transcribed_at": (now - timedelta(days=1, hours=20)).isoformat(),
            "summarized_at": (now - timedelta(days=1, hours=18)).isoformat(),
            "audio_local_path": None,
            "transcript_key": "pod_medmyths/ep_mm_001.txt",
            "transcript": "Despite the conclusive findings of the PRINCIPLE trial and the TOGETHER trial...",
            "summary_key": "pod_medmyths/ep_mm_001.json",
            "summary": {
                "summary": "The episode investigates why ivermectin advocacy for COVID-19 persists despite definitive negative results from large randomised controlled trials (PRINCIPLE, TOGETHER, ACTIV-6). Misinformation researcher Dr Lydia Marchetti maps the network of substack authors, podcasters, and social media influencers who continue to promote the drug, often reframing the narrative as 'suppressed early treatment' rather than engaging with the evidence. Infectious disease specialist Professor Mark Hensley explains the methodological flaws in the small positive studies that circulate on social media, including confounding by concurrent corticosteroid use and publication bias. The episode draws parallels with historical medical misinformation patterns around laetrile and chelation therapy, suggesting that institutional distrust, not ignorance, drives uptake. Notable is a segment on how the 'ivermectin narrative' has evolved to incorporate broader anti-establishment health claims.",
                "gist": "Ivermectin advocacy persists through networked misinformation and institutional distrust despite conclusive negative trial data.",
                "themes": ["Misinformation", "Medical Research", "Vaccine Debate", "Public Health", "Social Media & Health"],
                "key_quotes": [
                    "The ivermectin story is no longer about ivermectin. It is about whether people trust the institutions that produce medical evidence. -- Dr Lydia Marchetti",
                    "Every small, flawed positive study gets amplified a thousandfold, while the large definitive trials are dismissed as pharma-captured. -- Prof. Mark Hensley",
                ]
            },
        },
        {
            "id": "ep_mm_002",
            "podcast_id": "pod_medmyths",
            "title": "Seed Oils and the New Nutrition Panic",
            "description": "Social media influencers claim seed oils are 'toxic'. We look at what the evidence actually says.",
            "published": (now - timedelta(days=5)).isoformat(),
            "audio_url": "https://example.com/audio/mm002.mp3",
            "duration_seconds": 1680,
            "guid": "mm-ep-002",
            "status": "summarized",
            "scraped_at": (now - timedelta(days=5)).isoformat(),
            "transcribed_at": (now - timedelta(days=4, hours=20)).isoformat(),
            "summarized_at": (now - timedelta(days=4, hours=18)).isoformat(),
            "audio_local_path": None,
            "transcript_key": "pod_medmyths/ep_mm_002.txt",
            "transcript": "The claim that vegetable seed oils are driving chronic disease has exploded on TikTok and X...",
            "summary_key": "pod_medmyths/ep_mm_002.json",
            "summary": {
                "summary": "This episode examines the viral claim that seed oils (canola, sunflower, soybean) are a root cause of chronic disease. Nutritional epidemiologist Dr Hannah Wei reviews the evidence, noting that large meta-analyses consistently show that replacing saturated fat with polyunsaturated fat from seed oils reduces cardiovascular risk. The episode traces the claim's origins to a selective reading of linoleic acid research and the 'ancestral health' movement. Food scientist Dr Raj Patel explains oxidation chemistry and why the 'seed oils are toxic at any dose' claim misrepresents dose-response relationships. However, the episode acknowledges legitimate concerns about ultra-processed food formulations where seed oils are one component in a broader matrix of additives, and notes that the NOVA framework offers a more nuanced lens than demonising a single ingredient.",
                "gist": "Viral anti-seed-oil claims misrepresent evidence; the real concern is ultra-processed food systems, not individual ingredients.",
                "themes": ["Misinformation", "Nutrition", "Public Health", "Social Media & Health"],
                "key_quotes": [
                    "The dose makes the poison. Seed oils at normal dietary levels are not only safe, they are actively protective against heart disease. -- Dr Hannah Wei",
                    "When someone tells you to avoid all seed oils, ask what they are selling. Usually it is butter or coconut oil at three times the price. -- Dr Raj Patel",
                ]
            },
        },
        {
            "id": "ep_mm_003",
            "podcast_id": "pod_medmyths",
            "title": "Raw Milk Revival: Nostalgia vs Microbiology",
            "description": "The raw milk movement is growing. We separate the pastoral marketing from the public health reality.",
            "published": (now - timedelta(days=9)).isoformat(),
            "audio_url": "https://example.com/audio/mm003.mp3",
            "duration_seconds": 1920,
            "guid": "mm-ep-003",
            "status": "summarized",
            "scraped_at": (now - timedelta(days=9)).isoformat(),
            "transcribed_at": (now - timedelta(days=8, hours=20)).isoformat(),
            "summarized_at": (now - timedelta(days=8, hours=18)).isoformat(),
            "audio_local_path": None,
            "transcript_key": "pod_medmyths/ep_mm_003.txt",
            "transcript": "Raw milk sales have doubled in the UK over the past two years...",
            "summary_key": "pod_medmyths/ep_mm_003.json",
            "summary": {
                "summary": "The episode explores the resurgence of raw (unpasteurised) milk consumption, driven by social media claims about superior nutritional value and gut health benefits. Microbiologist Professor Elena Vasquez presents evidence that pasteurisation causes minimal nutrient loss while eliminating pathogens including E. coli O157, Listeria, and Campylobacter -- organisms that have caused documented outbreaks linked to raw milk. The programme examines the regulatory patchwork: raw milk sales are legal from farms in England and Wales but banned in Scotland. A raw milk advocate farmer argues for consumer choice, while a paediatric infectious disease consultant describes treating a child with haemolytic uraemic syndrome from contaminated raw milk. The episode concludes that while the microbiome argument is scientifically intriguing, current evidence does not support raw milk as a meaningful probiotic delivery vehicle compared to proven fermented foods.",
                "gist": "Raw milk's claimed health benefits lack evidence while pasteurisation remains critical for preventing serious foodborne illness.",
                "themes": ["Misinformation", "Public Health", "Food Safety", "Nutrition"],
                "key_quotes": [
                    "Pasteurisation is one of the greatest public health interventions in history. Reversing it based on TikTok testimonials would be catastrophic. -- Prof. Elena Vasquez",
                    "The child I treated nearly died from kidney failure caused by E. coli in raw milk. That is not a matter of consumer choice. -- Dr Aisha Khan",
                ]
            },
        },
    ]

    # ------------------------------------------------------------------
    # Episodes -- Westminster Health Briefing
    # ------------------------------------------------------------------
    wh_episodes = [
        {
            "id": "ep_wh_001",
            "podcast_id": "pod_westminster",
            "title": "Spring Budget Special: Health Spending Decoded",
            "description": "We parse the Spring Budget's health allocations and ask whether the numbers add up for the NHS and social care.",
            "published": (now - timedelta(days=3)).isoformat(),
            "audio_url": "https://example.com/audio/wh001.mp3",
            "duration_seconds": 2100,
            "guid": "wh-ep-001",
            "status": "summarized",
            "scraped_at": (now - timedelta(days=3)).isoformat(),
            "transcribed_at": (now - timedelta(days=2, hours=20)).isoformat(),
            "summarized_at": (now - timedelta(days=2, hours=18)).isoformat(),
            "audio_local_path": None,
            "transcript_key": "pod_westminster/ep_wh_001.txt",
            "transcript": "The Chancellor's Spring Budget allocated an additional 3.2 billion to the NHS...",
            "summary_key": "pod_westminster/ep_wh_001.json",
            "summary": {
                "summary": "The episode provides line-by-line analysis of the Spring Budget's health allocations. The headline 3.2 billion GBP NHS uplift is examined by health economist Dr Laura Griffiths, who calculates that after adjusting for inflation, pay settlements, and demographic pressures, the real-terms increase is closer to 0.8 billion -- well below what the King's Fund estimates is needed to maintain current service levels. The programme reveals that social care received no new funding beyond existing commitments, prompting the Local Government Association to warn of 'a ticking time bomb for hospital discharge'. Political correspondent James Worth reports on behind-the-scenes Treasury tensions, with the Health Secretary reportedly losing a battle for an additional 1.5 billion for capital investment in crumbling hospital estates. The episode also covers the new 200 million 'health innovation fund' for AI and digital health, which opposition critics call 'a vanity announcement dressed up as reform'.",
                "gist": "Spring Budget's NHS uplift is far smaller than it appears once inflation and pay pressures are accounted for.",
                "themes": ["Health Policy", "NHS", "Health Economics", "Political Rhetoric"],
                "key_quotes": [
                    "The headline figure of 3.2 billion sounds generous until you subtract 1.4 billion for the pay deal and 800 million for inflation. -- Dr Laura Griffiths",
                    "Social care is the crack in the dam. Every unfunded care home place becomes a blocked hospital bed. -- LGA spokesperson",
                ]
            },
        },
        {
            "id": "ep_wh_002",
            "podcast_id": "pod_westminster",
            "title": "Tobacco and Vapes Bill: Public Health vs Libertarian Backlash",
            "description": "The generational smoking ban and vape regulations face fierce parliamentary opposition. We examine the evidence on both sides.",
            "published": (now - timedelta(days=6)).isoformat(),
            "audio_url": "https://example.com/audio/wh002.mp3",
            "duration_seconds": 1800,
            "guid": "wh-ep-002",
            "status": "summarized",
            "scraped_at": (now - timedelta(days=6)).isoformat(),
            "transcribed_at": (now - timedelta(days=5, hours=20)).isoformat(),
            "summarized_at": (now - timedelta(days=5, hours=18)).isoformat(),
            "audio_local_path": None,
            "transcript_key": "pod_westminster/ep_wh_002.txt",
            "transcript": "The Tobacco and Vapes Bill would create a rolling ban preventing anyone born after 2009...",
            "summary_key": "pod_westminster/ep_wh_002.json",
            "summary": {
                "summary": "This episode covers the parliamentary debate around the Tobacco and Vapes Bill, which proposes a generational smoking ban and strict regulations on disposable vapes. Public health advocate Professor Sir Nicholas Wald presents modelling showing the ban could prevent 1.7 million smoking-related deaths over 50 years. Conservative backbencher Marcus Hale argues the legislation is 'nanny statism at its most extreme' and raises concerns about black market growth. The programme also examines the vaping provisions: while harm reduction experts support regulated vaping as a smoking cessation tool, paediatric pulmonologist Dr Jennifer Liu presents data on a 340% increase in under-16 vape-related A&E presentations over three years. The episode highlights the unusual cross-party dynamics, with rebel Conservative and Labour MPs forming an unlikely alliance against the bill's libertarian critics.",
                "gist": "Tobacco and Vapes Bill balances projected lives saved against libertarian objections and teenage vaping surge concerns.",
                "themes": ["Health Policy", "Public Health", "Political Rhetoric", "Tobacco & Vaping"],
                "key_quotes": [
                    "1.7 million lives over 50 years. That is the prize for getting this legislation right. -- Prof. Sir Nicholas Wald",
                    "We have exchanged one generation's addiction for another. Disposable vapes are the cigarettes of Gen Alpha. -- Dr Jennifer Liu",
                ]
            },
        },
    ]

    # ------------------------------------------------------------------
    # Episodes -- Global Health Dispatch
    # ------------------------------------------------------------------
    gh_episodes = [
        {
            "id": "ep_gh_001",
            "podcast_id": "pod_globalhealth",
            "title": "WHO Pandemic Treaty: Where Negotiations Stand",
            "description": "An insider's guide to the stalled pandemic treaty talks and what they mean for future outbreak response.",
            "published": (now - timedelta(days=4)).isoformat(),
            "audio_url": "https://example.com/audio/gh001.mp3",
            "duration_seconds": 2400,
            "guid": "gh-ep-001",
            "status": "summarized",
            "scraped_at": (now - timedelta(days=4)).isoformat(),
            "transcribed_at": (now - timedelta(days=3, hours=20)).isoformat(),
            "summarized_at": (now - timedelta(days=3, hours=18)).isoformat(),
            "audio_local_path": None,
            "transcript_key": "pod_globalhealth/ep_gh_001.txt",
            "transcript": "Negotiations on the WHO pandemic treaty entered their seventh round this week...",
            "summary_key": "pod_globalhealth/ep_gh_001.json",
            "summary": {
                "summary": "The episode provides an inside account of WHO pandemic treaty negotiations, now in their seventh round. Key sticking points include pathogen access and benefit sharing (PABS), with low- and middle-income countries demanding guaranteed access to vaccines and therapeutics in exchange for sharing pathogen sequences. WHO legal adviser Dr Maria Santos-Oliveira explains why the US and EU are resisting binding manufacturing transfer obligations, while African Union health representative Dr Kwame Asante argues that without enforceable equity provisions, the treaty will repeat the 'vaccine apartheid' of COVID-19. The programme examines the proposed pandemic fund financing mechanism and reveals that several G7 nations have privately indicated they will sign a watered-down treaty rather than accept the PABS framework sought by the Africa Group and SEARO member states.",
                "gist": "WHO pandemic treaty stalls on equity provisions as wealthy nations resist binding commitments to share vaccines and technology.",
                "themes": ["Global Health", "Health Policy", "Health Equity", "Pandemic Preparedness"],
                "key_quotes": [
                    "A pandemic treaty without enforceable equity provisions is a gentleman's agreement that will collapse at the first outbreak. -- Dr Kwame Asante",
                    "The political will that existed in 2021 has evaporated. We are now negotiating the minimum viable treaty. -- Dr Maria Santos-Oliveira",
                ]
            },
        },
        {
            "id": "ep_gh_002",
            "podcast_id": "pod_globalhealth",
            "title": "Antimicrobial Resistance: The Silent Pandemic Progress Report",
            "description": "A year after the UN High-Level Meeting on AMR, we assess what has actually changed.",
            "published": (now - timedelta(days=8)).isoformat(),
            "audio_url": "https://example.com/audio/gh002.mp3",
            "duration_seconds": 2040,
            "guid": "gh-ep-002",
            "status": "summarized",
            "scraped_at": (now - timedelta(days=8)).isoformat(),
            "transcribed_at": (now - timedelta(days=7, hours=20)).isoformat(),
            "summarized_at": (now - timedelta(days=7, hours=18)).isoformat(),
            "audio_local_path": None,
            "transcript_key": "pod_globalhealth/ep_gh_002.txt",
            "transcript": "One year on from the UN High-Level Meeting on antimicrobial resistance...",
            "summary_key": "pod_globalhealth/ep_gh_002.json",
            "summary": {
                "summary": "This episode assesses progress on antimicrobial resistance (AMR) one year after the UN High-Level Meeting pledged to reduce AMR deaths by 10% by 2030. Infectious disease epidemiologist Professor Chris Murray presents updated GRAM data showing drug-resistant infections now directly cause an estimated 1.4 million deaths annually, with sub-Saharan Africa and South Asia bearing the greatest burden. The episode examines why the antibiotic development pipeline remains critically thin -- only 13 new antibiotics are in Phase 3 trials, and most target gram-positive organisms, not the gram-negative pathogens causing the greatest mortality. Health economist Dr Priya Sharma explains how subscription-based 'Netflix models' for antibiotic procurement, pioneered by Sweden and the UK, could delink revenue from volume and incentivise development. The episode also covers the agricultural sector, where antibiotic use in livestock remains largely unregulated in many low-income countries.",
                "gist": "AMR death toll continues to rise as the antibiotic pipeline stalls and agricultural overuse remains unregulated globally.",
                "themes": ["Global Health", "Medical Research", "Pharma Industry", "Health Economics", "Public Health"],
                "key_quotes": [
                    "AMR is the slowest-moving pandemic in history, and we are responding with the urgency of a committee meeting. -- Prof. Chris Murray",
                    "The Netflix model works in theory, but we need 20 countries to adopt it, not two. -- Dr Priya Sharma",
                ]
            },
        },
    ]

    # ------------------------------------------------------------------
    # Store episode data and transcripts/summaries
    # ------------------------------------------------------------------
    all_episode_sets = [
        ("pod_healthwatch", hw_episodes),
        ("pod_medmyths", mm_episodes),
        ("pod_westminster", wh_episodes),
        ("pod_globalhealth", gh_episodes),
    ]

    for podcast_id, episodes in all_episode_sets:
        _save_episodes(podcast_id, episodes)

        for ep in episodes:
            # Store transcript stub
            if ep.get("transcript_key"):
                storage.put_object(
                    "transcripts", ep["transcript_key"],
                    ep.get("transcript", "[Demo transcript placeholder]")
                )
            # Store summary
            if ep.get("summary_key") and ep.get("summary"):
                storage.put_object("summaries", ep["summary_key"], ep["summary"])

    # ------------------------------------------------------------------
    # Distribution lists
    # ------------------------------------------------------------------
    cfg = app_config.load_config()
    cfg["distribution_lists"] = {
        "daily": [
            "editor@bmj.com",
            "news.desk@bmj.com",
            "health.policy@bmj.com",
        ],
        "weekly": [
            "editor-in-chief@bmj.com",
            "editorial.board@bmj.com",
            "strategy@bmj.com",
        ],
    }
    app_config.save_config(cfg)

    logger.info("Demo data seeded successfully")
    return jsonify({
        "message": "Demo data seeded successfully",
        "podcasts": len(podcasts),
        "episodes": sum(len(eps) for _, eps in all_episode_sets),
    }), 201


# ===================================================================
#  Error handlers
# ===================================================================

@app.errorhandler(404)
def not_found(e):
    return jsonify({"error": "Not found"}), 404


@app.errorhandler(500)
def internal_error(e):
    logger.exception("Internal server error")
    return jsonify({"error": "Internal server error"}), 500


# ===================================================================
#  Entry point
# ===================================================================

if __name__ == "__main__":
    # Ensure data directories exist on startup
    app_config.load_config()

    port = int(os.environ.get("PORT", 5001))
    debug = os.environ.get("FLASK_DEBUG", "1") == "1"

    logger.info("Starting NYT Pod Scraper backend on port %d (debug=%s)", port, debug)
    app.run(host="0.0.0.0", port=port, debug=debug)
