from decimal import Decimal

from django.contrib.auth import get_user_model
from django.db import IntegrityError, transaction
from django.test import TestCase
from rest_framework import status
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from apps.accounts.models import UserProfile
from apps.classrooms.models import Classroom

from .models import Assessment, Question


def make_classroom(teacher, name, subject="الرياضيات"):
    return Classroom.objects.create(
        teacher=teacher,
        name=name,
        grade="الصف السادس",
        subject=subject,
        academic_year="1448",
    )


class AssessmentModelTests(TestCase):
    def setUp(self):
        user_model = get_user_model()
        self.teacher = UserProfile.objects.create(
            user=user_model.objects.create_user(username="teacher-one", password="test-only-password"),
            role=UserProfile.Role.TEACHER,
        )
        self.assessment = Assessment.objects.create(
            classroom=make_classroom(self.teacher, "سادس أ"),
            title="اختبار الكسور الأول",
            created_by=self.teacher,
        )

    def make_question(self, order, text="ما ناتج 1/2 + 1/4؟"):
        return Question.objects.create(
            assessment=self.assessment,
            order=order,
            text=text,
            max_score=Decimal("2"),
            model_answer="3/4",
        )

    def test_question_order_is_unique_inside_the_same_assessment(self):
        self.make_question(order=1)

        with self.assertRaises(IntegrityError), transaction.atomic():
            self.make_question(order=1, text="سؤال آخر")

    def test_same_order_is_allowed_in_a_different_assessment(self):
        self.make_question(order=1)
        other = Assessment.objects.create(
            classroom=self.assessment.classroom, title="اختبار ثانٍ"
        )

        Question.objects.create(
            assessment=other, order=1, text="سؤال", max_score=Decimal("1"), model_answer="نعم"
        )

        self.assertEqual(other.questions.count(), 1)

    def test_database_rejects_a_non_positive_max_score(self):
        with self.assertRaises(IntegrityError), transaction.atomic():
            Question.objects.create(
                assessment=self.assessment,
                order=1,
                text="سؤال",
                max_score=Decimal("0"),
                model_answer="لا شيء",
            )

    def test_next_order_follows_the_highest_existing_question(self):
        self.assertEqual(self.assessment.next_question_order(), 1)
        self.make_question(order=1)
        self.make_question(order=4, text="سؤال رابع")

        self.assertEqual(self.assessment.next_question_order(), 5)

    def test_questions_are_returned_in_order(self):
        self.make_question(order=3, text="ثالث")
        self.make_question(order=1, text="أول")
        self.make_question(order=2, text="ثانٍ")

        self.assertEqual(
            [question.text for question in self.assessment.questions.all()],
            ["أول", "ثانٍ", "ثالث"],
        )


class AssessmentApiTests(APITestCase):
    """Every teacher stays inside their own classrooms; the manager sees everything."""

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
        self.class_6a = make_classroom(self.teacher_a, "سادس أ")
        self.class_5a = make_classroom(self.teacher_b, "خامس أ", subject="العلوم")
        self.assessment_a = Assessment.objects.create(
            classroom=self.class_6a, title="اختبار الكسور الأول", created_by=self.teacher_a
        )
        self.assessment_b = Assessment.objects.create(
            classroom=self.class_5a, title="اختبار الخلية", created_by=self.teacher_b
        )

    def authenticate(self, profile):
        token = Token.objects.create(user=profile.user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")

    def questions_url(self, assessment):
        return f"/api/v1/assessments/{assessment.id}/questions/"

    def question_payload(self, **overrides):
        return {
            "text": "ما ناتج 1/2 + 1/4؟",
            "max_score": 2,
            "model_answer": "3/4",
            **overrides,
        }

    # ---------------------------------------------------------------- create

    def test_teacher_creates_an_assessment_for_their_own_classroom(self):
        self.authenticate(self.teacher_a)
        response = self.client.post(
            "/api/v1/assessments/",
            {"title": "اختبار الكسور الثاني", "classroom_id": str(self.class_6a.id)},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        created = Assessment.objects.get(title="اختبار الكسور الثاني")
        self.assertEqual(created.classroom, self.class_6a)
        self.assertEqual(created.created_by, self.teacher_a)
        self.assertEqual(response.data["classroom_name"], "سادس أ")
        self.assertEqual(response.data["subject"], "الرياضيات")

    def test_teacher_cannot_create_an_assessment_for_another_teachers_classroom(self):
        self.authenticate(self.teacher_a)
        response = self.client.post(
            "/api/v1/assessments/",
            {"title": "اختبار مسروق", "classroom_id": str(self.class_5a.id)},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("classroom_id", response.data)
        self.assertFalse(Assessment.objects.filter(title="اختبار مسروق").exists())

    def test_manager_creates_an_assessment_for_any_classroom(self):
        self.authenticate(self.manager)
        response = self.client.post(
            "/api/v1/assessments/",
            {"title": "اختبار إداري", "classroom_id": str(self.class_5a.id)},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(Assessment.objects.get(title="اختبار إداري").classroom, self.class_5a)

    def test_assessment_title_is_required(self):
        self.authenticate(self.teacher_a)
        response = self.client.post(
            "/api/v1/assessments/",
            {"title": "", "classroom_id": str(self.class_6a.id)},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    # ------------------------------------------------------------------ list

    def test_teacher_sees_only_assessments_of_their_own_classrooms(self):
        self.authenticate(self.teacher_a)
        response = self.client.get("/api/v1/assessments/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual({item["title"] for item in response.data}, {"اختبار الكسور الأول"})

    def test_manager_sees_all_assessments(self):
        self.authenticate(self.manager)
        response = self.client.get("/api/v1/assessments/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(
            {item["title"] for item in response.data},
            {"اختبار الكسور الأول", "اختبار الخلية"},
        )

    def test_list_reports_question_count_and_total_score(self):
        Question.objects.create(
            assessment=self.assessment_a,
            order=1,
            text="سؤال أول",
            max_score=Decimal("2.5"),
            model_answer="3/4",
        )
        Question.objects.create(
            assessment=self.assessment_a,
            order=2,
            text="سؤال ثانٍ",
            max_score=Decimal("1.5"),
            model_answer="1/2",
        )
        self.authenticate(self.teacher_a)
        response = self.client.get("/api/v1/assessments/")

        self.assertEqual(response.data[0]["questions_count"], 2)
        self.assertEqual(Decimal(str(response.data[0]["total_score"])), Decimal("4"))

    # --------------------------------------------------------------- retrieve

    def test_teacher_retrieves_their_own_assessment_with_questions(self):
        Question.objects.create(
            assessment=self.assessment_a,
            order=1,
            text="ما ناتج 1/2 + 1/4؟",
            max_score=Decimal("2"),
            model_answer="3/4",
        )
        self.authenticate(self.teacher_a)
        response = self.client.get(f"/api/v1/assessments/{self.assessment_a.id}/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data["questions"]), 1)
        self.assertEqual(response.data["questions"][0]["text"], "ما ناتج 1/2 + 1/4؟")
        self.assertEqual(response.data["questions"][0]["model_answer"], "3/4")

    def test_teacher_cannot_retrieve_another_teachers_assessment(self):
        self.authenticate(self.teacher_a)
        response = self.client.get(f"/api/v1/assessments/{self.assessment_b.id}/")

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertNotContains(response, "اختبار الخلية", status_code=status.HTTP_404_NOT_FOUND)

    def test_teacher_updates_the_title_of_their_own_assessment(self):
        self.authenticate(self.teacher_a)
        response = self.client.patch(
            f"/api/v1/assessments/{self.assessment_a.id}/",
            {"title": "اختبار الكسور المعدل"},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assessment_a.refresh_from_db()
        self.assertEqual(self.assessment_a.title, "اختبار الكسور المعدل")

    def test_teacher_cannot_update_another_teachers_assessment(self):
        self.authenticate(self.teacher_a)
        response = self.client.patch(
            f"/api/v1/assessments/{self.assessment_b.id}/",
            {"title": "عنوان مفروض"},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assessment_b.refresh_from_db()
        self.assertEqual(self.assessment_b.title, "اختبار الخلية")

    # --------------------------------------------------------------- questions

    def test_teacher_adds_a_question_to_their_own_assessment(self):
        self.authenticate(self.teacher_a)
        response = self.client.post(
            self.questions_url(self.assessment_a), self.question_payload(), format="json"
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        question = self.assessment_a.questions.get()
        self.assertEqual(question.text, "ما ناتج 1/2 + 1/4؟")
        self.assertEqual(question.max_score, Decimal("2"))
        self.assertEqual(question.model_answer, "3/4")

    def test_question_order_defaults_to_the_end_of_the_assessment(self):
        self.authenticate(self.teacher_a)
        for _ in range(3):
            self.client.post(
                self.questions_url(self.assessment_a), self.question_payload(), format="json"
            )

        self.assertEqual(
            list(self.assessment_a.questions.values_list("order", flat=True)), [1, 2, 3]
        )

    def test_teacher_cannot_add_a_question_to_another_teachers_assessment(self):
        self.authenticate(self.teacher_a)
        response = self.client.post(
            self.questions_url(self.assessment_b), self.question_payload(), format="json"
        )

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertFalse(self.assessment_b.questions.exists())

    def test_teacher_cannot_read_questions_of_another_teachers_assessment(self):
        Question.objects.create(
            assessment=self.assessment_b,
            order=1,
            text="ما وظيفة النواة؟",
            max_score=Decimal("3"),
            model_answer="تنظيم نشاط الخلية",
        )
        self.authenticate(self.teacher_a)
        response = self.client.get(self.questions_url(self.assessment_b))

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertNotContains(response, "النواة", status_code=status.HTTP_404_NOT_FOUND)

    def test_zero_max_score_is_rejected(self):
        self.authenticate(self.teacher_a)
        response = self.client.post(
            self.questions_url(self.assessment_a),
            self.question_payload(max_score=0),
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("max_score", response.data)
        self.assertFalse(self.assessment_a.questions.exists())

    def test_negative_max_score_is_rejected(self):
        self.authenticate(self.teacher_a)
        response = self.client.post(
            self.questions_url(self.assessment_a),
            self.question_payload(max_score=-1),
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertFalse(self.assessment_a.questions.exists())

    def test_duplicate_question_order_is_rejected(self):
        self.authenticate(self.teacher_a)
        first = self.client.post(
            self.questions_url(self.assessment_a),
            self.question_payload(order=1),
            format="json",
        )
        duplicate = self.client.post(
            self.questions_url(self.assessment_a),
            self.question_payload(order=1, text="سؤال مكرر الترتيب"),
            format="json",
        )

        self.assertEqual(first.status_code, status.HTTP_201_CREATED)
        self.assertEqual(duplicate.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("order", duplicate.data)
        self.assertEqual(self.assessment_a.questions.count(), 1)

    def test_teacher_edits_and_deletes_a_question_of_their_own_assessment(self):
        self.authenticate(self.teacher_a)
        created = self.client.post(
            self.questions_url(self.assessment_a), self.question_payload(), format="json"
        )
        question_id = created.data["id"]
        detail_url = f"{self.questions_url(self.assessment_a)}{question_id}/"

        edited = self.client.patch(detail_url, {"max_score": 5}, format="json")
        self.assertEqual(edited.status_code, status.HTTP_200_OK)
        self.assertEqual(self.assessment_a.questions.get().max_score, Decimal("5"))

        removed = self.client.delete(detail_url)
        self.assertEqual(removed.status_code, status.HTTP_204_NO_CONTENT)
        self.assertFalse(self.assessment_a.questions.exists())

    def test_teacher_cannot_delete_a_question_of_another_teachers_assessment(self):
        question = Question.objects.create(
            assessment=self.assessment_b,
            order=1,
            text="ما وظيفة النواة؟",
            max_score=Decimal("3"),
            model_answer="تنظيم نشاط الخلية",
        )
        self.authenticate(self.teacher_a)
        response = self.client.delete(
            f"{self.questions_url(self.assessment_b)}{question.id}/"
        )

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertTrue(Question.objects.filter(id=question.id).exists())

    # -------------------------------------------------------------- accounts

    def test_deactivated_teacher_is_rejected(self):
        self.teacher_a.is_active = False
        self.teacher_a.save(update_fields=["is_active"])
        self.authenticate(self.teacher_a)
        response = self.client.get("/api/v1/assessments/")

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_anonymous_caller_is_rejected(self):
        response = self.client.get("/api/v1/assessments/")

        self.assertIn(
            response.status_code,
            (status.HTTP_401_UNAUTHORIZED, status.HTTP_403_FORBIDDEN),
        )
