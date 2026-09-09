from django.contrib.auth import get_user_model
from django.db import IntegrityError, transaction
from django.test import TestCase
from rest_framework import status
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from apps.accounts.models import UserProfile

from .models import Classroom, Student


class ClassroomModelTests(TestCase):
    def setUp(self):
        user_model = get_user_model()
        self.teacher = UserProfile.objects.create(
            user=user_model.objects.create_user(username="teacher-one", password="test-only-password"),
            role=UserProfile.Role.TEACHER,
        )
        self.other_teacher = UserProfile.objects.create(
            user=user_model.objects.create_user(username="teacher-two", password="test-only-password"),
            role=UserProfile.Role.TEACHER,
        )

    def test_each_teacher_only_reaches_their_classrooms(self):
        own_classroom = Classroom.objects.create(
            teacher=self.teacher,
            name="سادس أ",
            grade="الصف السادس",
            subject="الرياضيات",
            academic_year="1448",
        )
        Classroom.objects.create(
            teacher=self.other_teacher,
            name="سادس ب",
            grade="الصف السادس",
            subject="الرياضيات",
            academic_year="1448",
        )

        visible = Classroom.objects.filter(teacher=self.teacher)

        self.assertQuerySetEqual(visible, [own_classroom])

    def test_student_code_is_unique_inside_the_same_classroom(self):
        classroom = Classroom.objects.create(
            teacher=self.teacher,
            name="سادس أ",
            grade="الصف السادس",
            subject="الرياضيات",
            academic_year="1448",
        )
        Student.objects.create(classroom=classroom, internal_code="S-001")

        with self.assertRaises(IntegrityError), transaction.atomic():
            Student.objects.create(classroom=classroom, internal_code="S-001")

    def test_student_name_is_optional(self):
        classroom = Classroom.objects.create(
            teacher=self.teacher,
            name="سادس أ",
            grade="الصف السادس",
            subject="الرياضيات",
            academic_year="1448",
        )
        student = Student.objects.create(classroom=classroom, internal_code="S-014")

        self.assertEqual(str(student), "S-014")


class ClassroomApiTests(APITestCase):
    def setUp(self):
        user_model = get_user_model()
        manager_user = user_model.objects.create_user(username="manager", password="strong-pass-123")
        self.manager = UserProfile.objects.create(user=manager_user, role=UserProfile.Role.MANAGER)
        teacher_user = user_model.objects.create_user(username="teacher", password="strong-pass-123")
        self.teacher = UserProfile.objects.create(user=teacher_user, role=UserProfile.Role.TEACHER)

    def authenticate(self, profile):
        token = Token.objects.create(user=profile.user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")

    def classroom_payload(self):
        return {
            "name": "سادس أ",
            "grade": "الصف السادس",
            "subject": "الرياضيات",
            "academic_year": "1448",
            "teacher_profile_id": str(self.teacher.id),
        }

    def test_manager_creates_classroom_and_assigns_teacher(self):
        self.authenticate(self.manager)
        response = self.client.post("/api/v1/management/classrooms/", self.classroom_payload(), format="json")

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        classroom = Classroom.objects.get()
        self.assertEqual(classroom.teacher, self.teacher)
        self.assertEqual(response.data["teacher_name"], "teacher")

    def test_classroom_reports_the_teachers_real_name(self):
        self.teacher.user.first_name = "أحمد"
        self.teacher.user.last_name = "الغامدي"
        self.teacher.user.save(update_fields=["first_name", "last_name"])
        self.authenticate(self.manager)
        response = self.client.post(
            "/api/v1/management/classrooms/", self.classroom_payload(), format="json"
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data["teacher_name"], "أحمد الغامدي")

    def test_teacher_cannot_create_classroom(self):
        self.authenticate(self.teacher)
        response = self.client.post("/api/v1/management/classrooms/", self.classroom_payload(), format="json")

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertFalse(Classroom.objects.exists())

    def test_manager_adds_student_to_classroom(self):
        self.authenticate(self.manager)
        classroom = Classroom.objects.create(
            teacher=self.teacher,
            name="سادس أ",
            grade="الصف السادس",
            subject="الرياضيات",
            academic_year="1448",
        )
        response = self.client.post(
            f"/api/v1/management/classrooms/{classroom.id}/students/",
            {"internal_code": "S-001", "display_name": "طالب تجريبي"},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(classroom.students.get().internal_code, "S-001")

    def test_duplicate_student_code_returns_validation_error(self):
        self.authenticate(self.manager)
        classroom = Classroom.objects.create(
            teacher=self.teacher,
            name="سادس أ",
            grade="الصف السادس",
            subject="الرياضيات",
            academic_year="1448",
        )
        Student.objects.create(classroom=classroom, internal_code="S-001")
        response = self.client.post(
            f"/api/v1/management/classrooms/{classroom.id}/students/",
            {"internal_code": "S-001"},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)


class TeacherClassroomAccessTests(APITestCase):
    """A teacher reads their own classrooms and nothing else."""

    def setUp(self):
        user_model = get_user_model()
        self.manager = UserProfile.objects.create(
            user=user_model.objects.create_user(username="manager", password="strong-pass-123"),
            role=UserProfile.Role.MANAGER,
        )
        self.teacher_a = UserProfile.objects.create(
            user=user_model.objects.create_user(username="teacher-a", password="strong-pass-123"),
            role=UserProfile.Role.TEACHER,
        )
        self.teacher_b = UserProfile.objects.create(
            user=user_model.objects.create_user(username="teacher-b", password="strong-pass-123"),
            role=UserProfile.Role.TEACHER,
        )
        self.class_6a = self.make_classroom(self.teacher_a, "سادس أ")
        self.class_6b = self.make_classroom(self.teacher_a, "سادس ب")
        self.class_5a = self.make_classroom(self.teacher_b, "خامس أ")
        self.student_6a = Student.objects.create(
            classroom=self.class_6a, internal_code="S-001", display_name="طالب أ"
        )
        Student.objects.create(classroom=self.class_5a, internal_code="S-900")

    def make_classroom(self, teacher, name):
        return Classroom.objects.create(
            teacher=teacher,
            name=name,
            grade="الصف السادس",
            subject="الرياضيات",
            academic_year="1448",
        )

    def authenticate(self, profile):
        token = Token.objects.create(user=profile.user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")

    def students_url(self, classroom):
        return f"/api/v1/management/classrooms/{classroom.id}/students/"

    def test_manager_sees_all_classrooms(self):
        self.authenticate(self.manager)
        response = self.client.get("/api/v1/management/classrooms/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(
            {item["name"] for item in response.data},
            {"سادس أ", "سادس ب", "خامس أ"},
        )

    def test_teacher_sees_only_assigned_classrooms(self):
        self.authenticate(self.teacher_a)
        response = self.client.get("/api/v1/management/classrooms/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual({item["name"] for item in response.data}, {"سادس أ", "سادس ب"})

    def test_classroom_list_reports_student_counts(self):
        self.authenticate(self.teacher_a)
        response = self.client.get("/api/v1/management/classrooms/")

        counts = {item["name"]: item["students_count"] for item in response.data}
        self.assertEqual(counts, {"سادس أ": 1, "سادس ب": 0})

    def test_teacher_cannot_reach_another_teachers_classroom(self):
        self.authenticate(self.teacher_a)
        response = self.client.get(self.students_url(self.class_5a))

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_teacher_reads_students_in_their_classroom(self):
        self.authenticate(self.teacher_a)
        response = self.client.get(self.students_url(self.class_6a))

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data), 1)
        self.assertEqual(response.data[0]["internal_code"], "S-001")
        self.assertEqual(response.data[0]["display_name"], "طالب أ")

    def test_teacher_cannot_read_students_of_another_teacher(self):
        self.authenticate(self.teacher_a)
        response = self.client.get(self.students_url(self.class_5a))

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertNotContains(response, "S-900", status_code=status.HTTP_404_NOT_FOUND)

    def test_teacher_cannot_create_a_classroom(self):
        self.authenticate(self.teacher_a)
        response = self.client.post(
            "/api/v1/management/classrooms/",
            {
                "name": "صف جديد",
                "grade": "الصف السادس",
                "subject": "الرياضيات",
                "academic_year": "1448",
                "teacher_profile_id": str(self.teacher_a.id),
            },
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertFalse(Classroom.objects.filter(name="صف جديد").exists())

    def test_teacher_cannot_add_a_student_to_their_own_classroom(self):
        self.authenticate(self.teacher_a)
        response = self.client.post(
            self.students_url(self.class_6a),
            {"internal_code": "S-002"},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertFalse(Student.objects.filter(internal_code="S-002").exists())

    def test_teacher_cannot_add_a_student_to_another_teachers_classroom(self):
        self.authenticate(self.teacher_a)
        response = self.client.post(
            self.students_url(self.class_5a),
            {"internal_code": "S-003"},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertFalse(Student.objects.filter(internal_code="S-003").exists())

    def test_deactivated_teacher_is_rejected(self):
        self.teacher_a.is_active = False
        self.teacher_a.save(update_fields=["is_active"])
        self.authenticate(self.teacher_a)
        response = self.client.get("/api/v1/management/classrooms/")

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_anonymous_caller_is_rejected(self):
        response = self.client.get("/api/v1/management/classrooms/")

        self.assertIn(
            response.status_code,
            (status.HTTP_401_UNAUTHORIZED, status.HTTP_403_FORBIDDEN),
        )
