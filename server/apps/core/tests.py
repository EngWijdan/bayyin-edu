from django.test import TestCase
from django.urls import reverse


class HealthApiTests(TestCase):
    def test_health_reports_service_and_database(self):
        response = self.client.get(reverse("health"))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["status"], "ok")
        self.assertEqual(response.json()["service"], "bayyin-api")
        self.assertEqual(response.json()["database"], "connected")
