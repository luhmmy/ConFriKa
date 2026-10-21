-- ConFriKa Full Database Schema (PostgreSQL 16)
-- Pan-African Communication Platform

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. Users Table
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    username VARCHAR(40) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(128) NOT NULL,
    full_name VARCHAR(120) NOT NULL,
    country_code CHAR(2) NOT NULL,
    origin_region VARCHAR(120) NOT NULL,
    primary_dialect VARCHAR(100) NOT NULL,
    f0_baseline_hz DOUBLE PRECISION DEFAULT 138.0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_users_country ON users(country_code);

-- 2. User Contacts Table
CREATE TABLE IF NOT EXISTS user_contacts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    contact_username VARCHAR(40) NOT NULL,
    alias_name VARCHAR(120),
    preferred_language VARCHAR(100),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, contact_username)
);

CREATE INDEX IF NOT EXISTS idx_contacts_user_id ON user_contacts(user_id);
CREATE INDEX IF NOT EXISTS idx_contacts_username ON user_contacts(contact_username);

-- 3. Direct Messages Table
CREATE TABLE IF NOT EXISTS direct_messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    recipient_username VARCHAR(40) NOT NULL,
    message_type VARCHAR(20) DEFAULT 'text',
    original_text TEXT NOT NULL,
    translated_text TEXT,
    source_dialect VARCHAR(100) NOT NULL,
    target_dialect VARCHAR(100),
    audio_url TEXT,
    audio_duration_seconds REAL,
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_dm_recipient ON direct_messages(recipient_username);
CREATE INDEX IF NOT EXISTS idx_dm_sender ON direct_messages(sender_id);
CREATE INDEX IF NOT EXISTS idx_dm_created_at ON direct_messages(created_at);

-- 4. Global Spaces Messages Table
CREATE TABLE IF NOT EXISTS global_spaces_messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    channel_category VARCHAR(40) DEFAULT 'all',
    country_filter VARCHAR(8) DEFAULT 'ALL',
    message_type VARCHAR(20) DEFAULT 'text',
    original_text TEXT NOT NULL,
    translated_text TEXT,
    source_dialect VARCHAR(100) NOT NULL,
    audio_url TEXT,
    duration_label VARCHAR(10),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_spaces_channel ON global_spaces_messages(channel_category);
CREATE INDEX IF NOT EXISTS idx_spaces_created_at ON global_spaces_messages(created_at);

-- 5. Call Sessions Table
CREATE TABLE IF NOT EXISTS call_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    caller_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    callee_username VARCHAR(40) NOT NULL,
    call_transport VARCHAR(20) DEFAULT 'inapp',
    status VARCHAR(20) DEFAULT 'ringing',
    started_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    connected_at TIMESTAMP WITH TIME ZONE,
    ended_at TIMESTAMP WITH TIME ZONE,
    duration_seconds INTEGER DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_calls_caller ON call_sessions(caller_id);
CREATE INDEX IF NOT EXISTS idx_calls_callee ON call_sessions(callee_username);

-- 6. Tonal Learning Records
CREATE TABLE IF NOT EXISTS tonal_learning_records (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    target_word VARCHAR(80) NOT NULL,
    diacritized_spelling VARCHAR(80) NOT NULL,
    meaning VARCHAR(120) NOT NULL,
    tone_pattern VARCHAR(60) NOT NULL,
    measured_f0_hz DOUBLE PRECISION NOT NULL,
    semitone_contour JSONB NOT NULL,
    match_score_pct REAL NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_tone_user ON tonal_learning_records(user_id);
