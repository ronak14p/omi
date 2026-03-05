# Mar4 Session README

Date: 2026-03-04  
Workspace: `/Users/ronak/Developer/omi`  
Owner: Ronak / `ronak14p`

## 1) Session Objective

Build a practical MVP path for Omi glasses where:
- AI can be activated by voice in an always-available capture session.
- First interaction includes both hearing (voice/transcript) and sight (photo context).
- AI can decide when backend agent execution is needed.
- Side-effecting actions require explicit user confirmation (`yes` / `no`).
- Confirmation should work by voice (and remain compatible with existing button-triggered voice capture flow).


## 2) Documents Produced in This Session

This `Mar4/` folder contains the planning and forensic artifacts created/updated in this work session:

- `BACKEND_APPS.MD`
  - Backend service map and route/API surface analysis.
  - Findings map for split flow, over-permissive runtime, and missing confirmation gate.

- `INITIAL_TRANSFORMATION.MD`
  - MVP strategy, forensic findings, scope lock, and phased implementation recommendations.

- `MVP_INTERACTION_FLOW.MD`
  - Canonical interaction contract:
    - voice activation
    - initial photo capture
    - AI dialogue and intent clarification
    - explicit confirmation before backend-agent execution


## 3) Implementation Work Completed

## 3.1 Activation phrase -> automatic initial photo request

Implemented a first vertical slice for live capture activation:

- Added backend activation phrase detection during live transcript processing.
- Added new live event: `request_capture_photo`.
- On event, app requests a single-shot image from connected device.

Backend files:
- `backend/models/message_event.py`
  - Added `RequestCapturePhotoEvent`.
- `backend/routers/transcribe.py`
  - Added activation phrase matching helpers and one-shot per-conversation trigger logic.

App files:
- `app/lib/backend/schema/message_event.dart`
  - Added `RequestCapturePhotoEvent` parsing.
- `app/lib/providers/capture_provider.dart`
  - Handles `request_capture_photo` with cooldown and device capability checks.
- `app/lib/services/devices/device_connection.dart`
  - Added generic `cameraTakePhoto()` API.
- `app/lib/services/devices/omi_connection.dart`
  - Marks single-shot implementation as override.
- `app/lib/services/devices/omiglass_connection.dart`
  - Added single-shot photo command (`[-1]`).


## 3.2 Confirmation gate for side-effecting backend actions

Implemented backend action-state and confirmation enforcement:

- Added Redis action state storage (per `uid + interaction_id`).
- Added action lifecycle endpoints:
  - `POST /v1/agent/actions/propose`
  - `POST /v1/agent/actions/confirm`
  - `GET /v1/agent/actions/{interaction_id}`
- Extended tool execution payload with `interaction_id`.
- Enforced confirmation for side-effecting tool names in `/v1/agent/execute-tool`.
- Added per-tool execution audit entries in action state (`executed_tools`).

Backend files:
- `backend/database/redis_db.py`
- `backend/routers/agent_tools.py`


## 3.3 Voice confirmation loop (yes/no by voice)

Implemented end-to-end support so confirmation can happen entirely by voice:

- Voice messages route through same agent path when agent mode is enabled.
- Voice is transcribed first, then fed into message/agent pipeline.
- Pending confirmation state is tracked in app provider.
- Spoken `yes/no` resolves confirmation and continues execution with same interaction id.

App files:
- `app/lib/providers/message_provider.dart`
  - Added pending confirmation state.
  - Added yes/no parser.
  - Added voice->transcribe->agent routing for agent mode.
- `app/lib/services/agent_chat_service.dart`
  - Added `awaitConfirmation` event handling and `interactionId` propagation.

VM harness file:
- `desktop/agent-cloud/agent.mjs`
  - Propagates `interaction_id` to backend tool execution.
  - Auto-proposes action state when missing.
  - Emits `await_confirmation` event to app.


## 4) API / Event Surface Added

## New live event
- `request_capture_photo`
  - Backend -> app
  - Triggered after activation-phrase detection in live transcript flow.

## New backend action APIs
- `POST /v1/agent/actions/propose`
- `POST /v1/agent/actions/confirm`
- `GET /v1/agent/actions/{interaction_id}`

## Tool execution payload extension
- `/v1/agent/execute-tool`
  - Added optional `interaction_id`.


## 5) Validation Performed

Ran targeted syntax/parse validation in this environment:

- Python compile checks:
  - `backend/models/message_event.py`
  - `backend/routers/transcribe.py`
  - `backend/database/redis_db.py`
  - `backend/routers/agent_tools.py`

- Node syntax check:
  - `desktop/agent-cloud/agent.mjs`

Status: pass for these checks.

Not executed in this environment (tooling unavailable):
- `black`
- `dart format`
- Flutter test/analyze scripts


## 6) Current MVP Behavior Snapshot

- Activation phrase in live transcript can trigger initial photo request event.
- App can issue one-shot photo capture to supported devices.
- Agent side-effecting tool calls now require explicit confirmation state.
- User can confirm by voice (`yes` / `no`) via the existing voice capture flow.
- Existing button-triggered voice capture remains compatible.


## 7) Known Gaps / Next Work

1. Tighten side-effect classification beyond tool-name heuristics.
2. Unify voice activation and chat flows under one explicit interaction-orchestrator state machine.
3. Expand confirmation UX and language handling (multilingual affirm/deny).
4. Add automated tests for:
- action state lifecycle
- confirmation enforcement
- await-confirmation event loop
- voice yes/no path
5. Run full repo formatting and test suites in CI/dev environment with required tooling.


## 8) Commit/Push Note

This folder is intended as a dated session artifact package for Mar 4 and should remain as a stable reference for MVP transformation decisions and implementation traceability.
