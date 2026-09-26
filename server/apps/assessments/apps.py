import logging

from django.apps import AppConfig


class AssessmentsConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "apps.assessments"
    verbose_name = "الاختبارات"

    def ready(self):
        from django.conf import settings

        if not str(getattr(settings, "GEMINI_API_KEY", "") or "").strip():
            logging.getLogger(__name__).warning(
                "GEMINI_API_KEY is missing; evaluation will return a safe error"
            )
