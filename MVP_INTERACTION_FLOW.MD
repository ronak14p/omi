# MVP INTERACTION FLOW (VOICE ACTIVATION + INITIAL PHOTO + CONFIRMED AGENT HANDOFF)

Date: 2026-03-04
Repo: `/Users/ronak/Developer/omi`

## 1) Locked MVP Behavior

- Session starts when user enables capture once.
- AI interaction is activated by voice phrase (example: `"AI, what am I looking at?"`).
- That first activation always triggers both:
  - voice/transcript context capture
  - single photo capture for initial visual grounding
- AI can continue a back-and-forth conversation first (clarify intent, gather requirements).
- If AI determines a backend action is needed, AI asks: `"Should I complete X task with the backend agent?"`
- Backend agent execution only starts after explicit user confirmation (`yes`/`no`).
- AI waits for backend agent result, then reports completion/follow-up to user.


## 2) Current Code Reality (What Exists vs Needed)

### 2.1 What already exists and is reusable

- Continuous audio ingestion over websocket `/v4/listen`.
- Photo upload pipeline (`image_chunk`) with backend photo description events.
- Voice-message transcription + assistant response flow (`/v2/voice-messages`).
- Agent VM/harness path (`/v1/agent/ws`) and backend tool execution path.

### 2.2 Gaps vs your required flow

- No current wake phrase/activation phrase pipeline in app/backend.
- No guaranteed `activation -> immediate single photo -> answer` orchestration.
- Voice-message flow and agent flow are split and inconsistent.
- No mandatory API-level confirm gate before side-effect agent execution.
- `OmiGlassConnection` button listener is stubbed, but this is no longer a primary blocker if voice phrase activation is used.


## 3) Exact Target Interaction Flow (Single Canonical Flow)

### 3.1 State machine

`CAPTURE_ON -> WAITING_FOR_ACTIVATION -> ACTIVATED -> CAPTURING_INITIAL_PHOTO -> AI_DIALOGUE -> [CONFIRM_AGENT?] -> AGENT_EXECUTING -> AGENT_DONE -> AI_REPORT`

### 3.2 Sequence (exact)

1. User turns capture on once.
2. Audio streams continuously to backend transcription.
3. User says activation phrase, for example: `"AI, what am I looking at?"`
4. Backend detects activation phrase and creates `interaction_id`.
5. Backend sends app event: `request_capture_photo` (single shot).
6. App immediately issues one-shot photo command (`-1`) to device.
7. App continues streaming transcript while photo uploads in chunks.
8. Backend receives photo, generates description, and builds initial multimodal context:
   - activation utterance transcript
   - recent transcript window
   - initial photo description
9. AI returns first response grounded in that initial photo and question.
10. AI continues dialogue to clarify whether this is just assistance or requires backend action.
11. If action is needed, AI asks explicit confirmation:
    - `"Should I complete X task with the backend agent?"`
12. User responds yes/no.
13. If `no`: continue AI dialogue only.
14. If `yes`: backend runs agent harness with allowlisted tools.
15. Backend streams execution updates and final outcome.
16. AI presents final confirmation/follow-up.


## 4) Required Implementation Changes (for this exact flow)

## 4.1 P0: Add activation phrase trigger and interaction sessioning

Backend:
- Add activation detection in live transcript path (recommended in `backend/routers/transcribe.py` or a helper module it calls).
- On detection, create `interaction_id` and emit websocket event `request_capture_photo`.
- Maintain per-interaction state (`activated_at`, `initial_photo_id`, `confirmation_state`, `agent_state`).

App:
- `app/lib/providers/capture_provider.dart`
  - Handle new message event `request_capture_photo`.
  - On event, call new generic `cameraTakePhoto()` immediately.
  - Keep transcript stream active during photo capture.

## 4.2 P0: Expose generic single-shot photo command in app device layer

- `app/lib/services/devices/device_connection.dart`
  - Add `cameraTakePhoto()` wrapper + abstract `performCameraTakePhoto()`.
- `app/lib/services/devices/omi_connection.dart`
  - Use existing single-shot implementation (`-1`) under interface contract.
- `app/lib/services/devices/omiglass_connection.dart`
  - Implement `performCameraTakePhoto()` by writing `[-1]` to photo control characteristic.

## 4.3 P0: Unify assistant decision path (assist vs agent)

Backend:
- Add unified interaction dispatcher endpoint (recommended `POST /v1/mvp/interaction/dispatch`) for non-live follow-up turns.
- Ensure both voice-activated turns and typed follow-ups use same intent router.
- Route outcomes into only two execution modes:
  - `assist_only`
  - `agent_required`

App:
- `app/lib/providers/message_provider.dart`
  - Add unified dispatcher client method for follow-up turns.
  - Stop relying on split logic where voice and agent paths diverge.

## 4.4 P0: Mandatory confirmation gate before backend agent execution

Backend:
- Introduce confirm gate state machine (recommended `backend/utils/agentic/mvp_orchestrator.py`):
  - `propose_action -> await_confirmation -> execute -> verify -> report`
- Enforce confirmation in `backend/routers/agent_tools.py` before side-effect tool execution.
- Require confirmation token/interaction state check for every mutating tool call.

AI behavior contract:
- AI must explicitly ask before agent execution.
- `yes` starts agent run.
- `no` cancels action and returns to dialogue.

## 4.5 P0: Harden OpenClaw-style harness for MVP

- `desktop/agent-cloud/agent.mjs`
  - Restrict tools to MVP allowlist only.
  - Disable over-permissive default behavior in MVP mode.
  - Emit structured progress events for app/UI (`planning`, `executing`, `done`, `failed`).


## 5) MVP Event Contract (Minimal)

## 5.1 Live websocket events (backend -> app)

```json
{ "type": "request_capture_photo", "interaction_id": "int_001", "reason": "activation_phrase" }
{ "type": "initial_photo_ready", "interaction_id": "int_001", "photo_id": "ph_001" }
{ "type": "assistant_response", "interaction_id": "int_001", "text": "You are looking at..." }
{ "type": "await_agent_confirmation", "interaction_id": "int_001", "summary": "Send this image to your email" }
{ "type": "agent_update", "interaction_id": "int_001", "status": "executing", "step": "Sending email" }
{ "type": "agent_done", "interaction_id": "int_001", "result": "Email sent" }
```

## 5.2 Confirmation request (app -> backend)

```json
{
  "interaction_id": "int_001",
  "confirmation": "yes"
}
```

Values: `yes` or `no`.


## 6) Example of your exact intended UX

1. User: `"AI, what am I looking at?"`
2. System: captures initial photo automatically.
3. AI: answers based on photo + voice.
4. User and AI discuss next step.
5. AI: `"Should I complete X task with the backend agent?"`
6. User: `"Yes"`
7. Backend agent runs and returns updates.
8. AI: confirms completion/follow-up.


## 7) Day-1 Hardware Test Checklist (for this flow)

1. Activation phrase triggers interaction session without manual button path.
2. Activation phrase triggers immediate single-shot photo capture.
3. First AI answer includes visual grounding from that initial photo.
4. AI can ask clarifying questions before deciding on agent use.
5. Agent task does not run without explicit yes confirmation.
6. On yes, agent runs and result is returned to AI and user.
7. On no, no side-effect is executed and conversation continues.


## 8) Non-Goals (MVP)

- No app-store/platform route.
- No autonomous side-effect execution without confirmation.
- No unbounded dynamic third-party tool execution.
