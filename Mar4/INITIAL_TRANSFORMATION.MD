# INITIAL TRANSFORMATION

Date: 2026-03-04
Repository: `/Users/ronak/Developer/omi`
Goal: Deliver a strict MVP for continuous multimodal assistant behavior (hearing + sight), with clear split between simple assistant responses and server-side agent execution.
Source of truth for MVP use cases: `/Users/ronak/Library/Mobile Documents/iCloud~md~obsidian/Documents/avonlabs_obs/101_PROJECT_SKEYE/use cases.md`

## 1) Executive Recommendation
Use an **OpenClaw-style harness-first strategy only** (no platform/app-store path), and reuse the existing stack already in this repo:
- Capture path: `app` + `backend/routers/transcribe.py` + `omiGlass/firmware`
- Agent harness path: `backend/agent-proxy/main.py` + `desktop/agent-cloud/agent.mjs` + `backend/routers/agent_tools.py`

Decision lock:
- Do not build third-party app marketplace capabilities in MVP.
- Do not rely on broad dynamic app tools in MVP.
- Build one first-party harness with strict policy and confirmation gates for your 20 use cases.

## 2) Scope Lock (MVP Only)
In scope:
- Audio + photo capture while active session is running.
- Simple ask path that answers directly.
- Agent action path that executes real tasks on user intent.
- Confirmation and audit for side-effecting actions.
- Use-case coverage strictly aligned to the 20 items in your Obsidian table.

Out of scope for MVP:
- Full app marketplace/platform expansion.
- Broad arbitrary tool execution from all installed apps.
- General-purpose autonomous desktop control without policy gates.

## 3) Forensic Findings (Code Evidence)

### P0 (must fix before MVP hardware test)
1. **Action path is split and inconsistent for voice from glasses**
- Evidence:
  - Voice command from button path calls voice message API: `app/lib/providers/capture_provider.dart:477`, `:587`, `:602`
  - Voice message path sends to `/v2/voice-messages`: `app/lib/providers/message_provider.dart:505`
  - VM agent path is only chat text when `claudeAgentEnabled`: `app/lib/providers/message_provider.dart:607`, `:691`
- Impact:
  - Same user intent can execute through different engines (backend graph vs VM harness), making behavior and safety inconsistent.

2. **VM agent runtime is over-permissive by default**
- Evidence:
  - Allowed tools include `Write`, `Edit`, `Bash`, `WebSearch`, `WebFetch`: `desktop/agent-cloud/agent.mjs:532-541`, `:656-657`
  - Permissions bypassed: `permissionMode: "bypassPermissions"`, `allowDangerouslySkipPermissions: true`: `desktop/agent-cloud/agent.mjs:542-544`, `:657-658`
- Impact:
  - Too much authority for an MVP that must be predictable and safe during first live wearable tests.

3. **No mandatory confirmation gate for side-effecting backend tools**
- Evidence:
  - Tool execution endpoint directly invokes tool: `backend/routers/agent_tools.py:263-307`
  - Calendar tools perform create/update/delete directly: `backend/utils/retrieval/tools/calendar_tools.py:733`, `:931`, `:1195`
- Impact:
  - Accidental or misunderstood actions can execute without explicit user confirmation.

4. **Dynamic tool surface is unbounded for MVP**
- Evidence:
  - Core tools + all enabled app tools loaded dynamically: `backend/utils/retrieval/agentic.py:362-369`
  - App tools call arbitrary endpoints from manifests: `backend/utils/retrieval/tools/app_tools.py:250-301`, `:167-247`
- Impact:
  - Tooling can expand unpredictably beyond MVP use-case boundaries.

### P1 (high priority)
5. **VM path is currently text-first, not truly multimodal input from app side**
- Evidence:
  - Agent query sends `{"type":"query","prompt": ...}` only: `app/lib/services/agent_chat_service.dart:203`
  - `_sendMessageViaAgent` clears files and sends text prompt only: `app/lib/providers/message_provider.dart:696-733`
- Impact:
  - Sight context is not first-class in agent action flow.

6. **Agent feature is hidden behind experimental toggle**
- Evidence:
  - `claudeAgentEnabled` in developer mode: `app/lib/providers/developer_mode_provider.dart:44`, `:284-322`
- Impact:
  - Operational setup friction when you are ready to live-test with glasses.

7. **Insufficient test coverage for critical agent-proxy/agent-tools path**
- Evidence:
  - `backend/test.sh` runs many unit tests, but no targeted `agent-proxy` or `agent_tools` test suite listed: `backend/test.sh:9-36`
- Impact:
  - Safety and reliability regressions likely during rapid MVP iteration.

8. **Duplicated VM lifecycle logic in two backend services**
- Evidence:
  - Similar start/check/restart flow in `backend/agent-proxy/main.py` and `backend/routers/agent_tools.py`
- Impact:
  - Drift risk and harder debugging.

### P2 (important cleanup)
9. **Photo interval command currently ignored by firmware logic**
- Evidence:
  - Control accepts `5..300` but forces fixed interval from config: `omiGlass/firmware/src/app.cpp:736-747`
  - Fixed interval in config: `omiGlass/firmware/src/config.h:54`
- Impact:
  - Harder to tune capture frequency for first hardware trials.

10. **Docs drift in service map across repo instructions**
- Evidence:
  - `AGENTS.md` chart list omits `agent-proxy` while chart exists and `CLAUDE.md` includes it.
- Impact:
  - Team confusion during deployment and debugging.

11. **`desktop/agent-cloud` package scripts reference missing script files**
- Evidence:
  - `desktop/agent-cloud/package.json` contains `deploy` and `upload-db` scripts referencing `scripts/*.sh` that are not present.
- Impact:
  - Automation reliability issues for harness deployment/testing.

## 4) What Already Works (Reusable)
1. **Continuous hearing + sight ingestion path exists**
- Audio WS ingest: `backend/routers/transcribe.py:2212`
- Photo chunk ingest + image description: `backend/routers/transcribe.py:1749`, `:1942`
- App sends image chunks from glasses: `app/lib/providers/capture_provider.dart:783-821`
- Firmware sends photo chunks and audio over BLE: `omiGlass/firmware/src/app.cpp:935-987`, `:361-376`

2. **Simple ask path exists and is production-proven**
- Chat stream: `backend/routers/chat.py:69-207`
- Voice command stream path: `backend/routers/chat.py:331-353`
- Graph routing simple vs context/agentic: `backend/utils/retrieval/graph.py:135-175`

3. **Server-side agent harness components already exist**
- Agent proxy websocket bridge: `backend/agent-proxy/main.py:380-580`
- VM side persistent query server: `desktop/agent-cloud/agent.mjs:1267-1404`
- Backend tool discovery/execution for VM: `backend/routers/agent_tools.py:240-307`

## 5) Use-Case Readiness Matrix (Current State)

| # | Use Case | Current Readiness | Notes |
|---|---|---|---|
| 1 | Email to Calendar automation | Partial | Calendar + Gmail tools exist; needs strict confirmation and intent routing. |
| 2 | Cooking/Baking guidance | Partial | Vision + speech available; needs tighter multimodal prompting path. |
| 3 | In-store price compare + auto-purchase | Partial | Web search possible; purchase actions not productized safely. |
| 4 | Travel disruption management | Partial | Calendar actions exist; travel provider actions not standardized. |
| 5 | Workout logging + form analysis | Partial | Health tools exist; visual form analysis flow not explicit. |
| 6 | Contract analysis + email drafting | Partial | File chat exists; transactional email-send path not hardened. |
| 7 | Home repair diagnostics | Partial | Vision + web search feasible; no structured contractor handoff path. |
| 8 | Business card networking automation | Partial | Vision/OCR possible; CRM/LinkedIn action path missing. |
| 9 | Receipt scanning + expense automation | Partial | Vision extraction feasible; accounting integrations missing. |
| 10 | Educational explanation + note save | Partial | Explanation easy; note-saving action should be explicit tool. |
| 11 | Sign/menu translation + flashcards | Partial | Translation possible; flashcard save flow missing. |
| 12 | Meeting capture + summary + tasks | Strong Partial | Capture + summaries + action items exist; needs predictable action policy. |
| 13 | Medication reminders + health logging | Partial | Could map to task/reminder actions; domain-specific safety missing. |
| 14 | Pantry scan + delivery order | Partial | Scene understanding possible; checkout integrations missing. |
| 15 | Outfit styling advice | Partial | Vision advice feasible; shopping actions missing. |
| 16 | Parenting/homework assistance | Partial | Vision + ask path feasible; school-system actions missing. |
| 17 | Vehicle diagnostics + service scheduling | Partial | Advice possible; diagnostics/service integrations missing. |
| 18 | Plant identification + advice | Partial | Vision + advice feasible; action automation not needed initially. |
| 19 | Content creation assistance while filming | Partial | Advisory support possible; edit/post actions missing. |
| 20 | Elderly companion + safety alerts | Partial | Conversational support possible; robust safety-alert detection missing. |

Interpretation: none of the 20 are "fully production-ready" in current shape for strict MVP testing. Core substrate exists, but policy, routing, and bounded action packs are missing.

## 6) Target MVP Architecture

### Decision model
- `Assist Mode`: quick response, no irreversible side effects.
- `Act Mode`: plan -> confirm -> execute -> verify -> report.

### Required control points
1. **Intent router**: classify each request into `assist` or `act`.
2. **Tool policy**: allowlist by use-case pack; deny everything else.
3. **Confirmation gate**:
- Required for any create/update/delete/send/external side-effect.
- Explicit user confirmation event before execution.
4. **Audit ledger**:
- Store: intent, tool plan, confirmation, execution result, artifact links.
5. **Unified multimodal context object**:
- Last transcript window + latest photo descriptions + optional raw references.

### OpenClaw-style Harness Design (MVP)
Use a single orchestration loop for `Act Mode`:
1. **Ingest**: Build one `capture_context` object from:
- voice transcript
- recent transcript window
- recent image descriptions (and optional raw image refs)
2. **Plan**: Agent proposes a structured action plan:
- `goal`
- `steps[]`
- `tools[]`
- `expected_outcome`
- `risk_level`
3. **Policy check**: Server validates the plan against MVP allowlist and risk rules.
4. **Confirm**: For side-effecting plans, require explicit user confirmation.
5. **Execute**: Run tool steps sequentially with per-step timeout and retries.
6. **Verify**: Confirm outcome with read-back tool call or API response validation.
7. **Report**: Return concise result + what changed.
8. **Audit**: Persist full trace (plan, confirmation, tool calls, outputs, final status).

Suggested ownership in this repo:
- `backend`: intent router + policy + confirmation + audit + orchestration state machine.
- `desktop/agent-cloud`: execution harness runtime (already present), reduced to MVP-safe tooling.
- `app`: confirmation UX and action status streaming events.

## 7) Implementation Plan

### Phase 0 (2-3 days): Safety and scope hardening
- Add MVP mode flag and central policy config.
- Restrict VM allowed tools in `desktop/agent-cloud/agent.mjs` to minimal set for your 20 use cases.
- Remove default over-permissive runtime behavior (`bypassPermissions` for broad actions).
- Add allowlist enforcement to `/v1/agent/execute-tool` (deny by default).
- Add explicit action confirmation protocol (`proposed_action` -> `confirm_action` -> `execute_action`).

Exit criteria:
- No side-effect tool runs without confirmation.
- No unmanaged dynamic app tool can execute in MVP mode.

### Phase 1 (3-5 days): Path unification for glasses flow
- Route single-tap voice command path through the same assist/act intent router as chat.
- Build `capture_context` envelope from transcripts + photo descriptions.
- Ensure both simple ask and action ask consume the same context contract.
- Add streaming action events (`plan`, `awaiting_confirmation`, `executing`, `done`, `failed`).

Exit criteria:
- Same user intent behaves consistently whether triggered from chat or button voice flow.

### Phase 2 (5-7 days): MVP action packs for your 20 use cases
Create bounded packs instead of open-ended autonomy.
- `Pack A`: calendar/email/task operations (use cases 1, 4, 12, 13)
- `Pack B`: multimodal guidance (2, 6, 7, 10, 11, 15, 16, 18, 19)
- `Pack C`: commerce/travel/admin adapters with controlled fallbacks (3, 8, 9, 14, 17, 20)

For each pack define:
- Allowed tools
- Confirmation requirements
- Output schema
- Failure behavior and fallback response
- Verification step per side-effect action (prove action took effect)

### Phase 3 (2-4 days): Pre-hardware readiness tests
- Add integration tests for `agent-proxy`, `agent_tools`, and intent router.
- Add deterministic replay tests with stored audio/photo fixtures.
- Add policy tests: deny-by-default for tools outside MVP packs.

### Phase 4 (Day 0 with glasses): hardware validation protocol
- 20 scripted scenario runs (1 per use case).
- Capture latency, false action rate, completion rate.
- Fix top 3 failure modes before broader field testing.

## 8) Pre-Glasses Test Checklist
1. Simulate hearing path with `/v2/voice-messages` and live `/v4/listen` audio stream.
2. Simulate sight path by injecting `image_chunk` payloads.
3. Run intent classification regression set across all 20 use-case prompts (`assist` vs `act`).
4. Verify confirmation appears for all side-effecting actions.
5. Verify denied tools return safe explanatory message.
6. Verify action audit logs contain full trace IDs and outputs.
7. Verify every completed action has a verification artifact (API response/read-back).

## 9) Harness Decision: OpenClaw-Style Only
Recommendation: implement MVP directly on the existing `agent-proxy` + `desktop/agent-cloud` stack, but enforce OpenClaw-style orchestration discipline in backend policy/state machine.

Concrete MVP operating mode:
- `Assist Mode`: stays on existing backend chat path for low-latency direct answers.
- `Act Mode`: routes to harness path, with mandatory plan + policy + confirmation + verification.
- Tooling: strictly allowlisted by use-case pack; dynamic app tools disabled in MVP mode.
- Runtime: one active harness session per user with explicit action state transitions.

## 10) Immediate 72-Hour Action List
1. Implement `assist|act` intent router and route all entry points through it.
2. Implement server-side `plan -> policy -> confirm -> execute -> verify` state machine.
3. Disable dynamic app tools and permissive runtime defaults in MVP mode.
4. Add targeted tests for `agent-proxy`, `agent_tools`, and action state machine.
5. Produce a 20-scenario acceptance test sheet aligned exactly to your Obsidian use-case table.

## 11) Success Criteria for MVP
- Zero unconfirmed side-effect executions.
- >= 90% successful completion on scripted action scenarios.
- <= 3s first response token for assist mode median.
- Full audit trail for every action-mode request.
- All 20 use cases map to an explicit support status: supported now, fallback, or intentionally deferred (none silent/implicit).
