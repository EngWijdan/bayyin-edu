# Bayyin MVP v1.0.0 — Release checklist

Use this before a demo or a staging hand-off. Do not treat a checked box as a substitute for the automated suite.

## Build and config

- [ ] `flutter analyze`
- [ ] `flutter test`
- [ ] `flutter build bundle`
- [ ] `docker compose exec api python manage.py test`
- [ ] `docker compose exec api python manage.py makemigrations --check`
- [ ] `docker compose exec api python manage.py check`
- [ ] `docker compose up -d --build` succeeds
- [ ] `GET /api/v1/health/` returns connected
- [ ] Migrations applied (`start-api.sh` runs `migrate`)
- [ ] `.env` is local only; no secrets in git
- [ ] `GEMINI_API_KEY` set if evaluation/remediation will be shown

## Roles

- [ ] Manager login
- [ ] Teacher login
- [ ] Invalid credentials show a safe message
- [ ] Inactive account cannot sign in
- [ ] Teacher never reaches manager insights or teacher-admin screens
- [ ] Manager stays on the manager dashboard

## Manager flow

- [ ] Add teacher
- [ ] Create classroom and assign teacher
- [ ] Add students
- [ ] School insights shows real counts (no mock data)

## Teacher flow

- [ ] My classes
- [ ] Create assessment and add questions
- [ ] Open student submissions
- [ ] Enter answers
- [ ] Upload attachment (JPG/PNG/PDF ≤ 10 MB)
- [ ] OCR extract and retry on failure
- [ ] OCR answer review and confirm
- [ ] AI evaluation
- [ ] Assessment result
- [ ] Class insights
- [ ] Remediation plan (skip empty groups)

## Safety

- [ ] Assessment with no questions is not a 0% Foundation result
- [ ] Arabic UI (RTL) reviewed
- [ ] English UI (LTR) reviewed; no Arabic leftovers
- [ ] Errors are safe (no stack traces in the UI)
