import uuid
from datetime import datetime, timezone
from sqlalchemy import (
    Column,
    String,
    Text,
    Boolean,
    Float,
    Integer,
    DateTime,
    ForeignKey,
    JSON,
)
from sqlalchemy.orm import declarative_base, relationship

Base = declarative_base()


class User(Base):
    __tablename__ = "users"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    username = Column(String(40), unique=True, nullable=False, index=True)
    email = Column(String(255), unique=True, nullable=False, index=True)
    password_hash = Column(String(128), nullable=False)
    full_name = Column(String(120), nullable=False)
    country_code = Column(String(2), nullable=False, index=True)
    origin_region = Column(String(120), nullable=False)
    primary_dialect = Column(String(100), nullable=False)
    f0_baseline_hz = Column(Float, default=138.0)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))
    updated_at = Column(
        DateTime,
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )

    contacts = relationship("UserContact", back_populates="user", cascade="all, delete-orphan")
    sent_direct_messages = relationship(
        "DirectMessage", foreign_keys="DirectMessage.sender_id", back_populates="sender"
    )
    tonal_records = relationship(
        "TonalLearningRecord", back_populates="user", cascade="all, delete-orphan"
    )


class UserContact(Base):
    __tablename__ = "user_contacts"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(String(36), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    contact_username = Column(String(40), nullable=False, index=True)
    alias_name = Column(String(120), nullable=True)
    preferred_language = Column(String(100), nullable=True)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))

    user = relationship("User", back_populates="contacts")


class DirectMessage(Base):
    __tablename__ = "direct_messages"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    sender_id = Column(String(36), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    recipient_username = Column(String(40), nullable=False, index=True)
    message_type = Column(String(20), default="text")  # 'text' or 'voicenote'
    original_text = Column(Text, nullable=False)
    translated_text = Column(Text, nullable=True)
    source_dialect = Column(String(100), nullable=False)
    target_dialect = Column(String(100), nullable=True)
    audio_url = Column(Text, nullable=True)
    audio_duration_seconds = Column(Float, nullable=True)
    is_read = Column(Boolean, default=False)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), index=True)

    sender = relationship("User", foreign_keys=[sender_id], back_populates="sent_direct_messages")


class GlobalSpacesMessage(Base):
    __tablename__ = "global_spaces_messages"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    sender_id = Column(String(36), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    sender_name = Column(String(120), nullable=False)
    sender_username = Column(String(40), nullable=False)
    sender_location = Column(String(120), nullable=False)
    channel_category = Column(String(40), default="all")  # 'all', 'trade', 'culture'
    country_filter = Column(String(8), default="ALL")
    message_type = Column(String(20), default="text")
    original_text = Column(Text, nullable=False)
    translated_text = Column(Text, nullable=True)
    source_dialect = Column(String(100), nullable=False)
    audio_url = Column(Text, nullable=True)
    duration_label = Column(String(10), nullable=True)
    sample_phrase = Column(String(120), nullable=True)
    sample_meaning = Column(String(120), nullable=True)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), index=True)


class CallSession(Base):
    __tablename__ = "call_sessions"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    caller_id = Column(String(36), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    caller_username = Column(String(40), nullable=False)
    callee_username = Column(String(40), nullable=False, index=True)
    call_transport = Column(String(20), default="inapp")  # 'inapp' or 'telecom'
    status = Column(String(20), default="ringing")  # 'ringing', 'connected', 'ended', 'missed'
    started_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))
    connected_at = Column(DateTime, nullable=True)
    ended_at = Column(DateTime, nullable=True)
    duration_seconds = Column(Integer, default=0)


class TonalLearningRecord(Base):
    __tablename__ = "tonal_learning_records"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(String(36), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    target_word = Column(String(80), nullable=False)
    diacritized_spelling = Column(String(80), nullable=False)
    meaning = Column(String(120), nullable=False)
    tone_pattern = Column(String(60), nullable=False)
    measured_f0_hz = Column(Float, nullable=False)
    semitone_contour = Column(JSON, nullable=False)
    match_score_pct = Column(Float, nullable=False)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))

    user = relationship("User", back_populates="tonal_records")
