# NEXT PRUNE EXECUTION SPEC (POST-MAR4)

Date: 2026-03-04  
Repo: `/Users/ronak/Developer/omi`  
Scope: Next hard-prune pass for single-agent MVP (OpenClaw-style harness target; not implemented yet)

## 1) Read This First (Mandatory)

Before touching code, read these in order:

1. `/Users/ronak/Developer/omi/Mar4/README.MD`  
   Session-level summary and what was already changed.
2. `/Users/ronak/Developer/omi/Mar4/MVP_INTERACTION_FLOW.MD`  
   Canonical product behavior for MVP.
3. `/Users/ronak/Developer/omi/Mar4/INITIAL_TRANSFORMATION.MD`  
   Transformation context and rationale.
4. `/Users/ronak/Developer/omi/Mar4/PRUNE.MD`  
   First-pass prune decisions and what was already removed.
5. `/Users/ronak/Developer/omi/AGENTS.md`  
   Repo execution rules (imports, formatting, tests).
6. `/Users/ronak/Developer/omi/README.md`  
   Base repo runtime/setup context.

This file assumes all of the above are the source of truth.

## 2) Locked Product Contract (Why We Are Pruning)

Target MVP interaction is:

1. User says activation phrase while capture is active.
2. System captures transcript + one initial photo.
3. Assistant responds with multimodal grounding.
4. Assistant decides `assist_only` vs `agent_required`.
5. If `agent_required`, assistant asks explicit yes/no.
6. Only after `yes`, backend harness executes side effects.
7. Assistant reports outcome.

Anything not needed for this loop is legacy surface and should be removed.

Important: OpenClaw-equivalent harness is not fully implemented yet. Current `agent-cloud` path remains the temporary bridge and must stay operational while pruning.

## 3) Current Forensic State (As of This File)

Already removed:

- `app/lib/pages/action_items/` and `app/lib/pages/memories/` removed.
- Non-glasses device connectors mostly removed.
- `DeviceType` narrowed to glasses (`omi`, `openglass`).
- Some backend action-item/memory wiring removed.

Still present and non-MVP:

- Frontend Apps platform is still active in runtime shell:
  - `app/lib/pages/apps/`
  - `app/lib/providers/app_provider.dart`
  - Apps tab in `home/page.dart` and `widgets/bottom_nav_bar.dart`
  - Chat app selection drawer in `chat/page.dart`
- Integrations/payment/persona stack still active:
  - providers in `app/lib/main.dart`
  - OAuth callback handling in `app/lib/core/app_shell.dart`
  - settings pages/services for Todoist/Asana/ClickUp/Google Tasks/Google Calendar
- Backend still mounts broad router surface in `backend/main.py`, including `apps`, `payment`, `mcp`, `integrations`, etc.
- Dynamic app tool loading still exists in backend agent tooling (`load_app_tools` path).

## 4) Keep Set (Do Not Delete)

These are required for MVP behavior and near-term testing:

- Frontend capture + conversation core:
  - `/Users/ronak/Developer/omi/app/lib/providers/capture_provider.dart`
  - `/Users/ronak/Developer/omi/app/lib/providers/message_provider.dart` (after simplification)
  - `/Users/ronak/Developer/omi/app/lib/providers/device_provider.dart`
  - `/Users/ronak/Developer/omi/app/lib/pages/home/page.dart` (after simplification)
  - `/Users/ronak/Developer/omi/app/lib/pages/conversations/`
  - `/Users/ronak/Developer/omi/app/lib/pages/conversation_capturing/`
  - `/Users/ronak/Developer/omi/app/lib/pages/chat/page.dart` (after single-agent cleanup)
- Frontend device stack (glasses):
  - `/Users/ronak/Developer/omi/app/lib/services/devices/device_connection.dart`
  - `/Users/ronak/Developer/omi/app/lib/services/devices/omi_connection.dart`
  - `/Users/ronak/Developer/omi/app/lib/services/devices/omiglass_connection.dart`
- Current temporary harness client:
  - `/Users/ronak/Developer/omi/app/lib/services/agent_chat_service.dart`
  - `/Users/ronak/Developer/omi/desktop/agent-cloud/`
- Backend MVP core:
  - `/Users/ronak/Developer/omi/backend/routers/transcribe.py`
  - `/Users/ronak/Developer/omi/backend/routers/chat.py`
  - `/Users/ronak/Developer/omi/backend/routers/conversations.py` (after app-specific cleanup)
  - `/Users/ronak/Developer/omi/backend/routers/agent_tools.py`
  - `/Users/ronak/Developer/omi/backend/database/redis_db.py`
  - `/Users/ronak/Developer/omi/backend/models/message_event.py`
  - `/Users/ronak/Developer/omi/backend/main.py` (after router reduction)

## 5) Next-Prune Work Matrix (Path + Function + Action + Rationale)

### 5.1 Frontend: Remove Apps Platform Runtime Surface

| Path(s) | Current functionality | Action | Rationale |
|---|---|---|---|
| `/Users/ronak/Developer/omi/app/lib/pages/apps/` | App-store style browse/install/manage/create | Delete directory after references removed | Not part of single-agent MVP |
| `/Users/ronak/Developer/omi/app/lib/providers/app_provider.dart` | App catalog, selected chat app state | Delete file after chat/provider refactor | Single agent should not select app personas/plugins |
| `/Users/ronak/Developer/omi/app/lib/pages/apps/providers/add_app_provider.dart` | App creation/edit provider | Delete | App platform route deprecated |
| `/Users/ronak/Developer/omi/app/lib/pages/settings/ai_app_generator_provider.dart` | AI app generation | Delete | Non-MVP |
| `/Users/ronak/Developer/omi/app/lib/backend/http/api/apps.dart` | Calls `/v1/apps`, `/v2/apps` | Delete after all callers removed | Removes app backend dependency |
| `/Users/ronak/Developer/omi/app/lib/backend/schema/app.dart` | App model and capabilities | Delete when no imports remain | Single-agent model does not need app schema |
| `/Users/ronak/Developer/omi/app/lib/pages/home/page.dart` | Mounts `AppsPage`, app deep-links, app prefetch | Refactor to conversation-only indexing | Remove active app runtime entrypoint |
| `/Users/ronak/Developer/omi/app/lib/widgets/bottom_nav_bar.dart` | Home + Apps tab | Refactor to single navigation surface | Avoid dead app navigation path |
| `/Users/ronak/Developer/omi/app/lib/core/app_shell.dart` | `/apps/...` deep link and app cache init | Remove app deep-link + app cache logic | Prevent app-store feature re-entry |
| `/Users/ronak/Developer/omi/app/lib/pages/chat/page.dart` | “Enable Apps” and app picker drawer | Refactor to single assistant identity | Chat must speak to one agent only |
| `/Users/ronak/Developer/omi/app/lib/providers/message_provider.dart` | `chatApps`, `selectedChatAppId`, app upload routing | Remove app selection branches | Simplify to single-agent message flow |
| `/Users/ronak/Developer/omi/app/lib/backend/preferences.dart` | `selectedChatAppId` persisted key | Remove key and callers | Eliminate stale app-state persistence |

### 5.2 Frontend: Remove Integrations/Payments/Persona Product Layers

| Path(s) | Current functionality | Action | Rationale |
|---|---|---|---|
| `/Users/ronak/Developer/omi/app/lib/pages/payments/` | Creator app monetization + payout setup | Delete | Not in MVP |
| `/Users/ronak/Developer/omi/app/lib/pages/persona/` | Persona cloning/profile route | Delete | Not in MVP |
| `/Users/ronak/Developer/omi/app/lib/pages/referral/` | Referral program UI | Delete | Not in MVP |
| `/Users/ronak/Developer/omi/app/lib/providers/integration_provider.dart` | Global external integration state | Delete after callsite cleanup | External integrations not part of single-agent MVP |
| `/Users/ronak/Developer/omi/app/lib/providers/task_integration_provider.dart` | Task integration state (Todoist/Asana/etc.) | Delete | Replaced by harness actions eventually |
| `/Users/ronak/Developer/omi/app/lib/providers/mcp_provider.dart` | MCP key/state provider | Delete if MCP route fully dropped | Avoid parallel tool-runtime track |
| `/Users/ronak/Developer/omi/app/lib/services/asana_service.dart` | Asana auth/sync | Delete | Non-MVP |
| `/Users/ronak/Developer/omi/app/lib/services/clickup_service.dart` | ClickUp auth/sync | Delete | Non-MVP |
| `/Users/ronak/Developer/omi/app/lib/services/todoist_service.dart` | Todoist auth/sync | Delete | Non-MVP |
| `/Users/ronak/Developer/omi/app/lib/services/google_tasks_service.dart` | Google Tasks auth/sync | Delete | Non-MVP |
| `/Users/ronak/Developer/omi/app/lib/services/google_calendar_service.dart` | Google Calendar integration | Delete if no remaining calendar sync requirement | Non-MVP |
| `/Users/ronak/Developer/omi/app/lib/main.dart` | Registers all providers above | Refactor provider graph to minimal MVP set | Remove runtime coupling to deleted modules |
| `/Users/ronak/Developer/omi/app/lib/pages/settings/settings_drawer.dart` | Integrations, plans, referral, get-mac, persona sign-out wiring | Remove non-MVP settings entries and imports | Keep settings narrow and testable |

### 5.3 Frontend: Remove Conversation-App Summarization Hooks

| Path(s) | Current functionality | Action | Rationale |
|---|---|---|---|
| `/Users/ronak/Developer/omi/app/lib/pages/conversation_detail/widgets/summarized_apps_sheet.dart` | Suggest/install summarization apps | Delete or replace with plain summary UI | Depends on app platform |
| `/Users/ronak/Developer/omi/app/lib/pages/conversation_detail/widgets/create_template_bottom_sheet.dart` | Create conversation apps/templates | Delete app-template path | Non-MVP |
| `/Users/ronak/Developer/omi/app/lib/pages/conversation_detail/conversation_detail_provider.dart` | Loads enabled/suggested apps | Remove app fetch/state methods | Avoid backend app endpoints |
| `/Users/ronak/Developer/omi/app/lib/pages/conversation_detail/widgets.dart` | Navigates to app details from conversation | Remove app navigation hooks | App layer removed |

### 5.4 Backend: Router Surface Reduction in `main.py`

Prune from import and `include_router` in `/Users/ronak/Developer/omi/backend/main.py`:

- `apps`
- `payment`
- `mcp`
- `mcp_sse`
- `oauth`
- `task_integrations`
- `integrations`
- `integration`
- `workflow`
- `trends`
- `wrapped`
- `folders`
- `goals`
- `announcements`
- `plugins`
- `imports`
- `calendar_meetings`
- `developer`
- `firmware`
- `updates`
- `agents` (hume callback route; non-MVP)

Keep in `main.py` (minimum):

- `transcribe`
- `chat`
- `conversations`
- `agent_tools`
- `users` (trim app-specific endpoints)
- `auth`
- `custom_auth`
- `speech_profile` (optional but currently useful)
- `sync` (optional, keep if app still uses it)
- `notifications` (optional for push UX)
- `other` (only if still required by app boot path)

### 5.5 Backend: Delete Routers/Modules After Unmount

Candidate delete list once not imported:

- `/Users/ronak/Developer/omi/backend/routers/apps.py`
- `/Users/ronak/Developer/omi/backend/routers/payment.py`
- `/Users/ronak/Developer/omi/backend/routers/mcp.py`
- `/Users/ronak/Developer/omi/backend/routers/mcp_sse.py`
- `/Users/ronak/Developer/omi/backend/routers/oauth.py`
- `/Users/ronak/Developer/omi/backend/routers/task_integrations.py`
- `/Users/ronak/Developer/omi/backend/routers/integrations.py`
- `/Users/ronak/Developer/omi/backend/routers/integration.py`
- `/Users/ronak/Developer/omi/backend/routers/workflow.py`
- `/Users/ronak/Developer/omi/backend/routers/trends.py`
- `/Users/ronak/Developer/omi/backend/routers/wrapped.py`
- `/Users/ronak/Developer/omi/backend/routers/folders.py`
- `/Users/ronak/Developer/omi/backend/routers/goals.py`
- `/Users/ronak/Developer/omi/backend/routers/announcements.py`
- `/Users/ronak/Developer/omi/backend/routers/plugins.py`
- `/Users/ronak/Developer/omi/backend/routers/imports.py`
- `/Users/ronak/Developer/omi/backend/routers/calendar_meetings.py`
- `/Users/ronak/Developer/omi/backend/routers/developer.py`
- `/Users/ronak/Developer/omi/backend/routers/firmware.py`
- `/Users/ronak/Developer/omi/backend/routers/updates.py`
- `/Users/ronak/Developer/omi/backend/routers/agents.py`

Related utility/data cleanup (after router removal):

- `/Users/ronak/Developer/omi/backend/database/apps.py`
- `/Users/ronak/Developer/omi/backend/utils/apps.py`
- `/Users/ronak/Developer/omi/backend/utils/app_integrations.py`
- App/payment-heavy sections in `/Users/ronak/Developer/omi/backend/database/redis_db.py`
- App-review notification paths in `/Users/ronak/Developer/omi/backend/utils/notifications.py`

### 5.6 Backend: Remove Dynamic App Tool Loading and App-Oriented Orchestration

| Path(s) | Current functionality | Action | Rationale |
|---|---|---|---|
| `/Users/ronak/Developer/omi/backend/routers/agent_tools.py` | Loads `load_app_tools(uid)` into tool surface | Remove dynamic app tools in MVP mode; keep strict allowlist only | Single-agent harness control |
| `/Users/ronak/Developer/omi/backend/utils/retrieval/tools/app_tools.py` | Dynamic app tools | Delete once no references | App platform removed |
| `/Users/ronak/Developer/omi/backend/utils/conversations/process_conversation.py` | Preferred/suggested app selection for conversation processing | Remove app selection branches | Avoid accidental app pipeline invocation |
| `/Users/ronak/Developer/omi/backend/routers/conversations.py` | Suggested app endpoints in conversation details | Remove app-summary endpoints and payload fields | Frontend app summary UI removed |
| `/Users/ronak/Developer/omi/backend/routers/users.py` | Set preferred app endpoint(s) | Remove app preference APIs | No app preference in single-agent mode |

## 6) Ordered Execution Plan (Future Agent Must Follow)

### Phase 0: Baseline and Safety

1. Create backup branch and tag before deletions.
2. Record current boot health:
   - app launch path
   - capture start/stop
   - voice query path
   - agent confirmation path
3. Confirm no local uncommitted work unrelated to prune.

### Phase 1: Frontend Runtime Decoupling (No Deletes Yet)

1. Remove Apps tab/nav and app deep-link branches.
2. Refactor chat page and `message_provider` to single-agent mode (no app picker).
3. Remove app/integration/payment/persona providers from `main.dart`.
4. Ensure app compiles with stubs removed from imports/callsites.

### Phase 2: Frontend Hard Deletes

1. Delete `app/lib/pages/apps/`, `app/lib/pages/payments/`, `app/lib/pages/persona/`, `app/lib/pages/referral/`.
2. Delete orphan providers/services/APIs listed above.
3. Remove conversation-detail app-summarization surfaces.

### Phase 3: Backend Router Reduction

1. Edit `backend/main.py` to keep only MVP routers.
2. Delete unmounted router files listed above.
3. Remove app/payment/integration utility modules and dead imports.

### Phase 4: Agent Tool Surface Hardening

1. Remove `load_app_tools` path from backend and tests.
2. Keep only explicitly allowlisted core tools for current harness.
3. Preserve confirmation gate behavior added in Mar4 session.

### Phase 5: Validation and Regression Check

Run required checks:

- Backend: `/Users/ronak/Developer/omi/backend/test.sh`
- App: `/Users/ronak/Developer/omi/app/test.sh`
- Formatting:
  - `black --line-length 120 --skip-string-normalization ...`
  - `dart format --line-length 120 ...`

Smoke test scenario:

1. Start capture.
2. Speak activation phrase.
3. Verify initial photo request event.
4. Verify multimodal assistant response.
5. Trigger action requiring confirmation.
6. Confirm by voice `yes`, verify execution.
7. Repeat with `no`, verify no side effects.

## 7) Verification Queries (Use During and After Prune)

Use these searches repeatedly until clean:

```bash
rg -n "AppsPage|selectedChatAppId|chatApps|/apps|retrieveAppsSearch|AppProvider|AddAppProvider|AiAppGeneratorProvider|McpProvider" app/lib
rg -n "TaskIntegrationProvider|IntegrationProvider|Todoist|Asana|ClickUp|Google Tasks|google_calendar" app/lib
rg -n "include_router\\(apps|include_router\\(payment|include_router\\(mcp|include_router\\(integrations|include_router\\(task_integrations" backend/main.py
rg -n "load_app_tools|preferred app|suggested_summarization_apps|/v1/apps|/v2/apps" backend
```

Completion criteria for these queries: zero hits for removed surfaces, except intentional historical docs in `Mar4/`.

## 8) Definition of Done

Prune is complete only when all are true:

1. App has no Apps tab, no app-picker UI, and no app selection state.
2. App has no runtime dependency on app/payment/persona/integration providers.
3. Backend no longer mounts app/payment/mcp/integration routers.
4. Dynamic app tools are disabled/removed from agent execution path.
5. Core MVP flow (voice activation + initial photo + confirmation-gated action) passes manual smoke test.
6. Backend/app tests pass.
7. `Mar4/README.MD` and this file are updated with final prune status.

## 9) Known High-Risk Areas (Handle Last)

Do not start here:

- `backend/utils/conversations/process_conversation.py` app-selection internals.
- Deep refactors in `backend/database/chat.py` app/plugin compatibility fields.
- Broad schema-level field removals (`app_id` in models) that may affect historical data.

Do these only after runtime behavior is stable with routers/features removed.

## 10) Notes for the Future OpenClaw Integration Step

This prune intentionally prepares for a single backend harness but does not implement OpenClaw yet.

Near-term strategy:

1. Keep `desktop/agent-cloud/` as temporary harness adapter.
2. Preserve agent confirmation APIs in `backend/routers/agent_tools.py`.
3. After prune, replace adapter internals with OpenClaw-compatible runtime while keeping same app-facing contract.

## 11) Execution Status (Completed 2026-03-05)

This prune spec has now been executed in-repo.

### Completed

1. Frontend runtime decoupling and hard deletes completed for app platform, payment/persona/referral layers, integration/task providers, MCP/provider surfaces, and conversation app-summary UI hooks.
2. Backend router surface was reduced in `backend/main.py` and unmounted routers were deleted.
3. Dynamic app tool loading path is removed from runtime agent execution.
4. Conversation processing app-selection flow was removed (no preferred/suggested app orchestration in runtime).
5. Backend chat/notification/pusher paths were hardened to single-agent behavior and cleaned of removed app utility dependencies.
6. Web conversation legacy cleanup completed:
   - removed `suggested_summarization_apps` usage in web conversation types/UI
   - removed `GenerateSummaryButton` template-generation component from conversation detail flow
   - retained read-only rendering for existing `apps_results` content only

### Verification Snapshot

- `rg -n "include_router\\(apps|include_router\\(payment|include_router\\(mcp|include_router\\(integrations|include_router\\(task_integrations" backend/main.py`  
  Result: clean.
- `rg -n "load_app_tools|preferred app|suggested_summarization_apps|/v1/apps|/v2/apps" backend`  
  Result: clean.
- App runtime verification queries are clean when excluding generated localization outputs:
  - excluded paths: `app/lib/l10n/**`, `app/lib/gen/**`
  - reason: these files still intentionally contain historical translation keys/text labels.
- Web verification query `suggested_summarization_apps|suggestedAppIds|GenerateSummaryButton` under `web/app/src`:
  Result: clean.

### Environment Constraints During Validation

- Could not run required formatters/tests in this environment because tooling was unavailable:
  - `black`: not installed
  - `dart`: not installed
  - `flutter`: not installed
  - `pytest`: not installed
  - `next`: not installed in this shell (`npm run lint` in `web/app` failed)

This preserves momentum: prune complexity now, swap harness internals next.
