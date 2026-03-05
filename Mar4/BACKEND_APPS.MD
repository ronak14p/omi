# BACKEND_APPS

Date: 2026-03-04  
Repo: `/Users/ronak/Developer/omi`  
Purpose: explain how backend services and API paths currently work so Findings 1, 2, and 3 in `INITIAL_TRANSFORMATION.MD` are easier to reason about.

## 1) What I Reviewed

### Documentation reviewed
- `docs/doc/developer/backend/backend_deepdive.mdx`
- `docs/doc/developer/backend/transcription.mdx`
- `docs/doc/developer/backend/chat_system.mdx`
- `docs/doc/developer/backend/StoringConversations.mdx`
- `docs/doc/developer/backend/Backend_Setup.mdx`
- `docs/doc/developer/MCP.mdx`
- `docs/doc/developer/api/{overview,conversations,memories,action-items,keys}.mdx`
- `docs/doc/developer/apps/{Introduction,Integrations}.mdx`
- `backend/INDEX.md`
- `backend/README.md`
- `AGENTS.md`
- `CLAUDE.md`

### Important doc reliability notes
- `docs/api-reference/openapi.json` is a placeholder "Plant Store" spec, not Omi backend; do not use it as truth.
- Backend deep-dive docs are directionally useful, but incomplete versus current router surface.
- Service map docs have some drift (for example around `agent-proxy` coverage across docs).

### Code reviewed for source-of-truth behavior
- `backend/main.py` (router wiring)
- `backend/routers/*.py` (all route definitions)
- `backend/utils/conversations/process_conversation.py`
- `backend/utils/app_integrations.py`
- `backend/utils/webhooks.py`
- `backend/utils/stt/{streaming.py,vad.py,speaker_embedding.py,speech_profile.py}`
- `backend/pusher/main.py`
- `backend/diarizer/main.py`
- `backend/modal/main.py`
- `backend/agent-proxy/main.py`
- Flutter integration points:
  - `app/lib/backend/http/api/*.dart`
  - `app/lib/env/env.dart`
  - `app/lib/providers/message_provider.dart`
  - `app/lib/pages/home/page.dart`
  - `app/lib/services/agent_chat_service.dart`
  - `app/lib/main.dart`

## 2) Runtime Topology (Current)

### Main backend process
- Entry: `backend/main.py`
- Framework: FastAPI (+ Modal wrapper in same file)
- Includes 36 router modules into one API app.

### Side services used by backend flow
- `backend/pusher/main.py`
  - WebSocket: `/v1/trigger/listen`
  - Used by transcribe flow when `HOSTED_PUSHER_API_URL` is set.
- `backend/diarizer/main.py`
  - HTTP: `/v1/diarization`, `/v1/embedding`, `/v2/embedding`
- `backend/modal/main.py` (VAD + speaker-id service)
  - HTTP: `/v1/vad`, `/v1/speaker-identification`
- `backend/agent-proxy/main.py`
  - WebSocket bridge: `/v1/agent/ws`
  - Authenticates Firebase token, looks up user VM, proxies app <-> VM.

### Shared dependencies
- Firestore (conversations/memories/users/tasks/etc.)
- Redis (session/cache/feature flags/rate limits)
- Pinecone (conversation vectors + semantic retrieval)
- GCS buckets (audio/photos/speech profiles)
- STT vendors (Deepgram primary, Soniox/Speechmatics fallback logic)

## 3) API Surface Snapshot (from router code)

Generated from AST parsing of `backend/routers/*.py` on 2026-03-04.

- Total routes: `335`
- Includes HTTP + WebSocket routes.

### Largest path families

| Path family | Route count | Primary purpose |
|---|---:|---|
| `/v1/users` | 49 | user profile/settings/people/migration/usage/daily summaries |
| `/v1/apps` | 33 | app-store style CRUD, install/enable/reviews/keys |
| `/v1/conversations` | 27 | conversation lifecycle and edits |
| `/v1/dev` | 26 | developer API for memories/action-items/conversations/goals |
| `/v1/mcp` | 13 | MCP key + data API |
| `/v1/task-integrations` | 12 | task provider oauth + tasks |
| `/v2/integrations` | 12 | external app integration API |
| `/v1/action-items` | 11 | task CRUD/share/batch |
| `/v1/goals` | 11 | goal CRUD/progress/advice |
| `/v1/announcements` | 10 | announcement/changelog lifecycle |

### Largest router files

| Router file | Routes |
|---|---:|
| `backend/routers/apps.py` | 59 |
| `backend/routers/users.py` | 49 |
| `backend/routers/developer.py` | 26 |
| `backend/routers/conversations.py` | 25 |
| `backend/routers/payment.py` | 21 |
| `backend/routers/task_integrations.py` | 16 |

## 4) How Core Backend Flows Actually Work

### A) Live capture and transcription flow
- Entry: WebSocket `backend/routers/transcribe.py`
  - `/v4/listen` (mobile/device)
  - `/v4/web/listen` (web first-message auth)
- Key behavior:
  - Validates user.
  - Creates and updates an `in_progress` conversation in Firestore.
  - Decodes codec (`pcm8/pcm16/opus/aac/lc3`) and selects STT provider via `utils/stt/streaming.py`.
  - Streams transcript segments back to app.
  - On timeout/manual trigger, processes conversation.
  - If pusher is enabled: offloads transcript/audio-byte integrations to pusher WS protocol.
  - If pusher is disabled: falls back to local processing and direct realtime integration triggers.

### B) Conversation processing flow
- Trigger points:
  - `POST /v1/conversations`
  - timeout path inside transcribe flow
  - integration/workflow import paths
- Processor: `utils/conversations/process_conversation.py`
- Key steps:
  - Discard check.
  - Structured extraction (title/overview/category/action items/events).
  - Folder assignment.
  - App summarization trigger.
  - Async side-effects in threads:
    - vector save to Pinecone
    - memories extraction
    - trends extraction
    - action item write + optional task sync
    - goal progress update
    - conversation-created webhooks
  - Marks conversation completed and upserts to Firestore.

### C) Chat / assistant response flow
- Primary route: `POST /v2/messages` (`backend/routers/chat.py`)
- Streams SSE output to client.
- Calls `execute_graph_chat_stream` in `utils/retrieval/graph.py`, which routes among:
  - no-context direct response
  - context-dependent agentic response
  - persona response
- Voice chat endpoints:
  - `POST /v2/voice-messages`
  - `POST /v2/voice-message/transcribe`

### D) Agent VM harness flow
- App WS target: `wss://<agent-host>/v1/agent/ws`
  - derived in `app/lib/env/env.dart` from API host (`api.*` -> `agent.*`)
- Lifecycle APIs in main backend:
  - `GET /v1/agent/vm-status`
  - `POST /v1/agent/vm-ensure`
  - `POST /v1/agent/keepalive`
- Tool APIs in main backend:
  - `GET /v1/agent/tools`
  - `POST /v1/agent/execute-tool`
- Proxy layer:
  - `backend/agent-proxy/main.py` authenticates, ensures VM health, then bidirectional WS proxy to VM service.

### E) App-store and external integration flow
- App platform surface (large):
  - `/v1/apps*`, `/v2/apps*`, `/v1/personas*`, `/v1/app/*`, `/v1/payment*` etc.
- External integration APIs:
  - `/v2/integrations/{app_id}/user/conversations`
  - `/v2/integrations/{app_id}/user/memories`
  - `/v2/integrations/{app_id}/conversations`
  - `/v2/integrations/{app_id}/memories`
  - `/v2/integrations/{app_id}/tasks`
  - `/v2/integrations/{app_id}/notification`
- User webhook features also exist (`memory_created`, realtime transcript, audio bytes).

### F) MCP flow
- REST-style MCP API: `backend/routers/mcp.py` (`/v1/mcp/*`)
- Streamable HTTP transport: `backend/routers/mcp_sse.py` (`/v1/mcp/sse`)
- Compatibility OAuth endpoints in same router also expose unprefixed:
  - `GET /authorize`
  - `POST /token`

## 5) Mapping to Findings 1, 2, 3

This section maps directly to `INITIAL_TRANSFORMATION.MD` Findings 1-3.

### Finding 1: action path split/inconsistent

Why this happens in current architecture:
- There are two distinct action-capable paths:
  - chat/voice-message path through `POST /v2/messages` and graph agentic tools.
  - VM harness path through `/v1/agent/ws` + `/v1/agent/execute-tool`.
- Glasses voice capture path uses transcribe + voice message/chat endpoints, while agent VM path is separately gated by `claudeAgentEnabled`.
- Net effect: same user intent can route through different engines with different tools and safety semantics.

Backend/API evidence:
- `backend/routers/chat.py` (`/v2/messages`, `/v2/voice-messages`)
- `backend/routers/agent_tools.py` (`/v1/agent/*`)
- `backend/agent-proxy/main.py` (`/v1/agent/ws`)

### Finding 2: VM runtime over-permissive

Why this happens in current architecture:
- Backend endpoint `POST /v1/agent/execute-tool` is generic and can execute any tool in loaded set.
- Loaded set is `CORE_TOOLS` plus dynamic app tools (`load_app_tools(uid)`), increasing scope unpredictably.
- VM proxy and VM lifecycle are optimized for availability, not policy minimization.

Backend/API evidence:
- `backend/routers/agent_tools.py` lines around tool list/execute.
- `backend/utils/retrieval/agentic.py` dynamic tool loading.
- `backend/utils/retrieval/tools/app_tools.py` manifest-driven external tools.

### Finding 3: no mandatory confirmation gate for side-effecting tools

Why this happens in current architecture:
- There is no dedicated API state machine for `propose -> confirm -> execute`.
- `POST /v1/agent/execute-tool` executes immediately.
- Agentic tool chains include mutating operations (for example calendar CRUD), but API layer does not enforce explicit confirmation.

Backend/API evidence:
- `backend/routers/agent_tools.py` execute endpoint.
- Mutating tool modules in `backend/utils/retrieval/tools/*` (for example calendar create/update/delete).

## 6) MVP Relevance (OpenClaw-style harness direction)

For your harness-first MVP, the backend can be treated in two buckets:

### Keep for MVP core
- Capture + transcript ingestion:
  - `/v4/listen`, `/v4/web/listen`
- Conversation finalize + retrieval:
  - `/v1/conversations` (+ minimal read endpoints)
- Assistant responses:
  - `/v2/messages` and optionally `/v2/voice-messages`
- Harness control plane:
  - `/v1/agent/vm-status`
  - `/v1/agent/vm-ensure`
  - `/v1/agent/keepalive`
  - `/v1/agent/tools`
  - `/v1/agent/execute-tool`
  - `agent-proxy` `/v1/agent/ws`

### De-prioritize for MVP
- Most `/v1/apps*`, `/v2/apps*`, personas, reviews, tester flows
- Most payments/subscription routes
- Broad third-party integration route families not used by your 20 use cases
- MCP endpoints if not needed in MVP tests

## 7) Notable Drift / Inconsistency Found

- OpenAPI file is non-Omi placeholder (`docs/api-reference/openapi.json`).
- App API client and backend route mismatch:
  - app calls `v1/apps/proactive-notification-scopes`
  - backend route is `v1/app/proactive-notification-scopes`
- VM lifecycle logic exists in both:
  - `backend/agent-proxy/main.py`
  - `backend/routers/agent_tools.py`
  This duplicates status/restart behavior and increases drift risk.

## 8) Route Inventory Repro Command

Use this to regenerate route inventory from source code:

```bash
python3 - <<'PY'
import ast
from pathlib import Path
from collections import Counter
rows=[]
for f in sorted(Path("backend/routers").glob("*.py")):
    t=ast.parse(f.read_text())
    prefix=""
    for n in t.body:
        if isinstance(n, ast.Assign) and any(isinstance(x, ast.Name) and x.id=="router" for x in n.targets):
            if isinstance(n.value, ast.Call):
                for kw in n.value.keywords:
                    if kw.arg=="prefix" and isinstance(kw.value, ast.Constant) and isinstance(kw.value.value, str):
                        prefix=kw.value.value
    for n in ast.walk(t):
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)):
            for d in n.decorator_list:
                if isinstance(d, ast.Call) and isinstance(d.func, ast.Attribute) and isinstance(d.func.value, ast.Name) and d.func.value.id=="router":
                    m=d.func.attr.upper()
                    if m not in {"GET","POST","PUT","PATCH","DELETE","WEBSOCKET"}:
                        continue
                    if d.args and isinstance(d.args[0], ast.Constant) and isinstance(d.args[0].value, str):
                        p=d.args[0].value
                        full=prefix.rstrip("/") + (p if p.startswith("/") else "/" + p) if prefix else p
                        rows.append((f.name, m, full))
print("Total routes:", len(rows))
for r in rows[:20]:
    print(r)
PY
```

