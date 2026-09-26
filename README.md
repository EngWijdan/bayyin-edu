# بيّن — Bayyin MVP v1.0.0

Bayyin helps a school manager and teachers turn paper assessments into class insights and remediation plans. Teachers review OCR, confirm answers, then the server evaluates with Gemini.

## MVP Features

- Manager and Teacher roles
- Classrooms and students
- Assessments and questions
- Student submissions
- Attachments (JPG / PNG / PDF, 10 MB)
- OCR (Tesseract, Arabic + English)
- Teacher OCR review and confirm
- AI evaluation (Gemini)
- Student results and gaps
- Class insights and grouping (Foundation / Practice / Ready)
- AI remediation plans
- Manager school insights
- Arabic and English (RTL / LTR)

## Tech stack

- Flutter
- Django / Django REST Framework
- PostgreSQL
- Docker Compose
- Tesseract OCR + Poppler
- Gemini
- Redis / Celery worker process (reserved; OCR and evaluation are synchronous in this MVP)

## Local setup

Requires Flutter, Docker Desktop (or Compose), and a copy of this repo.

```bash
cp .env.example .env
docker compose up -d --build
```

Wait until the API is healthy:

```text
http://localhost:8000/api/v1/health/
```

Expected:

```json
{"status":"ok","service":"bayyin-api","database":"connected"}
```

Create the first school manager (once):

```bash
docker compose exec api python manage.py bootstrap_manager --username manager
```

Run the Flutter app:

```bash
flutter run
```

Migrations run automatically when the API container starts (`python manage.py migrate`). Media files persist in the `bayyin_media` Docker volume.

## Environment

See `.env.example`. Required names:

- `DJANGO_SECRET_KEY`, `DJANGO_DEBUG`, `DJANGO_ALLOWED_HOSTS`
- `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD` (and host/port if not using Compose)
- `GEMINI_API_KEY` (optional for UI-only work; required for evaluation and remediation)
- `GEMINI_MODEL`, `GEMINI_TIMEOUT_MS`
- `REDIS_URL`

Do not commit `.env`. Attachment files are not served as public `MEDIA_URL`.

## Tests

```bash
flutter analyze
flutter test
flutter build bundle

docker compose exec api python manage.py test
docker compose exec api python manage.py makemigrations --check
docker compose exec api python manage.py check
```

## Architecture

Paper → OCR → Teacher review → Evaluation → Insights → Remediation

The Flutter app never holds the Gemini key. Results, class insights, and manager insights are computed from current evaluation rows; they are not stored snapshots.
