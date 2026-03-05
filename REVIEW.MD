# REVIEW: Post-Prune Forensic Audit (MVP Alignment)

Date: 2026-03-04  
Repo: `/Users/ronak/Developer/omi`  
Reference docs reviewed:
- `/Users/ronak/Developer/omi/Mar4/README.MD`
- `/Users/ronak/Developer/omi/Mar4/MVP_INTERACTION_FLOW.MD`
- `/Users/ronak/Developer/omi/Mar4/PRUNE.MD`
- `/Users/ronak/Developer/omi/Mar4/NEXT_PRUNE.MD`

## 1) MVP Contract Check (Current State)

Expected contract (from `Mar4/MVP_INTERACTION_FLOW.MD`):
1. Voice activation phrase starts interaction.
2. Initial photo is captured automatically.
3. First AI response is grounded in that activation utterance + initial photo.
4. AI can clarify intent.
5. Side-effecting action requires explicit yes/no confirmation.
6. Backend agent executes only after yes.
7. AI reports final result.

Current status:
- 1: Partial
- 2: Implemented
- 3: Not implemented end-to-end
- 4: Partial
- 5: Partial with bypass risk
- 6: Partial with scope risk
- 7: Partial

## 2) Findings (Severity Ordered)

### [P0] F1 - Activation phrase path does not trigger first AI conversation response

What is happening:
- Backend detects activation phrase and emits `request_capture_photo`.
- App captures a single photo.
- There is no orchestration that sends the activation utterance + photo into chat/agent flow automatically.

Evidence:
- `backend/routers/transcribe.py:738-770` only emits `RequestCapturePhotoEvent`.
- `app/lib/providers/capture_provider.dart:1492-1521` only triggers `cameraTakePhoto()`.
- `app/lib/backend/schema/message_event.dart` has only `request_capture_photo` for this flow, no `initial_photo_ready` / `assistant_response` / dispatch contract events.
- No MVP dispatcher endpoint exists (no `/v1/mvp/interaction/dispatch` equivalent in backend).

Impact:
- Core contract mismatch: user saying “AI, what am I looking at?” does not reliably start an immediate AI conversation grounded in that initial image.

Required change:
- Add interaction orchestrator state and dispatch path that binds:
  - activation transcript segment
  - auto-captured initial photo
  - deterministic first assistant response.
- Keep this in one interaction id through confirmation and execution lifecycle.

---

### [P0] F2 - Confirmation gate can be bypassed by mutating tools due name-heuristic classification

What is happening:
- Side effects are inferred by tool name substrings.
- Unknown names default to non-mutating.

Evidence:
- `backend/routers/agent_tools.py:186-199` (`_is_side_effecting_tool_name`) defaults unknown tools to non-mutating.
- `backend/utils/retrieval/tools/notification_settings_tools.py:93-116` mutates user settings (`set_daily_summary_enabled`, `set_daily_summary_hour_local`) via `manage_daily_summary_tool`, but this name is not reliably classified as side-effecting.

Impact:
- Some state-changing tools can execute without explicit user confirmation.

Required change:
- Replace name heuristics with explicit per-tool policy metadata.
- Enforce confirmation from policy (`requires_confirmation: true`) instead of string matching.

---

### [P0] F3 - Confirmation approval is not bound to the specific approved tool/action

What is happening:
- Action proposal stores `proposed_tools`, but execution checks only confirmed status.

Evidence:
- Proposal state stores tools in `backend/routers/agent_tools.py:340-343`.
- Execution path only checks `status == confirmed` in `backend/routers/agent_tools.py:201-218,457-460`.
- No validation that `body.tool_name` is inside approved `proposed_tools`.

Impact:
- User may approve one action summary, but agent can execute different side-effecting tools under same `interaction_id`.

Required change:
- Enforce tool-level binding at execution:
  - tool must be in approved list for the interaction.
  - optionally bind params hash or action plan id to prevent drift.

---

### [P0] F4 - Current harness remains over-permissive versus single-agent MVP safety model

What is happening:
- VM agent allows broad local tools and bypass permissions.

Evidence:
- `desktop/agent-cloud/agent.mjs:658-669` allows `Read`, `Write`, `Edit`, `Bash`, `WebSearch`, `WebFetch` with `permissionMode: "bypassPermissions"` and `allowDangerouslySkipPermissions: true`.
- Prompt still advertises broad capabilities including Playwright and legacy data families in `desktop/agent-cloud/agent.mjs:201-214`.

Impact:
- Side effects can happen outside backend confirmation path and outside MVP’s constrained harness model.

Required change:
- Restrict allowed local tools for MVP.
- Remove dangerous permission bypass in MVP mode.
- Keep only required read/query operations and backend-mediated actions with confirmation.

---

### [P1] F5 - Action-item feature surface still active in app, but backend endpoints were removed

What is happening:
- App still renders action items in conversation detail and calls removed endpoints.

Evidence:
- App API still calls removed endpoints:
  - `app/lib/backend/http/api/conversations.dart:297,317,329` (`/v1/conversations/{id}/action-items...`).
- UI still uses these calls:
  - `app/lib/pages/conversation_detail/widgets.dart:489-575`.
  - `app/lib/pages/conversation_detail/conversation_detail_provider.dart:167-170`.
- Backend router no longer has these routes:
  - `backend/routers/conversations.py` has no `/action-items` route definitions.

Impact:
- User can still see/modify action-item UI states, but backend updates 404/fail.
- This directly conflicts with “remove memories/action items related items.”

Required change:
- Remove action-item UI/API paths from active app runtime.
- Remove related provider methods and stale API helpers.

---

### [P1] F6 - Core backend processing still performs memory/action-item/goals/trends pipelines (scope drift)

What is happening:
- Conversation finalization still runs legacy extraction and mutation threads.

Evidence:
- `backend/utils/conversations/process_conversation.py` imports and executes:
  - memories (`:13`, `:279-377`, `:588`)
  - action items (`:19`, `:401-451`, `:590`)
  - trends (`:18`, `:394-399`, `:589`)
  - goals (`:51`, `:259-277`, `:591`)

Impact:
- Extra latency, cost, side effects, and non-MVP data churn in production path.

Required change:
- Gate or remove non-MVP processors for this branch.
- Keep only data needed for conversation history + image-grounded assistant + confirmation-gated agent actions.

---

### [P1] F7 - Dangling imports/test artifacts remain from deleted routers/modules

What is happening:
- Post-prune code still references deleted modules in runtime-adjacent utilities and test/dev scripts.

Evidence:
- Runtime utility:
  - `backend/utils/task_sync.py:48` imports deleted `routers.task_integrations`.
- Unit tests:
  - `backend/tests/unit/test_desktop_updates.py:22` imports deleted `routers.updates`.
  - `backend/tests/unit/test_firmware_pagination.py:26` imports deleted `routers.firmware`.
- Chaos scripts:
  - `backend/testing/chaos-oom/pusher_fixed.py:31-32`.
  - `backend/testing/chaos-oom/pusher_vuln.py:46-47`.

Impact:
- CI/test failures and brittle future refactors.
- Hidden runtime error risk if `task_sync` path is triggered.

Required change:
- Remove/update stale tests and scripts.
- Replace or delete dead task sync path if task integrations are no longer part of MVP.

---

### [P2] F8 - User-facing copy and telemetry still reference “memories” model

Evidence:
- `app/lib/providers/message_provider.dart:418,426` loading text still says “Reading your memories...” and “Learning from your memories...”.

Impact:
- Product messaging drift from current MVP framing.

Required change:
- Update copy to conversation-first language consistent with MVP.

---

### [P2] F9 - Web app still contains legacy app-platform API clients

Evidence:
- `web/app/src/lib/api.ts` and `web/app/src/lib/api/public.ts` still call `/v1/apps` and `/v2/apps` paths.

Impact:
- If web is still used, calls can fail since backend app routers were removed.

Required change:
- Remove dead web app-platform client surface or explicitly de-scope web for MVP.

## 3) What Is Aligned/Healthy

- Backend router surface reduction in `backend/main.py` is in place.
- App runtime app-store tab/path is removed from primary navigation.
- Glasses-only device path appears enforced at enum/runtime level (`DeviceType` reduced to `omi`, `openglass`).
- Voice confirmation plumbing exists end-to-end (`await_confirmation` event + yes/no handling + confirm endpoint).
- `request_capture_photo` event path is implemented and wired through BLE single-shot camera command.

## 4) Recommended Execution Order

1. Fix P0 safety and contract gaps first:
   - F1, F2, F3, F4.
2. Remove broken residual surfaces:
   - F5, F6, F7.
3. Finish polish and consistency:
   - F8, F9.

## 5) Validation Notes

In this environment, full framework test runs were not executed because core tooling is not installed (`pytest`, `dart`, `flutter`, `black`).
The review used static code path analysis, router/endpoint diff checks, and cross-reference verification against the Mar4 contract docs.
