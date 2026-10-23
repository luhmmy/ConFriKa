"""Transactional email delivery via a provider HTTP API.

Uses only the Python standard library (urllib) so it adds no dependency to the
image. Supported providers: Resend, SendGrid, Mailgun. When no API key is
configured the message is logged instead of sent (dev mode), and the caller is
told it was not delivered so it can surface the code for local testing.
"""
from __future__ import annotations

import asyncio
import base64
import json
import logging
import urllib.error
import urllib.parse
import urllib.request
from typing import Optional

from ..config.settings import settings

logger = logging.getLogger("confrika.email")

_TIMEOUT = 15


def _post(url: str, *, data: bytes, headers: dict) -> tuple[int, str]:
    # A real User-Agent is required: provider edges (Cloudflare) block the
    # default "Python-urllib" signature with HTTP 403 "error code: 1010".
    headers.setdefault("User-Agent", "ConFriKa-Backend/1.0 (+https://confrika.com)")
    headers.setdefault("Accept", "application/json")
    req = urllib.request.Request(url, data=data, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=_TIMEOUT) as resp:
            return resp.status, resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:  # non-2xx
        return e.code, e.read().decode("utf-8", "replace")
    except Exception as e:  # network/DNS/timeout
        return 0, str(e)


def _send_sync(to: str, subject: str, html: str, text: str) -> bool:
    provider = settings.EMAIL_PROVIDER.lower().strip()
    key = settings.EMAIL_API_KEY.strip()
    sender = settings.EMAIL_FROM

    if provider == "resend":
        status, body = _post(
            "https://api.resend.com/emails",
            data=json.dumps(
                {"from": sender, "to": [to], "subject": subject, "html": html, "text": text}
            ).encode(),
            headers={
                "Authorization": f"Bearer {key}",
                "Content-Type": "application/json",
            },
        )
    elif provider == "sendgrid":
        # SendGrid wants a bare "email" or "Name <email>"; it accepts both forms.
        status, body = _post(
            "https://api.sendgrid.com/v3/mail/send",
            data=json.dumps(
                {
                    "personalizations": [{"to": [{"email": to}]}],
                    "from": {"email": sender},
                    "subject": subject,
                    "content": [
                        {"type": "text/plain", "value": text},
                        {"type": "text/html", "value": html},
                    ],
                }
            ).encode(),
            headers={
                "Authorization": f"Bearer {key}",
                "Content-Type": "application/json",
            },
        )
    elif provider == "mailgun":
        domain = settings.MAILGUN_DOMAIN.strip()
        auth = base64.b64encode(f"api:{key}".encode()).decode()
        status, body = _post(
            f"https://api.mailgun.net/v3/{domain}/messages",
            data=urllib.parse.urlencode(
                {"from": sender, "to": to, "subject": subject, "text": text, "html": html}
            ).encode(),
            headers={
                "Authorization": f"Basic {auth}",
                "Content-Type": "application/x-www-form-urlencoded",
            },
        )
    else:
        logger.error("Unknown EMAIL_PROVIDER '%s'", provider)
        return False

    if 200 <= status < 300:
        return True
    logger.error("Email send failed (provider=%s status=%s): %s", provider, status, body[:400])
    return False


async def send_email(to: str, subject: str, html: str, text: Optional[str] = None) -> bool:
    """Send an email. Returns True if the provider accepted it."""
    if not settings.email_configured:
        logger.warning("EMAIL_API_KEY not set — not sending email to %s (subject=%r)", to, subject)
        return False
    return await asyncio.to_thread(_send_sync, to, subject, html, text or "")


def _otp_html(code: str, purpose: str) -> tuple[str, str]:
    action = "verify your email" if purpose == "signup" else "reset your password"
    html = f"""\
<div style="font-family:system-ui,Arial,sans-serif;max-width:480px;margin:auto">
  <h2 style="color:#154C79">ConFriKa</h2>
  <p>Use this code to {action}:</p>
  <p style="font-size:32px;font-weight:800;letter-spacing:8px;color:#154C79">{code}</p>
  <p style="color:#64748b;font-size:13px">This code expires in {settings.OTP_TTL_MINUTES} minutes.
     If you didn't request it, you can ignore this email.</p>
  <p style="color:#94a3b8;font-size:12px">Many languages. One connection. One Africa.</p>
</div>"""
    text = f"Your ConFriKa code to {action} is {code}. It expires in {settings.OTP_TTL_MINUTES} minutes."
    return html, text


async def send_otp_email(to: str, code: str, purpose: str) -> bool:
    subject = (
        "Your ConFriKa verification code"
        if purpose == "signup"
        else "Reset your ConFriKa password"
    )
    html, text = _otp_html(code, purpose)
    return await send_email(to, subject, html, text)
