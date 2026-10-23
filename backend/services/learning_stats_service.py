"""Real learning-progress statistics.

Every figure here is derived from rows the user actually generated — tonal
practice attempts, direct messages, and Global Spaces posts. There are no
seeded or fabricated numbers: a brand-new account reads back all zeros.
"""
from __future__ import annotations

from datetime import date, datetime, timedelta, timezone
from typing import Any, Dict, List

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..database.models import (
    DirectMessage,
    GlobalSpacesMessage,
    TonalLearningRecord,
    User,
)

# A word counts as "learned" once the learner has reproduced its tone contour
# at or above this match score at least once.
MASTERY_THRESHOLD_PCT = 80.0

# XP is a transparent function of real activity (not a stored counter):
_XP_PER_PRACTICE = 10
_XP_PER_MASTERED_WORD = 25
_XP_PER_MESSAGE = 2


def _utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def _streak_days(activity_dates: List[date]) -> int:
    """Consecutive-day streak ending today or yesterday.

    `activity_dates` is any collection of dates on which the user did something.
    The streak is the run of consecutive calendar days counting back from the
    most recent activity, but only if that activity was today or yesterday
    (otherwise the streak has lapsed and is 0).
    """
    if not activity_dates:
        return 0
    days = sorted(set(activity_dates), reverse=True)
    today = _utcnow().date()
    most_recent = days[0]
    if (today - most_recent).days > 1:
        return 0  # lapsed

    streak = 1
    cursor = most_recent
    for d in days[1:]:
        if (cursor - d).days == 1:
            streak += 1
            cursor = d
        elif d == cursor:
            continue
        else:
            break
    return streak


class LearningStatsService:
    @classmethod
    async def record_practice(
        cls,
        db: AsyncSession,
        user: User,
        *,
        base_word: str,
        diacritized_spelling: str,
        meaning: str,
        tone_pattern: str,
        measured_f0_hz: float,
        semitone_contour: List[float],
        match_score_pct: float,
    ) -> None:
        """Persist a single tonal-practice attempt for this user."""
        db.add(
            TonalLearningRecord(
                user_id=user.id,
                target_word=base_word,
                diacritized_spelling=diacritized_spelling,
                meaning=meaning,
                tone_pattern=tone_pattern,
                measured_f0_hz=measured_f0_hz,
                semitone_contour=semitone_contour,
                match_score_pct=match_score_pct,
            )
        )
        await db.commit()

    @classmethod
    async def get_user_stats(cls, db: AsyncSession, user: User) -> Dict[str, Any]:
        # ---- Tonal practice records ----------------------------------------
        records = (
            await db.scalars(
                select(TonalLearningRecord).where(
                    TonalLearningRecord.user_id == user.id
                )
            )
        ).all()

        practice_sessions = len(records)
        best_by_word: Dict[str, float] = {}
        for r in records:
            key = r.diacritized_spelling
            best_by_word[key] = max(best_by_word.get(key, 0.0), r.match_score_pct)

        words_practiced = len(best_by_word)
        words_mastered = sum(
            1 for score in best_by_word.values() if score >= MASTERY_THRESHOLD_PCT
        )

        # ---- Messages the user sent ----------------------------------------
        dm_count = (
            await db.scalar(
                select(func.count(DirectMessage.id)).where(
                    DirectMessage.sender_id == user.id
                )
            )
        ) or 0
        spaces_count = (
            await db.scalar(
                select(func.count(GlobalSpacesMessage.id)).where(
                    GlobalSpacesMessage.sender_id == user.id
                )
            )
        ) or 0
        messages_sent = int(dm_count) + int(spaces_count)

        # ---- Activity dates (for the streak) -------------------------------
        activity_dates: List[date] = [r.created_at.date() for r in records]
        dm_dates = (
            await db.scalars(
                select(DirectMessage.created_at).where(
                    DirectMessage.sender_id == user.id
                )
            )
        ).all()
        spaces_dates = (
            await db.scalars(
                select(GlobalSpacesMessage.created_at).where(
                    GlobalSpacesMessage.sender_id == user.id
                )
            )
        ).all()
        activity_dates.extend(d.date() for d in dm_dates)
        activity_dates.extend(d.date() for d in spaces_dates)

        streak_days = _streak_days(activity_dates)

        last_practiced_at = (
            max(r.created_at for r in records).isoformat() if records else None
        )

        xp = (
            practice_sessions * _XP_PER_PRACTICE
            + words_mastered * _XP_PER_MASTERED_WORD
            + messages_sent * _XP_PER_MESSAGE
        )

        return {
            "words_learned": words_mastered,
            "words_practiced": words_practiced,
            "practice_sessions": practice_sessions,
            "messages_sent": messages_sent,
            "streak_days": streak_days,
            "xp": xp,
            "last_practiced_at": last_practiced_at,
            "f0_baseline_hz": user.f0_baseline_hz,
            "is_calibrated": practice_sessions > 0,
        }
