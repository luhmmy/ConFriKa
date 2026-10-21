# ConFriKa System Architecture & Production Specification
**"Many languages. One connection. One Africa."**

---

## 1. Executive Architecture Summary

ConFriKa is an ultra-low-latency, resilient pan-African communication platform delivering:
1. **African Dialect Speech & Tonal Translation Engine**: Real-time diacritic-aware Neural Machine Translation (NMT) and F0 semitone pitch contour estimation for tonal languages (e.g. Yorùbá, Igbo, Hausa, Swahili, Amharic, Zulu, Xhosa, Twi, Shona, and 54 sovereign African states).
2. **WebRTC Live In-App Calling & Signaling Gateway**: Low-bandwidth adaptive Opus/G.711 voice calling with real-time bidirectional translation overlay, ICE/STUN/TURN mesh or SFU routing, and telecom fallback hooks (No-App Calling via SIP/PSTN carrier interconnects).
3. **Real-Time Direct Messaging & Global Spaces**: WebSocket-based event streaming, end-to-end delivery guarantees, audio transcoding for voice notes, and on-demand translation toggles (`Translate: ON` vs `Original Dialect`).
4. **Self-Learning Tonal Coach**: Adaptive F0 pitch calibration with semitone curve regression against learner speech to prevent semantic ambiguity in tonal minimal pairs (e.g., *ọkọ* husband, *ọkọ̀* vehicle, *ọkọ́* spear).

---

## 2. High-Level Component Topology

```
                  +----------------------------------------------+
                  |  ConFriKa Flutter Client (Android & iOS)     |
                  |  - Audio Capture / Playback (Opus / 16kHz)   |
                  |  - WebRTC PeerConnection (Calls)             |
                  |  - Persistent WebSocket (Chat & Presence)    |
                  +-----------------------+----------------------+
                                          |
                      TLS / HTTPS / WSS   |
                                          v
                  +----------------------------------------------+
                  |  Edge Reverse Proxy (Nginx / Cloudflare)     |
                  |  - SSL Offloading & Rate Limiting (Token Bkt)|
                  |  - WSS Upgrade Proxy & Static Asset Caching  |
                  +-----------------------+----------------------+
                                          |
                                          v
+---------------------------------------------------------------------------------+
|                       ConFriKa Gateway & Core Services                         |
|                                                                                 |
|  +------------------------+  +--------------------------+  +-----------------+  |
|  | Auth & User Directory  |  | Direct Messaging & Spaces|  | WebRTC Signal   |  |
|  | - Gmail + 54 Countries |  | - Real-time WS Pump      |  | - ICE / SDP Exch|  |
|  | - @username Registry   |  | - Dual-mode (Orig / Trn) |  | - Session Mgmt  |  |
|  +-----------+------------+  +------------+-------------+  +--------+--------+  |
|              |                            |                         |           |
|              +----------------------------+-------------------------+           |
|                                           |                                     |
|                                           v                                     |
|  +---------------------------------------------------------------------------+  |
|  | African Speech & Tonal Intelligence Service                                |  |
|  | - ASR Audio Ingestion & Diacritic Restoration                             |  |
|  | - F0 Autocorrelation & Semitone Drift Estimator (100-300 Hz)              |  |
|  | - Multi-Dialect Neural Translation Engine (54 African Nations)            |  |
|  | - Voice Synthesis & Natural Formant Pitch Resynthesis                     |  |
|  +---------------------------------------------------------------------------+  |
|                                           |                                     |
+-------------------------------------------+-------------------------------------+
                                            |
                                            v
+---------------------------------------------------------------------------------+
|                         Data Layer & State Engine                               |
|                                                                                 |
|  +--------------------------------------+   +--------------------------------+  |
|  | PostgreSQL 16 (Primary Persistence)  |   | Redis 7 (Pub/Sub & Presence)   |  |
|  | - Users, Contacts, Call Sessions     |   | - "● 428 Online" Presence      |  |
|  | - Direct Messages, Spaces Chat       |   | - WebSocket Channel Broadcasts |  |
|  | - Tonal Learning Vector Profiles     |   | - Ephemeral Call Ringing State |  |
|  +--------------------------------------+   +--------------------------------+  |
+---------------------------------------------------------------------------------+
```

---

## 3. Database Schema (PostgreSQL 16)

```sql
-- 1. Users Table
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username VARCHAR(40) UNIQUE NOT NULL,      -- e.g. @chinedu_okafor
    email VARCHAR(255) UNIQUE NOT NULL,         -- e.g. user@gmail.com
    full_name VARCHAR(120) NOT NULL,
    country_code CHAR(2) NOT NULL,              -- ISO 3166-1 alpha-2 (e.g. NG, GH, KE)
    origin_region VARCHAR(120) NOT NULL,        -- e.g. Anambra, Lagos, Nairobi
    primary_dialect VARCHAR(100) NOT NULL,      -- e.g. Igbo (Onitsha), Yoruba (Oyo)
    f0_baseline_hz DOUBLE PRECISION DEFAULT 138.0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 2. User Contacts Table
CREATE TABLE user_contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    contact_username VARCHAR(40) NOT NULL,
    alias_name VARCHAR(120),
    preferred_language VARCHAR(100),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, contact_username)
);

-- 3. Direct Messages Table
CREATE TABLE direct_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sender_id UUID REFERENCES users(id) ON DELETE CASCADE,
    recipient_username VARCHAR(40) NOT NULL,
    message_type VARCHAR(20) DEFAULT 'text',    -- 'text' or 'voicenote'
    original_text TEXT NOT NULL,
    translated_text TEXT,
    source_dialect VARCHAR(100) NOT NULL,
    target_dialect VARCHAR(100),
    audio_url TEXT,
    audio_duration_seconds REAL,
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 4. Global Spaces Messages Table
CREATE TABLE global_spaces_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sender_id UUID REFERENCES users(id) ON DELETE CASCADE,
    channel_category VARCHAR(40) DEFAULT 'all', -- 'all', 'trade', 'culture'
    country_filter CHAR(2) DEFAULT 'ALL',
    message_type VARCHAR(20) DEFAULT 'text',
    original_text TEXT NOT NULL,
    translated_text TEXT,
    source_dialect VARCHAR(100) NOT NULL,
    audio_url TEXT,
    duration_label VARCHAR(10),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 5. Call Sessions Table
CREATE TABLE call_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    caller_id UUID REFERENCES users(id) ON DELETE CASCADE,
    callee_username VARCHAR(40) NOT NULL,
    call_transport VARCHAR(20) DEFAULT 'inapp', -- 'inapp' or 'telecom'
    status VARCHAR(20) DEFAULT 'ringing',       -- 'ringing', 'connected', 'ended', 'missed'
    started_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    connected_at TIMESTAMP WITH TIME ZONE,
    ended_at TIMESTAMP WITH TIME ZONE,
    duration_seconds INTEGER DEFAULT 0
);

-- 6. Tonal Practice & Learned Words Table
CREATE TABLE tonal_learning_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    target_word VARCHAR(80) NOT NULL,           -- e.g. ọkọ, ọkọ̀, ọkọ́
    diacritized_spelling VARCHAR(80) NOT NULL,
    meaning VARCHAR(120) NOT NULL,
    tone_pattern VARCHAR(60) NOT NULL,          -- e.g. Mid-Low (-3.4 ST)
    measured_f0_hz DOUBLE PRECISION NOT NULL,
    semitone_contour JSONB NOT NULL,
    match_score_pct REAL NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
```

---

## 4. RESTful & WebSocket API Specification

### 4.1 Authentication & Profile
- `POST /api/v1/auth/signup`: Accepts Gmail (`@gmail.com`), Full Name, Username (`@handle`), Country (All 54), Origin, and Local Dialect. Returns signed JWT.
- `POST /api/v1/auth/login`: Handles passwordless/Gmail authentication and JWT token issuance.
- `GET /api/v1/users/me`: Retrieves current authenticated user profile, F0 pitch baseline, and learned words count.
- `PUT /api/v1/users/me/tonal-baseline`: Calibrates user's personal baseline vocal pitch (F0 mean Hz).

### 4.2 Contact Management
- `GET /api/v1/contacts`: Returns all saved contacts with `@username`, names, dialect badges, and online status.
- `POST /api/v1/contacts`: Adds a contact by `@username` or lookup from the global directory.
- `GET /api/v1/contacts/search?q={query}`: Searches users by `@username`, full name, country, or dialect.

### 4.3 Direct Messages & Chat
- `GET /api/v1/chat/dm/{username}`: Retrieves conversation thread with a specific contact.
- `POST /api/v1/chat/dm/{username}`: Sends a 1-on-1 text or voice note message with optional auto-translation.
- `GET /api/v1/chat/spaces`: Retrieves public pan-African Global Chat messages (filterable by channel & country).
- `POST /api/v1/chat/spaces`: Posts a message or voice note to Global Chat.

### 4.4 Speech, Translation & Tone Coach
- `POST /api/v1/speech/translate`: Translates text or audio transcript across African dialect pairs.
- `POST /api/v1/speech/pitch-analysis`: Analyzes an uploaded audio sample, returning F0 fundamental frequency and semitone pitch contour.
- `GET /api/v1/tone-coach/minimal-pairs`: Returns curated tonal minimal-pair exercises (e.g., Yoruba *ọkọ*, Igbo *akwa*).
- `POST /api/v1/tone-coach/calibrate`: Evaluates a learner's spoken audio against target semitone bands and computes match accuracy.

### 4.5 WebSockets
- `WSS /api/v1/ws/chat?token={jwt}`: Real-time messaging, typing indicators, read receipts, and live presence updates (`● 428 Online`).
- `WSS /api/v1/ws/calls?token={jwt}`: WebRTC signaling channel for SDP offers, answers, and ICE candidate exchanges.
