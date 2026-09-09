from decimal import Decimal

from rest_framework import serializers

from apps.classrooms.models import Classroom

from .models import Assessment, Question


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
