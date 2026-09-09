import uuid

from django.db import models

from apps.accounts.models import UserProfile


class ClassroomQuerySet(models.QuerySet):
    def visible_to(self, profile):
        """Managers see every classroom; a teacher only sees the ones assigned to them."""
        if profile is None:
            return self.none()
        if profile.is_manager:
            return self
        return self.filter(teacher=profile)


class Classroom(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    teacher = models.ForeignKey(
        UserProfile,
        on_delete=models.CASCADE,
        related_name="classrooms",
        verbose_name="المعلم",
    )
    name = models.CharField("اسم الصف", max_length=100)
    grade = models.CharField("المرحلة أو الصف الدراسي", max_length=80)
    subject = models.CharField("المادة", max_length=80)
    academic_year = models.CharField("العام الدراسي", max_length=20)
    is_active = models.BooleanField("نشط", default=True)
    created_at = models.DateTimeField("تاريخ الإنشاء", auto_now_add=True)
    updated_at = models.DateTimeField("آخر تحديث", auto_now=True)

    objects = ClassroomQuerySet.as_manager()

    class Meta:
        verbose_name = "صف"
        verbose_name_plural = "الصفوف"
        ordering = ("-created_at",)
        constraints = [
            models.UniqueConstraint(
                fields=("teacher", "name", "academic_year"),
                name="unique_classroom_per_teacher_year",
            )
        ]

    def __str__(self) -> str:
        return f"{self.name} - {self.subject}"


class Student(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    classroom = models.ForeignKey(
        Classroom,
        on_delete=models.CASCADE,
        related_name="students",
        verbose_name="الصف",
    )
    internal_code = models.CharField(
        "الرمز الداخلي",
        max_length=24,
        help_text="رمز غير حساس يستخدم أثناء التحليل بدل اسم الطالب.",
    )
    display_name = models.CharField(
        "اسم العرض",
        max_length=120,
        blank=True,
        help_text="يبقى داخل نظام بيّن ولا يرسل إلى مزود الذكاء الاصطناعي.",
    )
    is_active = models.BooleanField("نشط", default=True)
    created_at = models.DateTimeField("تاريخ الإنشاء", auto_now_add=True)
    updated_at = models.DateTimeField("آخر تحديث", auto_now=True)

    class Meta:
        verbose_name = "طالب"
        verbose_name_plural = "الطلاب"
        ordering = ("internal_code",)
        constraints = [
            models.UniqueConstraint(
                fields=("classroom", "internal_code"),
                name="unique_student_code_per_classroom",
            )
        ]

    def __str__(self) -> str:
        return self.display_name or self.internal_code
