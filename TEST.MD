# Test Log

Date: 2026-03-05
Repo: `/Users/ronak/Developer/omi`

## Tooling Installed

- Backend venv: `backend/.venv`
  - `black 26.1.0`
  - `pytest 9.0.2`
  - `pytest-asyncio 1.3.0`
  - `backend/requirements.txt` installed into the same venv
- Flutter SDKs installed locally:
  - `~/.local/share/flutter-sdk/flutter-3.24.1`
  - `~/.local/share/flutter-sdk/flutter-3.41.3`
- Active shell `flutter` / `dart` now point to `3.41.3`
- Web deps installed with `npm ci` in `web/app`

## Validation Run

- `backend/.venv/bin/black --line-length 120 --skip-string-normalization ...`  
  Status: passed
- `dart format --line-length 120 ...`  
  Status: passed
- `backend/test.sh`  
  Status: passed after fixing stale test references, stale test fixtures, and installing `pytest-asyncio`
- `app/test.sh`  
  Status: passed with Flutter `3.41.3`
- `npm exec tsc -- --noEmit -p tsconfig.json` in `web/app`  
  Status: passed
- `npm run lint` in `web/app`  
  Status: failed

## Issues Found

### 1. Stale backend test script after prune

Context:
- `backend/test.sh` still invoked deleted tests:
  - `tests/unit/test_firmware_pagination.py`
  - `tests/unit/test_desktop_updates.py`
  - `tests/unit/test_process_conversation_usage_context.py`
  - `tests/unit/test_mentor_notifications.py`

Resolution:
- Removed those references from `backend/test.sh`.

Recommendation:
- Keep `backend/test.sh` updated whenever tests are deleted in cleanup branches.

### 2. Backend unit-test fixtures drifted behind current imports

Context:
- `backend/tests/unit/test_llm_usage_endpoints.py` stubbed `database.redis_db` and `utils.other.*` incompletely for the current `routers.users` import graph.
- `backend/tests/unit/test_prompt_cache_integration.py` stubbed an older `utils.retrieval.tools` surface and omitted the screen-activity tools.

Resolution:
- Added missing Soniox-related mock symbols in `test_llm_usage_endpoints.py`.
- Updated the prompt-cache integration fixture to match the current MVP tool allowlist and tool names.

Recommendation:
- When tool imports change in `backend/utils/retrieval/agentic.py`, update the integration-test stub in the same change.

### 3. Backend async tests required an undeclared pytest plugin

Context:
- `tests/unit/test_pusher_heartbeat.py` uses `@pytest.mark.asyncio`.
- Plain `pytest` failed with:
  - `async def functions are not natively supported`
  - `PytestUnknownMarkWarning: Unknown pytest.mark.asyncio`

Resolution:
- Installed `pytest-asyncio` into `backend/.venv`.

Recommendation:
- Add `pytest-asyncio` to the repo’s documented dev bootstrap path or a dedicated dev requirements file.

Reference:
- [pytest-asyncio docs](https://pytest-asyncio.readthedocs.io/)

### 4. App Flutter pin was stale

Context:
- Checked-in `app/.fvmrc` pointed to `3.24.1`.
- `app/test.sh` failed immediately on that SDK because `flutter_test` pinned `vector_math 2.1.4` while the repo depends on `vector_math ^2.2.0`.
- The failing message referenced SDK version pinning behavior directly.

Resolution:
- Installed Flutter `3.41.3`.
- Updated `app/.fvmrc` to `3.41.3`.
- Re-ran `app/test.sh` successfully on `3.41.3`.

Recommendation:
- Keep CI/local setup aligned with `app/.fvmrc`.

Reference:
- [Dart SDK version pinning](https://dart.dev/go/sdk-version-pinning)

### 5. App compile fallout from the cleanup pass

Context:
- The first app test run exposed compile errors caused by leftover/de-scoped surfaces:
  - orphaned `app.dart` export in `app/lib/backend/schema/schema.dart`
  - dead `getConversationSuggestedApps()` API using removed `App` schema
  - missing analytics compatibility methods/keys
  - missing users API import in `conversation_detail_provider.dart`
  - stale l10n key usage in `settings_drawer.dart`
  - `GetAppsWidgets` referenced `provider` from outside the `Consumer` builder scope

Resolution:
- Removed the dead schema export and dead conversation API helper.
- Added minimal compatibility getters/methods/imports needed for the current compile path.
- Switched settings labels to existing l10n keys.
- Fixed the `Consumer` builder scope bug.

Recommendation:
- After large surface-area removals, run at least one full `flutter test` pass before treating the app cleanup as done.

### 6. Web lint configuration is currently broken

Context:
- `npm run lint` runs `next lint`.
- With the installed `next@16`, that command failed as:
  - `Invalid project directory provided, no such directory: /Users/ronak/Developer/omi/web/app/lint`
- Direct `eslint` execution also failed because there is no `eslint.config.js`, and ESLint 9 now expects flat config by default.

Status:
- Unresolved.

Recommendation:
- Migrate the web app to ESLint 9 flat config and replace the lint script with a config-aware command.

References:
- [ESLint flat config migration guide](https://eslint.org/docs/latest/use/configure/migration-guide)
- [Next.js docs](https://nextjs.org/docs)

## Environment Notes

- `flutter doctor -v` still reports:
  - Android SDK not installed
  - Xcode incomplete
  - CocoaPods missing
- Those did not block the current Flutter unit/widget test targets.

## Net Result

- Backend tests: passing
- App tests: passing
- Web typecheck: passing
- Web lint: still blocked by repo config/tooling mismatch
