from django.test import TestCase
from django.urls import reverse


class HealthApiTests(TestCase):
    def test_health_reports_service_and_database(self):
        response = self.client.get(reverse("health"))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["status"], "ok")
        self.assertEqual(response.json()["service"], "bayyin-api")
        self.assertEqual(response.json()["database"], "connected")


class CorsTests(TestCase):
    def test_login_preflight_allows_flutter_web_origin(self):
        origin = "http://localhost:55555"
        response = self.client.options(
            "/api/v1/auth/login/",
            HTTP_ORIGIN=origin,
            HTTP_ACCESS_CONTROL_REQUEST_METHOD="POST",
            HTTP_ACCESS_CONTROL_REQUEST_HEADERS="content-type,authorization",
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response["Access-Control-Allow-Origin"], origin)
        self.assertIn("POST", response["Access-Control-Allow-Methods"])
