# Working agreement

The APK is live and in use. Every change must keep existing installed clients working.

## Compatibility rules

- Backend-first: implement fixes in `backend/` whenever possible; make frontend changes only when necessary and batch them for the next APK.
- Backend changes must be backward compatible with payloads the live APK already sends:
  - add routes/fields; never make new request fields required
  - never tighten validation on existing payloads
  - keep old response fields and formats
- Do not break existing Firestore documents or require migrations. New fields must be optional with safe defaults.
- New authorization checks must allow legacy/ambiguous data through (only enforce when the data needed for the check is actually present).
- Permissions are additive; do not remove or rename existing permissions.
- Never commit or push unless explicitly asked.

## Verify before reporting

- Backend syntax: `node --check <file>` from `backend/`.
- Backend tests: `& '.\node_modules\.bin\vitest.cmd' run tests/<file>` from `backend/` (`npx` is broken).
- Flutter analyze: `& 'D:\flutter\bin\flutter.bat' analyze <paths>` from `app/`.
- APK (only when frontend changed): `& 'D:\flutter\bin\flutter.bat' build apk --release` from `app/`.
- Some legacy tests already fail (stale permission matrices/fields); do not treat them as regressions.
