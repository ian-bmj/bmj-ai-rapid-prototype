"""
Multi-LLM summarisation module.

Supports OpenAI, Anthropic (Claude), and Google (Gemini) as LLM
providers.  Each provider is accessed through a thin adapter so the
calling code does not need to know the specifics of each SDK.

The module exposes three tiers of summarisation:

1. **Episode-level** -- a single transcript is distilled into a
   summary, one-line gist, thematic tags, and key quotes.
2. **Daily digest** -- multiple episode summaries from the same day
   are synthesised into a cross-podcast briefing.
3. **Weekly digest** -- daily digests are aggregated into a weekly
   meta-analysis with trend identification.

All prompts are tuned for journalism / editorial use cases at the BMJ.
"""

import json
import logging
import os
from typing import Any, Dict, List, Optional

from config import load_config

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Prompt templates
# ---------------------------------------------------------------------------

_EPISODE_SYSTEM_PROMPT = (
    "You are an expert media analyst working for the BMJ (British Medical "
    "Journal) editorial intelligence team. Your role is to monitor podcasts "
    "that discuss health policy, medical science, public health, politics "
    "and the media landscape. You produce concise, accurate, and "
    "journalistically useful briefings for senior editors."
)

_EPISODE_USER_PROMPT = """\
Analyse the following podcast transcript and produce a structured JSON \
response with exactly these keys:

1. **summary** -- A 150-250 word editorial summary highlighting the most \
newsworthy and editorially relevant points. Focus on claims about health \
policy, medical evidence, public health measures, political narratives, \
and any misinformation or contested claims.

2. **gist** -- A single sentence (max 30 words) capturing the core \
takeaway of the episode.

3. **themes** -- A JSON array of 3-7 thematic tags (strings) that \
categorise the episode content. Use consistent taxonomy such as: \
"Health Policy", "Misinformation", "Vaccine Debate", "Mental Health", \
"NHS", "Pharma Industry", "Political Rhetoric", "Gender & Health", \
"Public Health", "Medical Research", "Health Economics", \
"Editorial Independence", "Climate & Health".

4. **key_quotes** -- A JSON array of 2-4 direct or near-direct quotes \
from the transcript that are most editorially significant. Each quote \
should be a string.

Return ONLY valid JSON with no markdown fencing, no commentary, and no \
extra keys.

--- TRANSCRIPT START ---
{transcript}
--- TRANSCRIPT END ---
"""

_DAILY_DIGEST_SYSTEM_PROMPT = (
    "You are the BMJ's daily podcast intelligence analyst. You synthesise "
    "summaries from multiple podcasts into a single cross-show briefing "
    "that highlights common narratives, contradictions, emerging themes, "
    "and anything the editorial team should be aware of."
)

_DAILY_DIGEST_USER_PROMPT = """\
Below are episode summaries from today's monitored podcasts.

Produce a structured JSON response with these keys:

1. **headline** -- An editorial headline (max 15 words) for today's digest.

2. **overview** -- A 200-300 word narrative overview of the day's podcast \
landscape, noting cross-show themes, notable disagreements, and any \
claims that warrant fact-checking or editorial attention.

3. **common_themes** -- A JSON array of themes that appeared across \
multiple podcasts today, each as a string.

4. **alerts** -- A JSON array of items requiring urgent editorial \
attention (e.g. health misinformation, breaking policy changes, \
significant claims about BMJ or medical research).

5. **podcast_briefs** -- A JSON array of objects, one per podcast, each \
with keys "podcast_name", "episode_title", and "one_liner" (a single \
sentence summary).

Return ONLY valid JSON.

--- EPISODE SUMMARIES ---
{summaries_text}
--- END ---
"""

_WEEKLY_DIGEST_SYSTEM_PROMPT = (
    "You are the BMJ's weekly podcast intelligence strategist. You produce "
    "a meta-analysis of the week's daily digests, identifying macro trends, "
    "narrative arcs, and strategic insights for the editorial board."
)

_WEEKLY_DIGEST_USER_PROMPT = """\
Below are the daily podcast digests from this week.

Produce a structured JSON response with these keys:

1. **headline** -- A strategic headline (max 15 words) for the week.

2. **executive_summary** -- A 300-400 word executive briefing for the \
editorial board. Identify the dominant narratives, how they evolved \
over the week, and their implications for BMJ coverage.

3. **trending_themes** -- A JSON array of themes that gained momentum \
across the week, each as an object with keys "theme", "trajectory" \
(one of "rising", "steady", "declining"), and "summary" (one sentence).

4. **narrative_arcs** -- A JSON array of multi-day story arcs, each \
with keys "title" and "description".

5. **recommended_actions** -- A JSON array of editorial recommendations \
(strings) based on the week's podcast intelligence.

Return ONLY valid JSON.

--- DAILY DIGESTS ---
{digests_text}
--- END ---
"""


# ---------------------------------------------------------------------------
# LLM client factory
# ---------------------------------------------------------------------------

def get_llm_client(provider: str, api_key: str) -> Any:
    """Instantiate and return an LLM client for the given provider.

    Args:
        provider: One of ``"openai"``, ``"anthropic"``, or ``"google"``.
        api_key: The API key for the provider.

    Returns:
        A provider-specific client object.

    Raises:
        ValueError: If the provider is unknown.
        ImportError: If the required SDK is not installed.
    """
    provider = provider.lower().strip()

    if provider == "openai":
        from openai import OpenAI
        return OpenAI(api_key=api_key)

    if provider == "anthropic":
        from anthropic import Anthropic
        return Anthropic(api_key=api_key)

    if provider == "google":
        from google import genai
        client = genai.Client(api_key=api_key)
        return client

    raise ValueError(f"Unknown LLM provider: {provider!r}")


def _call_llm(provider: str, client: Any, model: str,
              system_prompt: str, user_prompt: str) -> str:
    """Send a prompt to the configured LLM and return the raw text response.

    Args:
        provider: Provider name.
        client: The client returned by :func:`get_llm_client`.
        model: Model identifier (e.g. ``"gpt-4o"``).
        system_prompt: System-level instruction.
        user_prompt: The user message containing the actual task.

    Returns:
        The model's response text.

    Raises:
        RuntimeError: If the API call fails.
    """
    provider = provider.lower().strip()
    logger.info("Calling %s model=%s  (prompt length: %d chars)",
                provider, model, len(user_prompt))

    try:
        if provider == "openai":
            response = client.chat.completions.create(
                model=model,
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt},
                ],
                temperature=0.3,
                max_tokens=4096,
            )
            return response.choices[0].message.content

        if provider == "anthropic":
            response = client.messages.create(
                model=model,
                max_tokens=4096,
                system=system_prompt,
                messages=[
                    {"role": "user", "content": user_prompt},
                ],
            )
            return response.content[0].text

        if provider == "google":
            response = client.models.generate_content(
                model=model,
                contents=f"{system_prompt}\n\n{user_prompt}",
            )
            return response.text

    except Exception as exc:
        logger.exception("LLM call failed (provider=%s, model=%s)", provider, model)
        raise RuntimeError(f"LLM call failed: {exc}") from exc

    raise ValueError(f"Unsupported provider in _call_llm: {provider!r}")


def _parse_json_response(text: str) -> dict:
    """Best-effort parse of JSON from an LLM response.

    Handles common issues like markdown code fencing around JSON.

    Args:
        text: Raw LLM response text.

    Returns:
        Parsed dict.
    """
    text = text.strip()

    # Strip markdown code fences if present
    if text.startswith("```"):
        lines = text.split("\n")
        # Remove first and last lines (fences)
        if lines[0].startswith("```"):
            lines = lines[1:]
        if lines and lines[-1].strip() == "```":
            lines = lines[:-1]
        text = "\n".join(lines).strip()

    try:
        return json.loads(text)
    except json.JSONDecodeError:
        # Try to extract JSON from the response
        start = text.find("{")
        end = text.rfind("}") + 1
        if start >= 0 and end > start:
            try:
                return json.loads(text[start:end])
            except json.JSONDecodeError:
                pass

        logger.warning("Failed to parse LLM response as JSON. Returning raw text.")
        return {
            "summary": text,
            "gist": "Parse error -- see summary for raw LLM output.",
            "themes": [],
            "key_quotes": [],
        }


# ---------------------------------------------------------------------------
# Public summarisation functions
# ---------------------------------------------------------------------------

def summarize_transcript(transcript: str,
                         provider: Optional[str] = None,
                         api_key: Optional[str] = None,
                         model: Optional[str] = None) -> Dict[str, Any]:
    """Generate a structured summary from a podcast transcript.

    Args:
        transcript: The full transcript text.
        provider: LLM provider name (defaults to config value).
        api_key: API key (defaults to config / environment).
        model: Model identifier (defaults to config value).

    Returns:
        A dict with keys ``summary``, ``gist``, ``themes``, and
        ``key_quotes``.
    """
    cfg = load_config()
    provider = provider or cfg.get("llm_provider", "openai")
    api_key = api_key or cfg.get("llm_api_key", "")
    model = model or cfg.get("llm_models", {}).get(provider) or cfg.get("llm_model", "gpt-4o")

    if not api_key:
        api_key = os.environ.get("OPENAI_API_KEY") or os.environ.get(
            "ANTHROPIC_API_KEY") or os.environ.get("GOOGLE_API_KEY") or ""

    if not api_key:
        logger.warning("No API key available -- returning placeholder summary.")
        return _placeholder_episode_summary(transcript)

    # Truncate very long transcripts to stay within context windows
    max_chars = 100_000
    if len(transcript) > max_chars:
        logger.warning("Transcript truncated from %d to %d chars", len(transcript), max_chars)
        transcript = transcript[:max_chars] + "\n\n[...transcript truncated...]"

    client = get_llm_client(provider, api_key)
    user_prompt = _EPISODE_USER_PROMPT.format(transcript=transcript)
    raw = _call_llm(provider, client, model, _EPISODE_SYSTEM_PROMPT, user_prompt)

    result = _parse_json_response(raw)
    # Ensure expected keys exist
    result.setdefault("summary", "")
    result.setdefault("gist", "")
    result.setdefault("themes", [])
    result.setdefault("key_quotes", [])

    return result


def generate_daily_digest(summaries: List[Dict[str, Any]],
                          provider: Optional[str] = None,
                          api_key: Optional[str] = None,
                          model: Optional[str] = None) -> Dict[str, Any]:
    """Generate a cross-podcast daily digest.

    Args:
        summaries: A list of episode summary dicts, each with at least
            ``podcast_name``, ``episode_title``, and ``summary`` keys.
        provider: LLM provider name.
        api_key: API key.
        model: Model identifier.

    Returns:
        A dict with keys ``headline``, ``overview``, ``common_themes``,
        ``alerts``, and ``podcast_briefs``.
    """
    cfg = load_config()
    provider = provider or cfg.get("llm_provider", "openai")
    api_key = api_key or cfg.get("llm_api_key", "")
    model = model or cfg.get("llm_models", {}).get(provider) or cfg.get("llm_model", "gpt-4o")

    if not api_key:
        api_key = os.environ.get("OPENAI_API_KEY") or os.environ.get(
            "ANTHROPIC_API_KEY") or os.environ.get("GOOGLE_API_KEY") or ""

    # Build text block from summaries
    parts = []
    for s in summaries:
        parts.append(
            f"Podcast: {s.get('podcast_name', 'Unknown')}\n"
            f"Episode: {s.get('episode_title', 'Unknown')}\n"
            f"Summary: {s.get('summary', '')}\n"
            f"Themes: {', '.join(s.get('themes', []))}\n"
        )
    summaries_text = "\n---\n".join(parts)

    if not api_key:
        logger.warning("No API key available -- returning placeholder daily digest.")
        return _placeholder_daily_digest(summaries)

    client = get_llm_client(provider, api_key)
    user_prompt = _DAILY_DIGEST_USER_PROMPT.format(summaries_text=summaries_text)
    raw = _call_llm(provider, client, model, _DAILY_DIGEST_SYSTEM_PROMPT, user_prompt)

    result = _parse_json_response(raw)
    result.setdefault("headline", "Daily Podcast Digest")
    result.setdefault("overview", "")
    result.setdefault("common_themes", [])
    result.setdefault("alerts", [])
    result.setdefault("podcast_briefs", [])

    return result


def generate_weekly_digest(daily_digests: List[Dict[str, Any]],
                           provider: Optional[str] = None,
                           api_key: Optional[str] = None,
                           model: Optional[str] = None) -> Dict[str, Any]:
    """Generate a weekly meta-analysis from daily digests.

    Args:
        daily_digests: A list of daily digest dicts.
        provider: LLM provider name.
        api_key: API key.
        model: Model identifier.

    Returns:
        A dict with keys ``headline``, ``executive_summary``,
        ``trending_themes``, ``narrative_arcs``, and
        ``recommended_actions``.
    """
    cfg = load_config()
    provider = provider or cfg.get("llm_provider", "openai")
    api_key = api_key or cfg.get("llm_api_key", "")
    model = model or cfg.get("llm_models", {}).get(provider) or cfg.get("llm_model", "gpt-4o")

    if not api_key:
        api_key = os.environ.get("OPENAI_API_KEY") or os.environ.get(
            "ANTHROPIC_API_KEY") or os.environ.get("GOOGLE_API_KEY") or ""

    # Build text from daily digests
    parts = []
    for i, d in enumerate(daily_digests, 1):
        parts.append(
            f"Day {i}: {d.get('headline', 'No headline')}\n"
            f"Overview: {d.get('overview', '')}\n"
            f"Common Themes: {', '.join(d.get('common_themes', []))}\n"
        )
    digests_text = "\n---\n".join(parts)

    if not api_key:
        logger.warning("No API key available -- returning placeholder weekly digest.")
        return _placeholder_weekly_digest(daily_digests)

    client = get_llm_client(provider, api_key)
    user_prompt = _WEEKLY_DIGEST_USER_PROMPT.format(digests_text=digests_text)
    raw = _call_llm(provider, client, model, _WEEKLY_DIGEST_SYSTEM_PROMPT, user_prompt)

    result = _parse_json_response(raw)
    result.setdefault("headline", "Weekly Podcast Intelligence Briefing")
    result.setdefault("executive_summary", "")
    result.setdefault("trending_themes", [])
    result.setdefault("narrative_arcs", [])
    result.setdefault("recommended_actions", [])

    return result


# ---------------------------------------------------------------------------
# Placeholder generators (used when no API key is available)
# ---------------------------------------------------------------------------

def _placeholder_episode_summary(transcript: str) -> Dict[str, Any]:
    """Return a realistic placeholder episode summary."""
    word_count = len(transcript.split())
    return {
        "summary": (
            "This is a placeholder summary generated because no LLM API key "
            "was configured. In production, this would contain a 150-250 word "
            f"editorial summary of the transcript ({word_count} words). "
            "Configure an API key in Settings to enable real summarisation."
        ),
        "gist": "Placeholder gist -- configure an LLM API key to enable summarisation.",
        "themes": ["Placeholder"],
        "key_quotes": [
            "No quotes extracted -- LLM API key required for real analysis."
        ],
    }


def _placeholder_daily_digest(summaries: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Return a realistic placeholder daily digest."""
    briefs = []
    for s in summaries:
        briefs.append({
            "podcast_name": s.get("podcast_name", "Unknown"),
            "episode_title": s.get("episode_title", "Unknown"),
            "one_liner": s.get("gist", "No gist available."),
        })

    return {
        "headline": "Daily Digest Placeholder",
        "overview": (
            "This is a placeholder daily digest. Configure an LLM API key "
            f"to generate a real cross-podcast analysis of {len(summaries)} "
            "episode summaries."
        ),
        "common_themes": ["Placeholder"],
        "alerts": [],
        "podcast_briefs": briefs,
    }


def _placeholder_weekly_digest(daily_digests: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Return a realistic placeholder weekly digest."""
    return {
        "headline": "Weekly Digest Placeholder",
        "executive_summary": (
            "This is a placeholder weekly digest. Configure an LLM API key "
            f"to generate a real meta-analysis of {len(daily_digests)} daily "
            "digests."
        ),
        "trending_themes": [
            {"theme": "Placeholder", "trajectory": "steady",
             "summary": "No real analysis available."}
        ],
        "narrative_arcs": [],
        "recommended_actions": [
            "Configure an LLM API key to enable real weekly analysis."
        ],
    }
