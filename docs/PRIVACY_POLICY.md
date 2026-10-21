# ConFriKa — Official Privacy Policy

**Effective Date:** October 2026  
**Last Updated:** October 2026  
**Application:** ConFriKa (iOS, Android, Web)  
**Entity:** ConFriKa Technologies Inc. ("ConFriKa", "we", "us", or "our")

---

## 1. Introduction & Pan-African Commitment

ConFriKa ("Many languages. One connection. One Africa.") is committed to safeguarding the privacy and personal data of every individual across all 54 African nations and the diaspora.

This Privacy Policy explains how ConFriKa collects, processes, encrypts, and retains personal information when you use the ConFriKa mobile application, web prototype, and backend services, compliant with:
- **Nigeria Data Protection Regulation (NDPR / NDPA 2023)**
- **South Africa Protection of Personal Information Act (POPIA 2013)**
- **Kenya Data Protection Act (KDPA 2019)**
- **Ghana Data Protection Act (Act 843)**
- **General Data Protection Regulation (EU GDPR 2016/679)**
- **Apple App Store Review Guidelines (Section 5.1 Privacy)**
- **Google Play Developer Policy (User Data & Permissions)**

---

## 2. Information We Collect

### A. Account Information
- **Google Authentication:** When registering with `@gmail.com`, we collect your verified email, display name, and unique Google authentication UID.
- **ConFriKa Unique Username:** Your public handle (e.g., `@amara_lagos`).
- **Linguistic Profile:** Selected native country (from all 54 African nations), indigenous spoken dialects, and learning goals.

### B. Communications & Voice Data
- **Direct Messages:** End-to-end TLS 1.3 encrypted text messages between users.
- **Voice Notes & Live In-App Audio:** Audio recordings submitted for translation or tone coaching are processed in real-time. Acoustic feature vectors (Fundamental frequency $F_0$) are extracted in-memory to calculate pitch semitones and are not retained for advertising purposes.
- **Call Session Metadata:** Call timestamps, duration, participant IDs, and WebRTC ICE connection status. We do NOT record or store the contents of your live voice calls.

### C. Device & Telemetry Data
- **Device Information:** Operating system version (Android / iOS), device manufacturer, network type (2G/3G/4G/5G/Wi-Fi).
- **Push Notification Tokens:** Firebase Cloud Messaging (FCM) and Apple Push Notification Service (APNs) device tokens for incoming call alerts and direct message delivery.

---

## 3. How We Use Your Data

1. **Real-Time Dialect Translation:** Converting text and voice across African languages with tonal diacritics (*Àmì Ohùn*).
2. **Interactive Tone Coaching:** Computing pitch deviation $\Delta ST = 12 \times \log_2(F_0 / F_{\text{target}})$ to provide immediate visual feedback.
3. **Peer-to-Peer Calling:** Establishing WebRTC media sessions traversing Carrier-Grade NATs (CGNAT) via STUN and TURN relays.
4. **Security & Spam Prevention:** Preventing automated bot attacks, ensuring unique username reservation, and rate limiting abuse.

---

## 4. Permissions Requested & Justification

| Platform | Permission | User-Facing Purpose |
| :--- | :--- | :--- |
| **Android / iOS** | `RECORD_AUDIO` / `NSMicrophoneUsageDescription` | Required to record voice notes and capture live audio for real-time translation and tone coaching. |
| **Android** | `MANAGE_OWN_CALLS` / `USE_FULL_SCREEN_INTENT` | Displays full-screen incoming phone call interface like a native carrier phone call. |
| **iOS** | `UIBackgroundModes (voip, audio)` | Keeps voice calls connected when the device is locked or the app is minimized. |
| **Android / iOS** | `POST_NOTIFICATIONS` | Alerts you when receiving direct messages or incoming calls. |
| **Android / iOS** | `BLUETOOTH` | Directs call audio to Bluetooth earpieces, headsets, and hands-free car kits. |

---

## 5. Data Retention & Deletion

- **Direct Messages:** Retained until deleted by the user or account deactivation.
- **Ephemeral Audio & Transcripts:** Live call audio is streamed in real-time and never written to permanent disk storage.
- **Account Deletion:** Users can permanently delete their account at any time through `Profile -> Delete Account`. Upon confirmation, all associated credentials, contacts, and message records are purged within 30 days.

---

## 6. International Data Transfers

Your data is hosted in high-security, ISO 27001-certified data centers with localized edge points of presence across Africa (Lagos, Johannesburg, Nairobi, Cairo) to reduce latency and comply with data sovereignty regulations.

---

## 7. Contact Us

If you have questions, data access requests, or complaints regarding this Privacy Policy, please contact our Data Protection Officer (DPO):

- **Email:** `privacy@confrika.com`
- **Legal Entity:** ConFriKa Technologies Inc.
- **Address:** Pan-Africa Technology Park, Victoria Island, Lagos, Nigeria.
