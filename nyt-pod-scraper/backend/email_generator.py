"""
Email generation and delivery module.

Uses Jinja2 templates to render daily and weekly digest emails as HTML,
and provides SMTP delivery as well as local preview functionality.
"""

import logging
import os
import smtplib
import tempfile
import webbrowser
from datetime import datetime, timezone
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from pathlib import Path
from typing import Any, Dict, List, Optional

from jinja2 import Environment, FileSystemLoader, select_autoescape

from config import load_config

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Template directory -- defaults to ``templates/`` next to the backend code,
# but can be overridden by the config.
# ---------------------------------------------------------------------------
_BACKEND_DIR = Path(__file__).resolve().parent
_DEFAULT_TEMPLATE_DIR = _BACKEND_DIR.parent / "templates"


def _get_jinja_env(template_dir: Optional[str] = None) -> Environment:
    """Create a Jinja2 environment pointing at the template directory.

    If the directory does not yet exist we create it and write built-in
    default templates so the application works out of the box.

    Args:
        template_dir: Absolute path to the template directory.  Falls
            back to the project ``templates/`` directory.

    Returns:
        A configured :class:`jinja2.Environment`.
    """
    tpl_dir = Path(template_dir) if template_dir else _DEFAULT_TEMPLATE_DIR
    tpl_dir.mkdir(parents=True, exist_ok=True)

    # Ensure default templates exist
    _ensure_default_templates(tpl_dir)

    return Environment(
        loader=FileSystemLoader(str(tpl_dir)),
        autoescape=select_autoescape(["html", "xml"]),
    )


# ---------------------------------------------------------------------------
# Built-in default templates
# ---------------------------------------------------------------------------

_DAILY_EMAIL_TEMPLATE = """\
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1.0"/>
<title>{{ headline | default('BMJ Daily Podcast Digest') }}</title>
<style>
  body { font-family: Georgia, 'Times New Roman', serif; margin: 0; padding: 0; background: #f4f4f4; color: #222; }
  .wrapper { max-width: 680px; margin: 0 auto; background: #fff; }
  .header { background: #1a3c5e; color: #fff; padding: 28px 32px 20px; }
  .header h1 { margin: 0 0 6px; font-size: 22px; font-weight: 700; }
  .header .date { font-size: 13px; opacity: 0.85; }
  .body { padding: 28px 32px; }
  .body h2 { font-size: 18px; color: #1a3c5e; border-bottom: 2px solid #d4a843; padding-bottom: 6px; margin-top: 28px; }
  .overview { font-size: 15px; line-height: 1.65; color: #333; }
  .podcast-brief { background: #f9f7f2; border-left: 4px solid #d4a843; padding: 14px 18px; margin: 14px 0; }
  .podcast-brief .name { font-weight: 700; color: #1a3c5e; font-size: 14px; }
  .podcast-brief .episode { font-style: italic; font-size: 13px; color: #555; }
  .podcast-brief .liner { font-size: 14px; margin-top: 6px; line-height: 1.5; }
  .themes { display: flex; flex-wrap: wrap; gap: 6px; margin: 12px 0; }
  .theme-tag { background: #e8e0cf; color: #4a3f2f; padding: 4px 12px; border-radius: 14px; font-size: 12px; }
  .alert { background: #fdf0e6; border-left: 4px solid #c0392b; padding: 12px 16px; margin: 10px 0; font-size: 14px; }
  .footer { background: #f0ece4; padding: 18px 32px; font-size: 12px; color: #888; text-align: center; }
  .footer a { color: #1a3c5e; }
</style>
</head>
<body>
<div class="wrapper">
  <div class="header">
    <h1>{{ headline | default('BMJ Daily Podcast Digest') }}</h1>
    <div class="date">{{ date | default('Today') }}</div>
  </div>
  <div class="body">
    <div class="overview">{{ overview | default('') }}</div>

    {% if common_themes %}
    <h2>Common Themes</h2>
    <div class="themes">
      {% for theme in common_themes %}
      <span class="theme-tag">{{ theme }}</span>
      {% endfor %}
    </div>
    {% endif %}

    {% if alerts %}
    <h2>Editorial Alerts</h2>
    {% for alert in alerts %}
    <div class="alert">{{ alert }}</div>
    {% endfor %}
    {% endif %}

    {% if podcast_briefs %}
    <h2>Podcast Briefs</h2>
    {% for brief in podcast_briefs %}
    <div class="podcast-brief">
      <div class="name">{{ brief.podcast_name | default('Podcast') }}</div>
      <div class="episode">{{ brief.episode_title | default('') }}</div>
      <div class="liner">{{ brief.one_liner | default('') }}</div>
    </div>
    {% endfor %}
    {% endif %}
  </div>
  <div class="footer">
    BMJ Editorial Intelligence &middot; Podcast Monitoring Service<br/>
    <a href="#">Manage preferences</a> &middot; <a href="#">Unsubscribe</a>
  </div>
</div>
</body>
</html>
"""

_WEEKLY_EMAIL_TEMPLATE = """\
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1.0"/>
<title>{{ headline | default('BMJ Weekly Podcast Intelligence') }}</title>
<style>
  body { font-family: Georgia, 'Times New Roman', serif; margin: 0; padding: 0; background: #f4f4f4; color: #222; }
  .wrapper { max-width: 680px; margin: 0 auto; background: #fff; }
  .header { background: #1a3c5e; color: #fff; padding: 28px 32px 20px; }
  .header h1 { margin: 0 0 6px; font-size: 22px; font-weight: 700; }
  .header .subtitle { font-size: 14px; opacity: 0.85; }
  .header .date { font-size: 13px; opacity: 0.7; margin-top: 4px; }
  .body { padding: 28px 32px; }
  .body h2 { font-size: 18px; color: #1a3c5e; border-bottom: 2px solid #d4a843; padding-bottom: 6px; margin-top: 28px; }
  .exec-summary { font-size: 15px; line-height: 1.65; color: #333; }
  .trend { background: #f9f7f2; padding: 14px 18px; margin: 10px 0; border-left: 4px solid #d4a843; }
  .trend .theme-name { font-weight: 700; color: #1a3c5e; }
  .trend .trajectory { font-size: 12px; display: inline-block; padding: 2px 8px; border-radius: 10px; margin-left: 8px; }
  .trend .trajectory.rising { background: #e8f5e9; color: #2e7d32; }
  .trend .trajectory.steady { background: #fff3e0; color: #e65100; }
  .trend .trajectory.declining { background: #fce4ec; color: #c62828; }
  .trend .desc { font-size: 14px; margin-top: 6px; line-height: 1.5; }
  .arc { background: #f0f4f8; padding: 14px 18px; margin: 10px 0; border-radius: 6px; }
  .arc .title { font-weight: 700; color: #1a3c5e; font-size: 15px; }
  .arc .description { font-size: 14px; margin-top: 4px; line-height: 1.5; }
  .action { padding: 8px 0; font-size: 14px; border-bottom: 1px solid #eee; }
  .action:last-child { border-bottom: none; }
  .footer { background: #f0ece4; padding: 18px 32px; font-size: 12px; color: #888; text-align: center; }
  .footer a { color: #1a3c5e; }
</style>
</head>
<body>
<div class="wrapper">
  <div class="header">
    <h1>{{ headline | default('BMJ Weekly Podcast Intelligence') }}</h1>
    <div class="subtitle">Weekly Meta-Analysis &amp; Trend Report</div>
    <div class="date">{{ date_range | default('This Week') }}</div>
  </div>
  <div class="body">
    <div class="exec-summary">{{ executive_summary | default('') }}</div>

    {% if trending_themes %}
    <h2>Trending Themes</h2>
    {% for t in trending_themes %}
    <div class="trend">
      <span class="theme-name">{{ t.theme }}</span>
      <span class="trajectory {{ t.trajectory | default('steady') }}">{{ t.trajectory | default('steady') | upper }}</span>
      <div class="desc">{{ t.summary | default('') }}</div>
    </div>
    {% endfor %}
    {% endif %}

    {% if narrative_arcs %}
    <h2>Narrative Arcs</h2>
    {% for arc in narrative_arcs %}
    <div class="arc">
      <div class="title">{{ arc.title }}</div>
      <div class="description">{{ arc.description }}</div>
    </div>
    {% endfor %}
    {% endif %}

    {% if recommended_actions %}
    <h2>Recommended Editorial Actions</h2>
    {% for action in recommended_actions %}
    <div class="action">{{ action }}</div>
    {% endfor %}
    {% endif %}
  </div>
  <div class="footer">
    BMJ Editorial Intelligence &middot; Weekly Podcast Intelligence Report<br/>
    <a href="#">Manage preferences</a> &middot; <a href="#">Unsubscribe</a>
  </div>
</div>
</body>
</html>
"""


def _ensure_default_templates(tpl_dir: Path) -> None:
    """Write built-in templates to disk if they do not already exist.

    Args:
        tpl_dir: The templates directory.
    """
    daily_path = tpl_dir / "daily_email.html"
    weekly_path = tpl_dir / "weekly_email.html"

    if not daily_path.exists():
        daily_path.write_text(_DAILY_EMAIL_TEMPLATE, encoding="utf-8")
        logger.info("Wrote default daily email template to %s", daily_path)

    if not weekly_path.exists():
        weekly_path.write_text(_WEEKLY_EMAIL_TEMPLATE, encoding="utf-8")
        logger.info("Wrote default weekly email template to %s", weekly_path)


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

def render_daily_email(digest_data: Dict[str, Any],
                       template_path: Optional[str] = None) -> str:
    """Render a daily digest email as HTML.

    Args:
        digest_data: The daily digest dict (from :func:`summarizer.generate_daily_digest`).
        template_path: Optional override for the template directory.

    Returns:
        Rendered HTML string.
    """
    env = _get_jinja_env(template_path)
    template = env.get_template("daily_email.html")

    context = dict(digest_data)
    context.setdefault("date", datetime.now(timezone.utc).strftime("%A, %d %B %Y"))
    context.setdefault("headline", "BMJ Daily Podcast Digest")

    html = template.render(**context)
    logger.info("Rendered daily email (%d bytes)", len(html))
    return html


def render_weekly_email(digest_data: Dict[str, Any],
                        template_path: Optional[str] = None) -> str:
    """Render a weekly digest email as HTML.

    Args:
        digest_data: The weekly digest dict (from :func:`summarizer.generate_weekly_digest`).
        template_path: Optional override for the template directory.

    Returns:
        Rendered HTML string.
    """
    env = _get_jinja_env(template_path)
    template = env.get_template("weekly_email.html")

    context = dict(digest_data)
    context.setdefault("date_range", "This Week")
    context.setdefault("headline", "BMJ Weekly Podcast Intelligence")

    html = template.render(**context)
    logger.info("Rendered weekly email (%d bytes)", len(html))
    return html


# ---------------------------------------------------------------------------
# Preview
# ---------------------------------------------------------------------------

def preview_email(html_content: str) -> str:
    """Save rendered HTML to a temp file for browser preview.

    Args:
        html_content: The rendered HTML string.

    Returns:
        The absolute path to the saved HTML file.
    """
    cfg = load_config()
    emails_dir = Path(cfg.get("emails_dir", "data/emails"))
    emails_dir.mkdir(parents=True, exist_ok=True)

    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    preview_path = emails_dir / f"preview_{timestamp}.html"
    preview_path.write_text(html_content, encoding="utf-8")

    logger.info("Email preview saved to %s", preview_path)
    return str(preview_path)


# ---------------------------------------------------------------------------
# SMTP delivery
# ---------------------------------------------------------------------------

def send_email(html_content: str,
               recipients: List[str],
               subject: str,
               smtp_config: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    """Send an HTML email via SMTP.

    Args:
        html_content: The rendered HTML email body.
        recipients: List of recipient email addresses.
        subject: Email subject line.
        smtp_config: SMTP configuration dict.  If ``None``, values are
            loaded from the application config.

    Returns:
        A result dict with ``success`` (bool), ``sent_to`` (list), and
        ``errors`` (list).
    """
    if not recipients:
        return {"success": False, "sent_to": [], "errors": ["No recipients specified."]}

    cfg = load_config()
    smtp = smtp_config or {}
    server_host = smtp.get("smtp_server") or cfg.get("smtp_server", "smtp.gmail.com")
    server_port = smtp.get("smtp_port") or cfg.get("smtp_port", 587)
    use_tls = smtp.get("smtp_use_tls", cfg.get("smtp_use_tls", True))
    username = smtp.get("smtp_username") or cfg.get("smtp_username", "")
    password = smtp.get("smtp_password") or cfg.get("smtp_password", "")
    sender = smtp.get("email_sender") or cfg.get("email_sender", "nyt-pod-scraper@bmj.com")
    sender_name = smtp.get("email_sender_name") or cfg.get("email_sender_name", "BMJ Pod Digest")

    if not username or not password:
        logger.warning(
            "SMTP credentials not configured. Saving email to disk instead."
        )
        path = preview_email(html_content)
        return {
            "success": False,
            "sent_to": [],
            "errors": [
                "SMTP credentials not configured. "
                f"Email saved to {path} for preview."
            ],
            "preview_path": path,
        }

    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = f"{sender_name} <{sender}>"
    msg["To"] = ", ".join(recipients)

    # Attach HTML part
    msg.attach(MIMEText(html_content, "html", "utf-8"))

    # Also attach a plain-text fallback
    plain = (
        f"{subject}\n\n"
        "This email is best viewed in an HTML-capable email client.\n"
        "Please enable HTML display or view online."
    )
    msg.attach(MIMEText(plain, "plain", "utf-8"))

    errors: List[str] = []
    sent: List[str] = []

    try:
        logger.info("Connecting to SMTP %s:%d ...", server_host, server_port)
        with smtplib.SMTP(server_host, server_port, timeout=30) as smtp_conn:
            smtp_conn.ehlo()
            if use_tls:
                smtp_conn.starttls()
                smtp_conn.ehlo()
            smtp_conn.login(username, password)

            for rcpt in recipients:
                try:
                    smtp_conn.sendmail(sender, rcpt, msg.as_string())
                    sent.append(rcpt)
                    logger.info("Email sent to %s", rcpt)
                except smtplib.SMTPRecipientsRefused as exc:
                    errors.append(f"Refused: {rcpt} -- {exc}")
                    logger.error("Recipient refused: %s", rcpt)

    except smtplib.SMTPAuthenticationError as exc:
        errors.append(f"SMTP authentication failed: {exc}")
        logger.error("SMTP auth failed: %s", exc)
    except Exception as exc:
        errors.append(f"SMTP error: {exc}")
        logger.exception("SMTP delivery failed")

    return {
        "success": len(sent) > 0,
        "sent_to": sent,
        "errors": errors,
    }
