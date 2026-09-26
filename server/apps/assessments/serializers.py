from decimal import Decimal
from pathlib import Path

from django.conf import settings
from django.db import transaction
from django.urls import reverse
from django.utils import timezone
from rest_framework import serializers

from apps.classrooms.models import Classroom, Student

from .models import (
    AnswerEvaluation,
    Assessment,
    AssessmentQuestionCandidate,
    AssessmentSourceAttachment,
    AttachmentOcrResult,
    OcrAnswerCandidate,
    Question,
    RemediationPlan,
    Submission,
    SubmissionAnswer,
    SubmissionAttachment,
)


class QuestionSerializer(serializers.ModelSerializer):
    # `coerce_to_string=False` keeps the score a JSON number so the client can
    # add scores up without parsing strings.
    max_score = serializers.DecimalField(
        max_digits=5,
        decimal_places=2,
        min_value=Decimal("0.01"),
        coerce_to_string=False,
        error_messages={"min_value": "الدرجة القصوى يجب أن تكون أكبر من صفر."},
    )
    order = serializers.IntegerField(min_value=1, required=False)

    class Meta:
        model = Question
        fields = ("id", "order", "text", "max_score", "model_answer")
        read_only_fields = ("id",)

    def validate_order(self, value):
        assessment = self.context.get("assessment")
        if assessment is None:
            return value
        clashes = assessment.questions.filter(order=value)
        if self.instance is not None:
            clashes = clashes.exclude(pk=self.instance.pk)
        if clashes.exists():
            raise serializers.ValidationError("ترتيب السؤال مستخدم داخل هذا الاختبار.")
        return value

    def create(self, validated_data):
        assessment = self.context["assessment"]
        validated_data.setdefault("order", assessment.next_question_order())
        return Question.objects.create(assessment=assessment, **validated_data)


class AssessmentSerializer(serializers.ModelSerializer):
    classroom_id = serializers.PrimaryKeyRelatedField(
        source="classroom",
        queryset=Classroom.objects.none(),
    )
    classroom_name = serializers.CharField(source="classroom.name", read_only=True)
    grade = serializers.CharField(source="classroom.grade", read_only=True)
    subject = serializers.CharField(source="classroom.subject", read_only=True)
    questions_count = serializers.SerializerMethodField()
    total_score = serializers.SerializerMethodField()
    archived = serializers.BooleanField(required=False, write_only=True)
    archived_at = serializers.DateTimeField(read_only=True)

    class Meta:
        model = Assessment
        fields = (
            "id",
            "title",
            "classroom_id",
            "classroom_name",
            "grade",
            "subject",
            "questions_count",
            "total_score",
            "created_at",
            "archived_at",
            "archived",
        )
        read_only_fields = ("id", "created_at", "archived_at")

    def get_fields(self):
        fields = super().get_fields()
        # The only classrooms a caller may attach an assessment to are the ones
        # they can already see, so a teacher cannot target another teacher's class.
        fields["classroom_id"].queryset = Classroom.objects.visible_to(
            self.context.get("profile")
        )
        return fields

    def get_questions_count(self, assessment) -> int:
        return len(assessment.questions.all())

    def get_total_score(self, assessment) -> Decimal:
        return sum(
            (question.max_score for question in assessment.questions.all()),
            Decimal("0"),
        )

    def to_representation(self, instance):
        data = super().to_representation(instance)
        data["archived"] = instance.archived_at is not None
        return data

    def create(self, validated_data):
        validated_data.pop("archived", None)
        return super().create(validated_data)

    def update(self, instance, validated_data):
        archived = validated_data.pop("archived", None)
        instance = super().update(instance, validated_data)
        if archived is True and instance.archived_at is None:
            instance.archived_at = timezone.now()
            instance.save(update_fields=["archived_at", "updated_at"])
        elif archived is False and instance.archived_at is not None:
            instance.archived_at = None
            instance.save(update_fields=["archived_at", "updated_at"])
        return instance


class AssessmentDetailSerializer(AssessmentSerializer):
    questions = QuestionSerializer(many=True, read_only=True)

    class Meta(AssessmentSerializer.Meta):
        fields = AssessmentSerializer.Meta.fields + ("questions",)


class SubmissionSerializer(serializers.ModelSerializer):
    student_id = serializers.PrimaryKeyRelatedField(
        source="student",
        queryset=Student.objects.none(),
    )
    student_name = serializers.CharField(source="student.display_name", read_only=True)
    student_code = serializers.CharField(source="student.internal_code", read_only=True)

    class Meta:
        model = Submission
        fields = ("id", "student_id", "student_name", "student_code", "created_at")
        read_only_fields = ("id", "created_at")

    def get_fields(self):
        fields = super().get_fields()
        assessment = self.context.get("assessment")
        # Only the roster of the assessment's own classroom is selectable, so a
        # student from another class can never be attached to it.
        fields["student_id"].queryset = (
            Student.objects.filter(classroom=assessment.classroom)
            if assessment is not None
            else Student.objects.none()
        )
        return fields

    def validate(self, attrs):
        # The unique constraint would raise a 500; catching it here makes the
        # duplicate a plain validation error instead.
        assessment = self.context["assessment"]
        if Submission.objects.filter(
            assessment=assessment, student=attrs["student"]
        ).exists():
            raise serializers.ValidationError(
                {"student_id": "لهذا الطالب تسليم مسجل في هذا الاختبار."}
            )
        return attrs


class AnswerEvaluationSerializer(serializers.ModelSerializer):
    awarded_score = serializers.DecimalField(
        max_digits=5, decimal_places=2, coerce_to_string=False, read_only=True
    )

    class Meta:
        model = AnswerEvaluation
        fields = (
            "id",
            "status",
            "awarded_score",
            "feedback",
            "misconception",
            "evaluated_at",
        )
        read_only_fields = fields


class SubmissionDetailSerializer(SubmissionSerializer):
    """Carries every question of the assessment, answered or not, so the entry
    screen can render the whole form from a single response."""

    assessment_id = serializers.UUIDField(source="assessment.id", read_only=True)
    assessment_title = serializers.CharField(source="assessment.title", read_only=True)
    answers = serializers.SerializerMethodField()

    class Meta(SubmissionSerializer.Meta):
        fields = SubmissionSerializer.Meta.fields + (
            "assessment_id",
            "assessment_title",
            "answers",
        )

    def get_answers(self, submission):
        stored = {}
        for row in submission.answers.all():
            stored[row.question_id] = row
            stored[str(row.question_id)] = row
        payload = []
        for question in submission.assessment.questions.all():
            answer = stored.get(question.id) or stored.get(str(question.id))
            payload.append(
                {
                    "id": str(answer.id) if answer else None,
                    "question_id": str(question.id),
                    "order": question.order,
                    "text": question.text,
                    "max_score": question.max_score,
                    "answer_text": answer.answer_text if answer else "",
                    "evaluation": self._evaluation_of(answer),
                }
            )
        return payload

    def _evaluation_of(self, answer):
        if answer is None:
            return None
        try:
            return AnswerEvaluationSerializer(answer.evaluation).data
        except AnswerEvaluation.DoesNotExist:
            return None


class AnswerInputSerializer(serializers.Serializer):
    question_id = serializers.UUIDField()
    answer_text = serializers.CharField(allow_blank=True, trim_whitespace=False)


class AnswerBulkWriteSerializer(serializers.Serializer):
    """Saves the whole answer sheet in one call: existing answers are updated,
    missing ones are created, so the client never tracks answer ids."""

    answers = AnswerInputSerializer(many=True, allow_empty=True)

    def validate_answers(self, value):
        submission = self.context["submission"]
        allowed = set(submission.assessment.questions.values_list("id", flat=True))
        seen = set()
        for entry in value:
            question_id = entry["question_id"]
            if question_id not in allowed:
                raise serializers.ValidationError("السؤال لا ينتمي إلى هذا الاختبار.")
            if question_id in seen:
                raise serializers.ValidationError("لا يمكن إرسال إجابتين لنفس السؤال.")
            seen.add(question_id)
        return value

    @transaction.atomic
    def save(self, **kwargs):
        submission = self.context["submission"]
        for entry in self.validated_data["answers"]:
            incoming = entry["answer_text"]
            existing = SubmissionAnswer.objects.filter(
                submission=submission, question_id=entry["question_id"]
            ).first()
            # A stale empty sheet save must not erase text that OCR confirm
            # already wrote. Creating a new blank row is still allowed.
            if (
                existing is not None
                and existing.answer_text.strip()
                and not incoming.strip()
            ):
                continue
            if existing is not None and existing.answer_text != incoming:
                AnswerEvaluation.objects.filter(answer=existing).delete()
            SubmissionAnswer.objects.update_or_create(
                submission=submission,
                question_id=entry["question_id"],
                defaults={"answer_text": incoming},
            )
        cache = getattr(submission, "_prefetched_objects_cache", None)
        if cache is not None:
            cache.pop("answers", None)
        return submission


SUPPORTED_ATTACHMENT_TYPES = {
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".pdf": "application/pdf",
}

# Leading bytes every file of that type starts with.
_FILE_SIGNATURES = (
    (b"\xff\xd8\xff", "image/jpeg"),
    (b"\x89PNG\r\n\x1a\n", "image/png"),
    (b"%PDF-", "application/pdf"),
)


def sniff_content_type(uploaded_file):
    """The type the file's own leading bytes claim, or None if unrecognised."""
    head = uploaded_file.read(8)
    uploaded_file.seek(0)
    for signature, content_type in _FILE_SIGNATURES:
        if head.startswith(signature):
            return content_type
    return None


def validate_uploaded_attachment(uploaded_file):
    """Shared JPG/PNG/PDF + 10 MB + signature check for student and exam papers."""
    if uploaded_file.size > settings.SUBMISSION_ATTACHMENT_MAX_BYTES:
        raise serializers.ValidationError("حجم الملف كبير جدًا.")
    expected = SUPPORTED_ATTACHMENT_TYPES.get(
        Path(uploaded_file.name or "").suffix.lower()
    )
    if expected is None or sniff_content_type(uploaded_file) != expected:
        raise serializers.ValidationError("نوع الملف غير مدعوم.")
    return uploaded_file


class SubmissionAttachmentSerializer(serializers.ModelSerializer):
    file = serializers.FileField(write_only=True)
    download_url = serializers.SerializerMethodField()

    class Meta:
        model = SubmissionAttachment
        fields = (
            "id",
            "file",
            "original_filename",
            "content_type",
            "file_size",
            "download_url",
            "created_at",
        )
        read_only_fields = (
            "id",
            "original_filename",
            "content_type",
            "file_size",
            "created_at",
        )

    def get_download_url(self, attachment):
        return reverse(
            "assessment-submission-attachment-download",
            kwargs={
                "assessment_id": attachment.submission.assessment_id,
                "submission_id": attachment.submission_id,
                "attachment_id": attachment.id,
            },
        )

    def validate_file(self, uploaded_file):
        return validate_uploaded_attachment(uploaded_file)

    def create(self, validated_data):
        uploaded_file = validated_data["file"]
        return SubmissionAttachment.objects.create(
            submission=self.context["submission"],
            created_by=self.context["profile"],
            file=uploaded_file,
            original_filename=Path(uploaded_file.name).name[:255],
            content_type=sniff_content_type(uploaded_file),
            file_size=uploaded_file.size,
        )


class AttachmentOcrResultSerializer(serializers.ModelSerializer):
    class Meta:
        model = AttachmentOcrResult
        fields = (
            "id",
            "status",
            "extracted_text",
            "error_message",
            "processed_at",
            "updated_at",
        )
        read_only_fields = fields


class OcrAnswerCandidateSerializer(serializers.ModelSerializer):
    question_id = serializers.UUIDField(source="question.id", read_only=True)
    order = serializers.IntegerField(source="question.order", read_only=True)
    question_text = serializers.CharField(source="question.text", read_only=True)
    max_score = serializers.DecimalField(
        source="question.max_score",
        max_digits=5,
        decimal_places=2,
        coerce_to_string=False,
        read_only=True,
    )
    current_answer = serializers.SerializerMethodField()

    class Meta:
        model = OcrAnswerCandidate
        fields = (
            "id",
            "question_id",
            "order",
            "question_text",
            "max_score",
            "extracted_text",
            "status",
            "current_answer",
        )
        read_only_fields = fields

    def get_current_answer(self, candidate):
        answers = self.context.get("answers_by_question") or {}
        return answers.get(candidate.question_id) or answers.get(
            str(candidate.question_id), ""
        )


class OcrMappingSerializer(serializers.Serializer):
    candidates = OcrAnswerCandidateSerializer(many=True)
    incomplete_ocr = serializers.BooleanField()


class QuestionGapSerializer(serializers.Serializer):
    question_id = serializers.UUIDField()
    question_order = serializers.IntegerField()
    question_text = serializers.CharField()
    status = serializers.CharField()
    awarded_score = serializers.DecimalField(
        max_digits=5, decimal_places=2, coerce_to_string=False
    )
    max_score = serializers.DecimalField(
        max_digits=5, decimal_places=2, coerce_to_string=False
    )
    feedback = serializers.CharField()
    misconception = serializers.CharField(allow_blank=True)


class ClassInsightsSummarySerializer(serializers.Serializer):
    total_students_in_class = serializers.IntegerField()
    students_with_submission = serializers.IntegerField()
    students_without_submission = serializers.IntegerField()
    complete_results = serializers.IntegerField()
    incomplete_results = serializers.IntegerField()
    average_percentage = serializers.DecimalField(
        max_digits=6,
        decimal_places=2,
        allow_null=True,
        coerce_to_string=False,
    )


class ClassQuestionGapSerializer(serializers.Serializer):
    question_id = serializers.UUIDField()
    question_order = serializers.IntegerField()
    question_text = serializers.CharField()
    max_score = serializers.DecimalField(
        max_digits=5, decimal_places=2, coerce_to_string=False
    )
    evaluated_students = serializers.IntegerField()
    correct_count = serializers.IntegerField()
    partial_count = serializers.IntegerField()
    incorrect_count = serializers.IntegerField()
    gap_count = serializers.IntegerField()
    gap_percentage = serializers.DecimalField(
        max_digits=6,
        decimal_places=2,
        allow_null=True,
        coerce_to_string=False,
    )


class MisconceptionCountSerializer(serializers.Serializer):
    text = serializers.CharField()
    count = serializers.IntegerField()


class GroupedStudentSerializer(serializers.Serializer):
    student_id = serializers.UUIDField()
    display_name = serializers.CharField(allow_blank=True)
    student_code = serializers.CharField()
    percentage = serializers.DecimalField(
        max_digits=6, decimal_places=2, coerce_to_string=False
    )
    group = serializers.CharField()


class PendingStudentSerializer(serializers.Serializer):
    student_id = serializers.UUIDField()
    display_name = serializers.CharField(allow_blank=True)
    student_code = serializers.CharField()
    reason = serializers.CharField()


class ClassGroupsSerializer(serializers.Serializer):
    foundation = GroupedStudentSerializer(many=True)
    practice = GroupedStudentSerializer(many=True)
    ready = GroupedStudentSerializer(many=True)


class ClassInsightsSerializer(serializers.Serializer):
    summary = ClassInsightsSummarySerializer()
    question_gaps = ClassQuestionGapSerializer(many=True)
    misconceptions = MisconceptionCountSerializer(many=True)
    groups = ClassGroupsSerializer()
    pending_students = PendingStudentSerializer(many=True)


class SubmissionResultSerializer(serializers.Serializer):
    is_evaluable = serializers.BooleanField()
    is_complete = serializers.BooleanField()
    awarded_score_total = serializers.DecimalField(
        max_digits=8, decimal_places=2, coerce_to_string=False
    )
    max_score_total = serializers.DecimalField(
        max_digits=8, decimal_places=2, coerce_to_string=False
    )
    percentage = serializers.DecimalField(
        max_digits=6, decimal_places=2, coerce_to_string=False
    )
    evaluated_questions = serializers.IntegerField()
    total_questions = serializers.IntegerField()
    correct_count = serializers.IntegerField()
    partial_count = serializers.IntegerField()
    incorrect_count = serializers.IntegerField()
    unevaluated_count = serializers.IntegerField()
    gaps = QuestionGapSerializer(many=True)
    misconceptions = serializers.ListField(child=serializers.CharField())


class RemediationActivitySerializer(serializers.Serializer):
    title = serializers.CharField()
    description = serializers.CharField()
    duration_minutes = serializers.IntegerField(allow_null=True)


class RemediationPlanSerializer(serializers.ModelSerializer):
    activities = RemediationActivitySerializer(many=True)

    class Meta:
        model = RemediationPlan
        fields = (
            "id",
            "assessment",
            "group",
            "status",
            "title",
            "summary",
            "objectives",
            "activities",
            "teacher_guidance",
            "model_name",
            "generated_at",
        )
        read_only_fields = fields


class RemediationGenerateSerializer(serializers.Serializer):
    group_empty = serializers.BooleanField()
    group = serializers.CharField()
    plan = RemediationPlanSerializer(allow_null=True)


class ManagerInsightsSummarySerializer(serializers.Serializer):
    total_teachers = serializers.IntegerField()
    total_classrooms = serializers.IntegerField()
    total_students = serializers.IntegerField()
    total_assessments = serializers.IntegerField()
    assessments_with_complete_results = serializers.IntegerField()
    assessments_with_incomplete_results = serializers.IntegerField()
    overall_average_percentage = serializers.DecimalField(
        max_digits=6,
        decimal_places=2,
        allow_null=True,
        coerce_to_string=False,
    )


class ManagerClassroomRowSerializer(serializers.Serializer):
    classroom_id = serializers.UUIDField()
    classroom_name = serializers.CharField()
    grade = serializers.CharField()
    subject = serializers.CharField()
    teacher_name = serializers.CharField()
    student_count = serializers.IntegerField()
    assessment_count = serializers.IntegerField()
    completed_results_count = serializers.IntegerField()
    incomplete_results_count = serializers.IntegerField()
    average_percentage = serializers.DecimalField(
        max_digits=6,
        decimal_places=2,
        allow_null=True,
        coerce_to_string=False,
    )


class ManagerTeacherRowSerializer(serializers.Serializer):
    teacher_id = serializers.UUIDField()
    display_name = serializers.CharField()
    classrooms_count = serializers.IntegerField()
    students_count = serializers.IntegerField()
    assessments_count = serializers.IntegerField()
    complete_results_count = serializers.IntegerField()
    incomplete_results_count = serializers.IntegerField()
    average_percentage = serializers.DecimalField(
        max_digits=6,
        decimal_places=2,
        allow_null=True,
        coerce_to_string=False,
    )


class ManagerAssessmentRowSerializer(serializers.Serializer):
    assessment_id = serializers.UUIDField()
    title = serializers.CharField()
    classroom = serializers.CharField()
    teacher = serializers.CharField()
    students_with_submission = serializers.IntegerField()
    complete_results = serializers.IntegerField()
    incomplete_results = serializers.IntegerField()
    average_percentage = serializers.DecimalField(
        max_digits=6,
        decimal_places=2,
        allow_null=True,
        coerce_to_string=False,
    )


class ManagerGapQuestionSerializer(serializers.Serializer):
    assessment_title = serializers.CharField()
    classroom = serializers.CharField()
    question_order = serializers.IntegerField()
    question_text = serializers.CharField()
    evaluated_students = serializers.IntegerField()
    gap_count = serializers.IntegerField()
    gap_percentage = serializers.DecimalField(
        max_digits=6,
        decimal_places=2,
        allow_null=True,
        coerce_to_string=False,
    )


class ManagerInsightsSerializer(serializers.Serializer):
    summary = ManagerInsightsSummarySerializer()
    classrooms = ManagerClassroomRowSerializer(many=True)
    teachers = ManagerTeacherRowSerializer(many=True)
    assessments = ManagerAssessmentRowSerializer(many=True)
    highest_gap_questions = ManagerGapQuestionSerializer(many=True)
    misconceptions = MisconceptionCountSerializer(many=True)


class AssessmentSourceAttachmentSerializer(serializers.ModelSerializer):
    file = serializers.FileField(write_only=True)
    download_url = serializers.SerializerMethodField()

    class Meta:
        model = AssessmentSourceAttachment
        fields = (
            "id",
            "file",
            "original_filename",
            "content_type",
            "file_size",
            "download_url",
            "created_at",
        )
        read_only_fields = (
            "id",
            "original_filename",
            "content_type",
            "file_size",
            "created_at",
        )

    def get_download_url(self, attachment):
        return reverse(
            "assessment-source-attachment-download",
            kwargs={
                "assessment_id": attachment.assessment_id,
                "attachment_id": attachment.id,
            },
        )

    def validate_file(self, uploaded_file):
        return validate_uploaded_attachment(uploaded_file)

    def create(self, validated_data):
        uploaded_file = validated_data["file"]
        return AssessmentSourceAttachment.objects.create(
            assessment=self.context["assessment"],
            created_by=self.context["profile"],
            file=uploaded_file,
            original_filename=Path(uploaded_file.name).name[:255],
            content_type=sniff_content_type(uploaded_file),
            file_size=uploaded_file.size,
        )


class AssessmentQuestionCandidateSerializer(serializers.ModelSerializer):
    proposed_max_score = serializers.DecimalField(
        max_digits=5,
        decimal_places=2,
        required=False,
        allow_null=True,
        coerce_to_string=False,
    )
    order = serializers.IntegerField(min_value=1)

    class Meta:
        model = AssessmentQuestionCandidate
        fields = (
            "id",
            "order",
            "extracted_text",
            "proposed_max_score",
            "proposed_model_answer",
            "status",
        )
        read_only_fields = ("id", "status")

    def validate_order(self, value):
        assessment = self.context.get("assessment")
        if assessment is None:
            return value
        clashes = assessment.question_candidates.filter(order=value)
        if self.instance is not None:
            clashes = clashes.exclude(pk=self.instance.pk)
        if clashes.exists():
            raise serializers.ValidationError("ترتيب السؤال مستخدم داخل هذا الاختبار.")
        return value


class QuestionCandidateConfirmItemSerializer(serializers.Serializer):
    id = serializers.UUIDField(required=False)
    order = serializers.IntegerField(min_value=1)
    extracted_text = serializers.CharField(trim_whitespace=True)
    proposed_max_score = serializers.DecimalField(
        max_digits=5,
        decimal_places=2,
        min_value=Decimal("0.01"),
        coerce_to_string=False,
        error_messages={"min_value": "الدرجة القصوى يجب أن تكون أكبر من صفر."},
    )
    proposed_model_answer = serializers.CharField(allow_blank=False, trim_whitespace=True)

    def validate_extracted_text(self, value):
        if not value.strip():
            raise serializers.ValidationError("نص السؤال مطلوب.")
        return value.strip()


class QuestionCandidateConfirmSerializer(serializers.Serializer):
    candidates = QuestionCandidateConfirmItemSerializer(many=True, allow_empty=False)

    def validate_candidates(self, value):
        orders = [item["order"] for item in value]
        if len(orders) != len(set(orders)):
            raise serializers.ValidationError("ترتيب السؤال مستخدم داخل هذا الاختبار.")
        return value

    @transaction.atomic
    def save(self, **kwargs):
        assessment = self.context["assessment"]
        incoming = self.validated_data["candidates"]
        keep_ids = [item["id"] for item in incoming if "id" in item]
        AssessmentQuestionCandidate.objects.filter(assessment=assessment).exclude(
            id__in=keep_ids
        ).delete()
        confirmed = []
        for item in incoming:
            defaults = {
                "extracted_text": item["extracted_text"],
                "proposed_max_score": item["proposed_max_score"],
                "proposed_model_answer": item["proposed_model_answer"],
                "status": AssessmentQuestionCandidate.Status.CONFIRMED,
            }
            candidate_id = item.get("id")
            if candidate_id:
                candidate = AssessmentQuestionCandidate.objects.filter(
                    assessment=assessment, id=candidate_id
                ).first()
                if candidate is None:
                    candidate = AssessmentQuestionCandidate(
                        assessment=assessment, id=candidate_id, order=item["order"]
                    )
                candidate.order = item["order"]
                for field, value in defaults.items():
                    setattr(candidate, field, value)
                candidate.save()
            else:
                candidate, _ = AssessmentQuestionCandidate.objects.update_or_create(
                    assessment=assessment,
                    order=item["order"],
                    defaults=defaults,
                )
            Question.objects.update_or_create(
                assessment=assessment,
                order=item["order"],
                defaults={
                    "text": item["extracted_text"],
                    "max_score": item["proposed_max_score"],
                    "model_answer": item["proposed_model_answer"],
                },
            )
            confirmed.append(candidate)
        return confirmed
