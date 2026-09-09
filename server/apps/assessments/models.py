import uuid
from decimal import Decimal

from django.core.validators import MinValueValidator
from django.db import models

from apps.accounts.models import UserProfile
from apps.classrooms.models import Classroom


class AssessmentQuerySet(models.QuerySet):
    def visible_to(self, profile):
        """Managers see every assessment; a teacher only sees the ones on their own classrooms."""
        if profile is None:
            return self.none()
        if profile.is_manager:
            return self
        return self.filter(classroom__teacher=profile)


class Assessment(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    classroom = models.ForeignKey(
        Classroom,
        on_delete=models.CASCADE,
        related_name="assessments",
        verbose_name="الصف",
    )
    title = models.CharField("عنوان الاختبار", max_length=150)
    created_by = models.ForeignKey(
        UserProfile,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="created_assessments",
        verbose_name="أنشئ بواسطة",
    )
    created_at = models.DateTimeField("تاريخ الإنشاء", auto_now_add=True)
    updated_at = models.DateTimeField("آخر تحديث", auto_now=True)

    objects = AssessmentQuerySet.as_manager()

    class Meta:
        verbose_name = "اختبار"
        verbose_name_plural = "الاختبارات"
        ordering = ("-created_at",)

    def __str__(self) -> str:
        return f"{self.title} - {self.classroom.name}"

    def next_question_order(self) -> int:
        """The order to hand a question the caller did not place explicitly."""
        highest = self.questions.aggregate(models.Max("order"))["order__max"]
        return (highest or 0) + 1


class Question(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    assessment = models.ForeignKey(
        Assessment,
        on_delete=models.CASCADE,
        related_name="questions",
        verbose_name="الاختبار",
    )
    order = models.PositiveIntegerField("الترتيب")
    text = models.TextField("نص السؤال")
    max_score = models.DecimalField(
        "الدرجة القصوى",
        max_digits=5,
        decimal_places=2,
        validators=[MinValueValidator(Decimal("0.01"))],
    )
    model_answer = models.TextField("الإجابة النموذجية")
    created_at = models.DateTimeField("تاريخ الإنشاء", auto_now_add=True)
    updated_at = models.DateTimeField("آخر تحديث", auto_now=True)

    class Meta:
        verbose_name = "سؤال"
        verbose_name_plural = "الأسئلة"
        ordering = ("order",)
        constraints = [
            models.UniqueConstraint(
                fields=("assessment", "order"),
                name="unique_question_order_per_assessment",
            ),
            models.CheckConstraint(
                condition=models.Q(max_score__gt=0),
                name="question_max_score_is_positive",
            ),
        ]

    def __str__(self) -> str:
        return f"{self.order}. {self.text[:40]}"
