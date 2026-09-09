# بيّن - Bayyin

تطبيق Flutter عربي يساعد المعلم على تحليل أعمال الطلاب، مراجعة الأدلة، وتكوين مجموعات وخطط علاجية.

## تشغيل تطبيق Flutter

```bash
flutter run
```

## تشغيل الخادم محليًا

يتطلب Docker Desktop أو بديلًا متوافقًا مع Docker Compose.

```bash
cp .env.example .env
docker compose up --build
```

بعد اكتمال التشغيل، افتح:

```text
http://localhost:8000/api/v1/health/
```

الاستجابة المتوقعة:

```json
{"status":"ok","service":"bayyin-api","database":"connected"}
```

## إنشاء مدير المدرسة الأول

هذه خطوة تأسيسية تنفذ مرة واحدة، وبعدها يضيف المدير المعلمين من تطبيق Flutter:

```bash
docker compose exec api python manage.py bootstrap_manager --username manager
```

واجهات الحسابات الحالية:

- `POST /api/v1/auth/login/`
- `GET /api/v1/auth/me/`
- `POST /api/v1/auth/logout/`
- `GET|POST /api/v1/management/teachers/` للمدير فقط

لإيقاف الخدمات دون حذف البيانات:

```bash
docker compose down
```

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
