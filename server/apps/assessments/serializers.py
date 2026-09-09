from decimal import Decimal

from django.db import transaction
from rest_framework import serializers

from apps.classrooms.models import Classroom, Student

from .models import Assessment, Question, Submission, SubmissionAnswer


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
        )
        read_only_fields = ("id", "created_at")

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
        texts = {
            answer.question_id: answer.answer_text for answer in submission.answers.all()
        }
        return [
            {
                "question_id": str(question.id),
                "order": question.order,
                "text": question.text,
                "max_score": question.max_score,
                "answer_text": texts.get(question.id, ""),
            }
            for question in submission.assessment.questions.all()
        ]


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
            SubmissionAnswer.objects.update_or_create(
                submission=submission,
                question_id=entry["question_id"],
                defaults={"answer_text": entry["answer_text"]},
            )
        return submission
