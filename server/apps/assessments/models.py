import uuid
from decimal import Decimal
from pathlib import Path

from django.core.exceptions import ValidationError
from django.core.validators import MinValueValidator
from django.db import models
from django.dispatch import receiver

from apps.accounts.models import UserProfile
from apps.classrooms.models import Classroom, Student


class AssessmentQuerySet(models.QuerySet):
    def visible_to(self, profile):
        """Managers see every assessment; a teacher only sees the ones on their own classrooms."""
        if profile is None:
            return self.none()
        if profile.is_manager:
            return self
        return self.filter(classroom__teacher=profile)

    def active(self):
        return self.filter(archived_at__isnull=True)

    def archived(self):
        return self.filter(archived_at__isnull=False)


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
    archived_at = models.DateTimeField("تاريخ الأرشفة", null=True, blank=True)

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


class SubmissionQuerySet(models.QuerySet):
    def visible_to(self, profile):
        """Managers see every submission; a teacher only sees the ones on their own assessments."""
        if profile is None:
            return self.none()
        if profile.is_manager:
            return self
        return self.filter(assessment__classroom__teacher=profile)


class Submission(models.Model):
    """One student's attempt at one assessment. Answers hang off it."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    assessment = models.ForeignKey(
        Assessment,
        on_delete=models.CASCADE,
        related_name="submissions",
        verbose_name="الاختبار",
    )
    student = models.ForeignKey(
        Student,
        on_delete=models.CASCADE,
        related_name="submissions",
        verbose_name="الطالب",
    )
    created_by = models.ForeignKey(
        UserProfile,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="created_submissions",
        verbose_name="أنشئ بواسطة",
    )
    created_at = models.DateTimeField("تاريخ الإنشاء", auto_now_add=True)
    updated_at = models.DateTimeField("آخر تحديث", auto_now=True)

    objects = SubmissionQuerySet.as_manager()

    class Meta:
        verbose_name = "تسليم"
        verbose_name_plural = "التسليمات"
        ordering = ("student__internal_code",)
        constraints = [
            models.UniqueConstraint(
                fields=("assessment", "student"),
                name="unique_submission_per_student_and_assessment",
            )
        ]

    def __str__(self) -> str:
        return f"{self.student} - {self.assessment.title}"

    def clean(self):
        """Guards the admin and any direct ORM use; the API checks this too."""
        super().clean()
        if (
            self.assessment_id
            and self.student_id
            and self.student.classroom_id != self.assessment.classroom_id
        ):
            raise ValidationError({"student": "الطالب لا ينتمي إلى صف هذا الاختبار."})


class SubmissionAnswer(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    submission = models.ForeignKey(
        Submission,
        on_delete=models.CASCADE,
        related_name="answers",
        verbose_name="التسليم",
    )
    question = models.ForeignKey(
        Question,
        on_delete=models.CASCADE,
        related_name="answers",
        verbose_name="السؤال",
    )
    answer_text = models.TextField("إجابة الطالب", blank=True)
    created_at = models.DateTimeField("تاريخ الإنشاء", auto_now_add=True)
    updated_at = models.DateTimeField("آخر تحديث", auto_now=True)

    class Meta:
        verbose_name = "إجابة"
        verbose_name_plural = "الإجابات"
        ordering = ("question__order",)
        constraints = [
            models.UniqueConstraint(
                fields=("submission", "question"),
                name="unique_answer_per_question_and_submission",
            )
        ]

    def __str__(self) -> str:
        return f"{self.submission} - {self.question.order}"

    def clean(self):
        super().clean()
        if (
            self.submission_id
            and self.question_id
            and self.question.assessment_id != self.submission.assessment_id
        ):
            raise ValidationError({"question": "السؤال لا ينتمي إلى هذا الاختبار."})


def attachment_upload_path(instance, filename):
    """Store under a per-submission folder using a generated name, so an
    unsafe or colliding client filename never reaches the filesystem."""
    suffix = Path(filename).suffix.lower()
    return f"submission_attachments/{instance.submission_id}/{uuid.uuid4().hex}{suffix}"


def source_attachment_upload_path(instance, filename):
    """Same generated-name rule as student papers, under the assessment."""
    suffix = Path(filename).suffix.lower()
    return f"assessment_source/{instance.assessment_id}/{uuid.uuid4().hex}{suffix}"


class SubmissionAttachment(models.Model):
    """A photo or PDF of the student's paper. One submission may have several,
    because a paper can run to more than one page."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    submission = models.ForeignKey(
        Submission,
        on_delete=models.CASCADE,
        related_name="attachments",
        verbose_name="التسليم",
    )
    file = models.FileField("الملف", upload_to=attachment_upload_path)
    original_filename = models.CharField("اسم الملف الأصلي", max_length=255)
    content_type = models.CharField("نوع الملف", max_length=100)
    file_size = models.PositiveIntegerField("حجم الملف")
    created_by = models.ForeignKey(
        UserProfile,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="uploaded_attachments",
        verbose_name="رفع بواسطة",
    )
    created_at = models.DateTimeField("تاريخ الرفع", auto_now_add=True)

    class Meta:
        verbose_name = "مرفق"
        verbose_name_plural = "المرفقات"
        ordering = ("created_at",)

    def __str__(self) -> str:
        return self.original_filename


class AttachmentOcrResult(models.Model):
    """The current OCR pass for one attachment. OneToOne so a retry updates
    this row instead of stacking history the UI cannot show yet."""

    class Status(models.TextChoices):
        PENDING = "pending", "قيد الانتظار"
        PROCESSING = "processing", "جاري الاستخراج"
        COMPLETED = "completed", "مكتمل"
        FAILED = "failed", "فشل"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    attachment = models.OneToOneField(
        SubmissionAttachment,
        on_delete=models.CASCADE,
        related_name="ocr_result",
        verbose_name="المرفق",
    )
    status = models.CharField(
        "الحالة",
        max_length=20,
        choices=Status.choices,
        default=Status.PENDING,
    )
    extracted_text = models.TextField("النص المستخرج", blank=True)
    error_message = models.TextField("رسالة الخطأ", blank=True)
    created_at = models.DateTimeField("تاريخ الإنشاء", auto_now_add=True)
    updated_at = models.DateTimeField("آخر تحديث", auto_now=True)
    processed_at = models.DateTimeField("تاريخ المعالجة", null=True, blank=True)

    class Meta:
        verbose_name = "نتيجة التعرف الضوئي"
        verbose_name_plural = "نتائج التعرف الضوئي"

    def __str__(self) -> str:
        return f"{self.attachment} ({self.get_status_display()})"


class OcrAnswerCandidate(models.Model):
    """A heuristic suggestion from OCR, one current row per question. The
    teacher still has to confirm it into SubmissionAnswer before it counts."""

    class Status(models.TextChoices):
        SUGGESTED = "suggested", "مقترح"
        CONFIRMED = "confirmed", "مؤكد"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    submission = models.ForeignKey(
        Submission,
        on_delete=models.CASCADE,
        related_name="ocr_candidates",
        verbose_name="التسليم",
    )
    question = models.ForeignKey(
        Question,
        on_delete=models.CASCADE,
        related_name="ocr_candidates",
        verbose_name="السؤال",
    )
    extracted_text = models.TextField("النص المقترح", blank=True)
    source = models.CharField("المصدر", max_length=20, default="ocr")
    status = models.CharField(
        "الحالة",
        max_length=20,
        choices=Status.choices,
        default=Status.SUGGESTED,
    )
    created_at = models.DateTimeField("تاريخ الإنشاء", auto_now_add=True)
    updated_at = models.DateTimeField("آخر تحديث", auto_now=True)

    class Meta:
        verbose_name = "اقتراح إجابة"
        verbose_name_plural = "اقتراحات الإجابات"
        ordering = ("question__order",)
        constraints = [
            models.UniqueConstraint(
                fields=("submission", "question"),
                name="unique_ocr_candidate_per_question_and_submission",
            )
        ]

    def __str__(self) -> str:
        return f"{self.submission} - {self.question.order}"

    def clean(self):
        super().clean()
        if (
            self.submission_id
            and self.question_id
            and self.question.assessment_id != self.submission.assessment_id
        ):
            raise ValidationError({"question": "السؤال لا ينتمي إلى هذا الاختبار."})


class AnswerEvaluation(models.Model):
    """The current AI grade for one confirmed student answer. OneToOne so a
    re-run updates this row instead of stacking history the UI cannot show."""

    class Status(models.TextChoices):
        CORRECT = "correct", "صحيح"
        PARTIAL = "partial", "صحيح جزئيًا"
        INCORRECT = "incorrect", "غير صحيح"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    answer = models.OneToOneField(
        SubmissionAnswer,
        on_delete=models.CASCADE,
        related_name="evaluation",
        verbose_name="الإجابة",
    )
    status = models.CharField("الحالة", max_length=20, choices=Status.choices)
    awarded_score = models.DecimalField(
        "الدرجة الممنوحة",
        max_digits=5,
        decimal_places=2,
        validators=[MinValueValidator(Decimal("0"))],
    )
    feedback = models.TextField("الملاحظات")
    misconception = models.TextField("الفهم الخاطئ", blank=True)
    model_name = models.CharField("النموذج", max_length=80)
    created_at = models.DateTimeField("تاريخ الإنشاء", auto_now_add=True)
    updated_at = models.DateTimeField("آخر تحديث", auto_now=True)
    evaluated_at = models.DateTimeField("تاريخ التقييم")

    class Meta:
        verbose_name = "تقييم إجابة"
        verbose_name_plural = "تقييمات الإجابات"
        constraints = [
            models.CheckConstraint(
                condition=models.Q(awarded_score__gte=0),
                name="evaluation_awarded_score_is_not_negative",
            )
        ]

    def __str__(self) -> str:
        return f"{self.answer} - {self.get_status_display()}"


class RemediationPlan(models.Model):
    """The current AI plan for one student group on one assessment.

    Unique per (assessment, group) so regenerate updates this row instead of
    stacking history the UI cannot show.
    """

    class Group(models.TextChoices):
        FOUNDATION = "foundation", "تأسيس"
        PRACTICE = "practice", "تدريب"
        READY = "ready", "جاهز"

    class Status(models.TextChoices):
        PENDING = "pending", "قيد الإنشاء"
        COMPLETED = "completed", "مكتملة"
        FAILED = "failed", "فشلت"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    assessment = models.ForeignKey(
        Assessment,
        on_delete=models.CASCADE,
        related_name="remediation_plans",
        verbose_name="الاختبار",
    )
    group = models.CharField("المجموعة", max_length=20, choices=Group.choices)
    status = models.CharField(
        "الحالة", max_length=20, choices=Status.choices, default=Status.PENDING
    )
    title = models.CharField("العنوان", max_length=200, blank=True)
    summary = models.TextField("الملخص", blank=True)
    objectives = models.JSONField("الأهداف", default=list)
    activities = models.JSONField("الأنشطة", default=list)
    teacher_guidance = models.TextField("إرشادات المعلم", blank=True)
    model_name = models.CharField("النموذج", max_length=80, blank=True)
    generated_at = models.DateTimeField("تاريخ التوليد", null=True, blank=True)
    created_at = models.DateTimeField("تاريخ الإنشاء", auto_now_add=True)
    updated_at = models.DateTimeField("آخر تحديث", auto_now=True)

    class Meta:
        verbose_name = "خطة علاجية"
        verbose_name_plural = "الخطط العلاجية"
        constraints = [
            models.UniqueConstraint(
                fields=("assessment", "group"),
                name="unique_remediation_plan_per_assessment_group",
            )
        ]

    def __str__(self) -> str:
        return f"{self.assessment} - {self.get_group_display()}"


class AssessmentSourceAttachment(models.Model):
    """The teacher's exam paper (photo or PDF) used to propose questions."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    assessment = models.ForeignKey(
        Assessment,
        on_delete=models.CASCADE,
        related_name="source_attachments",
        verbose_name="الاختبار",
    )
    file = models.FileField("الملف", upload_to=source_attachment_upload_path)
    original_filename = models.CharField("اسم الملف الأصلي", max_length=255)
    content_type = models.CharField("نوع الملف", max_length=100)
    file_size = models.PositiveIntegerField("حجم الملف")
    created_by = models.ForeignKey(
        UserProfile,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="uploaded_source_attachments",
        verbose_name="رفع بواسطة",
    )
    created_at = models.DateTimeField("تاريخ الرفع", auto_now_add=True)

    class Meta:
        verbose_name = "ورقة اختبار"
        verbose_name_plural = "أوراق الاختبار"
        ordering = ("created_at",)

    def __str__(self) -> str:
        return self.original_filename


class AssessmentQuestionCandidate(models.Model):
    """A suggested question from the exam paper. The teacher confirms it
    into a real Question; extraction never writes Question rows itself."""

    class Status(models.TextChoices):
        SUGGESTED = "suggested", "مقترح"
        CONFIRMED = "confirmed", "مؤكد"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    assessment = models.ForeignKey(
        Assessment,
        on_delete=models.CASCADE,
        related_name="question_candidates",
        verbose_name="الاختبار",
    )
    order = models.PositiveIntegerField("الترتيب")
    extracted_text = models.TextField("النص المستخرج")
    proposed_max_score = models.DecimalField(
        "الدرجة المقترحة",
        max_digits=5,
        decimal_places=2,
        null=True,
        blank=True,
    )
    proposed_model_answer = models.TextField("الإجابة النموذجية المقترحة", blank=True)
    status = models.CharField(
        "الحالة",
        max_length=20,
        choices=Status.choices,
        default=Status.SUGGESTED,
    )
    created_at = models.DateTimeField("تاريخ الإنشاء", auto_now_add=True)
    updated_at = models.DateTimeField("آخر تحديث", auto_now=True)

    class Meta:
        verbose_name = "سؤال مستخرج"
        verbose_name_plural = "الأسئلة المستخرجة"
        ordering = ("order",)
        constraints = [
            models.UniqueConstraint(
                fields=("assessment", "order"),
                name="unique_question_candidate_order_per_assessment",
            )
        ]

    def __str__(self) -> str:
        return f"{self.order}. {self.extracted_text[:40]}"


@receiver(models.signals.post_delete, sender=SubmissionAttachment)
def discard_attachment_file(sender, instance, **kwargs):
    """Django drops the row but keeps the file, so remove it here. A signal
    rather than an overridden delete() so cascades are covered too."""
    instance.file.delete(save=False)


@receiver(models.signals.post_delete, sender=AssessmentSourceAttachment)
def discard_source_attachment_file(sender, instance, **kwargs):
    instance.file.delete(save=False)
