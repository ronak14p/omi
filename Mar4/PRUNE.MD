# PRUNE PLAN FOR MVP (OPENCLAW-STYLE HARNESS)

Date: 2026-03-04
Repo: `/Users/ronak/Developer/omi`

## 1) Goal and Scope Lock

Target MVP flow (must be preserved):
1. User says activation phrase.
2. System starts/continues transcript capture.
3. System captures one initial photo automatically.
4. AI responds grounded in transcript + photo.
5. AI decides `assist_only` vs `agent_required`.
6. For `agent_required`, AI asks explicit yes/no confirmation.
7. Backend harness executes only after yes.
8. AI reports backend result.

This prune review is optimized for that flow only (no app-store/platform route).

## 2) Forensic Snapshot (Current Surface Area)

Current codebase still carries broad Omi product surface beyond MVP:

- Backend routers loaded in `/Users/ronak/Developer/omi/backend/main.py`: 30+ modules.
- Backend route count in `backend/routers/*.py`: ~339 endpoints.
- If we keep only MVP-critical router families, we can remove about 66% of route surface.
- App bootstraps 30+ providers in `/Users/ronak/Developer/omi/app/lib/main.dart` (many non-MVP).
- Home shell still includes 4-tab product UI (Conversations, Action Items, Memories, Apps) in `/Users/ronak/Developer/omi/app/lib/pages/home/page.dart`.
- Repo has large non-MVP top-level components:
  - `plugins/` (~209M)
  - `omi/` (~77M)
  - `sdks/` (~76M)
  - `docs/` (~74M)
  - `desktop/` (~53M, but only a small part is needed for harness)
  - `web/` (~17M)

## 3) Do Not Prune (MVP-Critical Keep Set)

Keep these intact for MVP:

- App capture and AI interaction core:
  - `/Users/ronak/Developer/omi/app/lib/providers/capture_provider.dart`
  - `/Users/ronak/Developer/omi/app/lib/providers/message_provider.dart`
  - `/Users/ronak/Developer/omi/app/lib/providers/device_provider.dart`
  - `/Users/ronak/Developer/omi/app/lib/services/devices/device_connection.dart`
  - `/Users/ronak/Developer/omi/app/lib/services/devices/omi_connection.dart`
  - `/Users/ronak/Developer/omi/app/lib/services/devices/omiglass_connection.dart`
  - `/Users/ronak/Developer/omi/app/lib/services/agent_chat_service.dart`

- Backend capture + chat + agent core:
  - `/Users/ronak/Developer/omi/backend/routers/transcribe.py`
  - `/Users/ronak/Developer/omi/backend/routers/chat.py`
  - `/Users/ronak/Developer/omi/backend/routers/conversations.py`
  - `/Users/ronak/Developer/omi/backend/routers/agent_tools.py`
  - `/Users/ronak/Developer/omi/backend/agent-proxy/`
  - `/Users/ronak/Developer/omi/backend/database/redis_db.py`
  - `/Users/ronak/Developer/omi/backend/models/message_event.py`

- Side services for live audio stack:
  - `/Users/ronak/Developer/omi/backend/pusher/` (if pusher mode enabled)
  - `/Users/ronak/Developer/omi/backend/diarizer/`
  - `/Users/ronak/Developer/omi/backend/modal/`

- Harness runtime:
  - `/Users/ronak/Developer/omi/desktop/agent-cloud/`

- Glasses firmware:
  - `/Users/ronak/Developer/omi/omiGlass/firmware/`

## 4) High-Confidence Prune Candidates

These are the best cuts with low MVP risk.

### 4.1 Repository-level removals (safe with your MVP direction)

Candidate remove/archive:

- `/Users/ronak/Developer/omi/legacy/`
- `/Users/ronak/Developer/omi/web/`
- `/Users/ronak/Developer/omi/sdks/`
- `/Users/ronak/Developer/omi/mcp/`
- `/Users/ronak/Developer/omi/plugins/`
- `/Users/ronak/Developer/omi/evidence/` (if not needed for audit)
- `/Users/ronak/Developer/omi/codemagic-builds.png`
- `/Users/ronak/Developer/omi/codemagic-builds-2.png`

Notes:
- `plugins/` is large and aligned with the app-store/plugin strategy you already dropped.
- Keep a separate archive branch/tag before hard delete.

### 4.2 Backend router de-scope

In `/Users/ronak/Developer/omi/backend/main.py`, remove non-MVP router includes after migration:

- `apps`
- `payment`
- `mcp`
- `mcp_sse`
- `developer`
- `imports`
- `wrapped`
- `goals`
- `announcements`
- `task_integrations`
- `integrations`
- `integration`
- `workflow`
- `trends`
- `knowledge_graph`
- `folders`
- `calendar_meetings`
- `plugins`
- `oauth`
- `updates`
- `firmware`
- `agents`

Keep minimal router set for MVP:

- `transcribe`
- `chat`
- `conversations`
- `agent_tools`
- `users` (subset)
- `auth` / `custom_auth`
- `speech_profile` (optional but useful)
- `notifications` (optional)
- `sync` (optional; keep if your app flow still reads synced audio/files)

### 4.3 Backend tool-surface reduction

Current expansion points to trim:

- Dynamic app tool loading in:
  - `/Users/ronak/Developer/omi/backend/routers/agent_tools.py`
  - `/Users/ronak/Developer/omi/backend/utils/retrieval/agentic.py`

Prune action:

- Remove `load_app_tools(uid)` from tool registration and execution in MVP mode.
- Keep only strict allowlisted first-party tools.
- Disable tool families not needed for MVP launch:
  - app-manifest/dynamic tools
  - chart/screen-activity/health tools unless explicitly required by your MVP set

### 4.4 App-side feature removals

Current non-MVP load points:

- `MultiProvider` in `/Users/ronak/Developer/omi/app/lib/main.dart` creates many non-MVP providers (MCP, apps, payments, persona, goals, integrations, announcements, etc.).
- Home tabs in `/Users/ronak/Developer/omi/app/lib/pages/home/page.dart` still include Action Items, Memories, Apps.
- Deep links/OAuth callbacks in `/Users/ronak/Developer/omi/app/lib/core/app_shell.dart` cover app store, wrapped, task integrations.

Prune action:

- Move to a minimal provider set for capture/chat/agent.
- Collapse home UI to MVP pages only.
- Remove or disable non-MVP deep-link handlers.
- Remove app-store/payments/persona/task-integration pages and providers.

### 4.5 Device support narrowing

Current app supports many devices in `/Users/ronak/Developer/omi/app/lib/backend/schema/bt_device/bt_device.dart` and `/Users/ronak/Developer/omi/app/lib/services/devices/`.

Prune action:

- Keep only glasses path (`openglass`/`omiglass`) for MVP branch.
- Remove device connectors for Apple Watch, Bee, Plaud, Friend Pendant, Fieldy, Frame, Limitless.

### 4.6 Desktop subtree narrowing

For your harness-first MVP, keep only:

- `/Users/ronak/Developer/omi/desktop/agent-cloud/`

Candidate remove/archive:

- `/Users/ronak/Developer/omi/desktop/Desktop/`
- `/Users/ronak/Developer/omi/desktop/Backend-Rust/`
- `/Users/ronak/Developer/omi/desktop/acp-bridge/`
- `/Users/ronak/Developer/omi/desktop/demo/`
- desktop release/distribution scripts not used by agent-cloud deploy.

### 4.7 CI/CD and infra cleanup

Trim workflows not needed for MVP runtime:

- Web/persona/plugins/apps-js deploy workflows.
- Desktop auto-release workflows.
- SDK/docs sync workflows (if you are freezing public OSS distribution during MVP).

Keep workflows only for:

- backend listen service
- agent-proxy
- pusher/diarizer/vad (if deployed)
- tests/lint for kept components

## 5) Prune Order (Recommended)

### Phase A: Soft-prune (no hard delete)

1. Add `MVP_MODE=true` and gate non-MVP routers/features off.
2. Disable dynamic tools and non-MVP UI tabs/providers.
3. Run end-to-end flow tests with current hardware simulator paths.

### Phase B: Hard-prune after flow passes

1. Delete gated-off routers/pages/providers.
2. Delete non-MVP top-level directories.
3. Reduce CI workflows/charts to kept services.

### Phase C: Stabilize

1. Run backend tests and app tests.
2. Run scripted smoke test for exact MVP interaction flow.
3. Verify no non-MVP endpoints are still called by app startup.

## 6) Risky Areas to Delay Until Last

Do these only after MVP flow is fully stable:

- Deep surgery in `process_conversation.py` (currently coupled to memories/goals/apps/folders/trends).
- Removing `users.py` routes broadly (many shared profile/settings dependencies).
- Removing `sync.py` before confirming app no longer needs file/audio retrieval helpers.

## 7) Clarifications Needed Before I Execute the Prune

1. Do you want a **glasses-only app branch** now (remove all non-glasses device connectors), or keep multi-device support for later?
2. For MVP UI, should we keep only **one conversation screen** plus capture, or also keep conversation history browsing?
3. Should we remove `memories` and `action_items` features entirely from app/backend now, or keep read-only support temporarily?

## 8) Clarifications Received and Applied (2026-03-04)

Confirmed choices:

1. Glasses-only device direction.
2. Keep conversation history browsing.
3. Remove memories and action-items UX/API wiring from active MVP flow.

Applied in code (this branch):

- App navigation:
  - Removed Action Items and Memories tabs from bottom navigation.
  - Kept conversation history as primary tab.
  - Kept Apps tab index for compatibility, but removed memories/action-items entry points.
- App provider wiring:
  - Removed `ActionItemsProvider` and `MemoriesProvider` from app bootstrap providers.
  - Removed action-item deep-link handling from app shell.
- Conversations UI:
  - Removed Daily Score / Today Tasks widgets from conversations page (both depended on action-items/memories).
- Device support:
  - Restricted active discovery/connection flow to Omi/OmiGlass path.
  - Removed Apple Watch discovery from device service.
  - Removed Apple Watch onboarding branch from device selection flow.
  - Trimmed connection guide choices to Omi Glass only.
- Backend:
  - Removed `action_items` and `memories` routers from backend app registration.
  - Removed conversation action-item mutation endpoints from `routers/conversations.py`.
  - Removed memory/action-item tools from `utils/retrieval/agentic.py` core tool list and tool display routing.

Notes:

- Full hard deletion of all legacy non-glasses files is intentionally deferred to a second pass after runtime validation, to reduce regression risk.
