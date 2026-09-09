from django.contrib.auth import get_user_model
from rest_framework import status
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from .models import UserProfile


class AccountApiTests(APITestCase):
    def setUp(self):
        user_model = get_user_model()
        self.manager = user_model.objects.create_user(username="manager", password="strong-pass-123")
        UserProfile.objects.create(user=self.manager, role=UserProfile.Role.MANAGER)
        self.teacher = user_model.objects.create_user(username="teacher", password="strong-pass-123")
        UserProfile.objects.create(user=self.teacher, role=UserProfile.Role.TEACHER)

    def authenticate(self, user):
        token = Token.objects.create(user=user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")

    def test_login_returns_role(self):
        response = self.client.post(
            "/api/v1/auth/login/",
            {"username": "manager", "password": "strong-pass-123"},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data["token"])
        self.assertEqual(response.data["user"]["role"], UserProfile.Role.MANAGER)

    def test_manager_creates_teacher(self):
        self.authenticate(self.manager)
        response = self.client.post(
            "/api/v1/management/teachers/",
            {
                "username": "new-teacher",
                "password": "strong-pass-456",
                "first_name": "نورة",
                "last_name": "محمد",
                "email": "nora@example.com",
            },
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        profile = UserProfile.objects.get(user__username="new-teacher")
        self.assertEqual(profile.role, UserProfile.Role.TEACHER)

    def test_teacher_cannot_create_another_teacher(self):
        self.authenticate(self.teacher)
        response = self.client.post(
            "/api/v1/management/teachers/",
            {"username": "forbidden", "password": "strong-pass-456"},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertFalse(get_user_model().objects.filter(username="forbidden").exists())

    def test_login_returns_the_real_name_of_the_signed_in_teacher(self):
        self.teacher.first_name = "أحمد"
        self.teacher.last_name = "الغامدي"
        self.teacher.save(update_fields=["first_name", "last_name"])

        response = self.client.post(
            "/api/v1/auth/login/",
            {"username": "teacher", "password": "strong-pass-123"},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["user"]["full_name"], "أحمد الغامدي")
        self.assertEqual(response.data["user"]["display_name"], "أحمد الغامدي")
        self.assertNotEqual(response.data["user"]["display_name"], "teacher")

    def test_login_falls_back_to_username_when_no_name_is_stored(self):
        response = self.client.post(
            "/api/v1/auth/login/",
            {"username": "teacher", "password": "strong-pass-123"},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["user"]["full_name"], "")
        self.assertEqual(response.data["user"]["display_name"], "teacher")

    def test_display_name_uses_first_name_only_when_there_is_no_last_name(self):
        self.teacher.first_name = "أحمد"
        self.teacher.save(update_fields=["first_name"])

        self.assertEqual(self.teacher.profile.display_name, "أحمد")

    def test_teacher_list_exposes_display_name(self):
        self.teacher.first_name = "أحمد"
        self.teacher.last_name = "الغامدي"
        self.teacher.save(update_fields=["first_name", "last_name"])
        self.authenticate(self.manager)
        response = self.client.get("/api/v1/management/teachers/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        entry = next(item for item in response.data if item["username"] == "teacher")
        self.assertEqual(entry["display_name"], "أحمد الغامدي")

    def test_manager_lists_all_teachers_in_the_system(self):
        self.authenticate(self.manager)
        response = self.client.get("/api/v1/management/teachers/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        usernames = {item["username"] for item in response.data}
        self.assertEqual(usernames, {"teacher"})
