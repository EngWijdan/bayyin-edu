from django.db.models import Q
from rest_framework import serializers

from apps.accounts.models import UserProfile

from .models import Classroom, Student


def _active_teacher_queryset():
    return UserProfile.objects.filter(
        role=UserProfile.Role.TEACHER,
        is_active=True,
        user__is_active=True,
    ).select_related("user")


class StudentSerializer(serializers.ModelSerializer):
    class Meta:
        model = Student
        fields = ("id", "internal_code", "display_name", "is_active")
        read_only_fields = ("id", "is_active")

    def validate_internal_code(self, value):
        classroom = self.context.get("classroom")
        if classroom and classroom.students.filter(internal_code=value).exists():
            raise serializers.ValidationError("رمز الطالب مستخدم داخل هذا الصف.")
        return value


class ClassroomSerializer(serializers.ModelSerializer):
    teacher_profile_id = serializers.PrimaryKeyRelatedField(
        source="teacher",
        queryset=_active_teacher_queryset(),
    )
    teacher_id = serializers.IntegerField(source="teacher.user_id", read_only=True)
    teacher_name = serializers.SerializerMethodField()
    students_count = serializers.IntegerField(source="students.count", read_only=True)
    assessments_count = serializers.SerializerMethodField()

    class Meta:
        model = Classroom
        fields = (
            "id",
            "name",
            "grade",
            "subject",
            "academic_year",
            "is_active",
            "teacher_profile_id",
            "teacher_id",
            "teacher_name",
            "students_count",
            "assessments_count",
        )
        read_only_fields = (
            "id",
            "is_active",
            "teacher_id",
            "teacher_name",
            "students_count",
            "assessments_count",
        )

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        queryset = _active_teacher_queryset()
        if isinstance(self.instance, Classroom):
            queryset = UserProfile.objects.filter(
                Q(pk=self.instance.teacher_id) | Q(pk__in=queryset)
            ).select_related("user")
        self.fields["teacher_profile_id"].queryset = queryset

    def get_teacher_name(self, classroom):
        return classroom.teacher.display_name

    def get_assessments_count(self, classroom):
        return len(classroom.assessments.all())

    def validate(self, attrs):
        teacher = attrs.get("teacher", getattr(self.instance, "teacher", None))
        name = attrs.get("name", getattr(self.instance, "name", None))
        academic_year = attrs.get(
            "academic_year", getattr(self.instance, "academic_year", None)
        )
        if teacher and name and academic_year:
            clash = Classroom.objects.filter(
                teacher=teacher, name=name, academic_year=academic_year
            )
            if self.instance:
                clash = clash.exclude(pk=self.instance.pk)
            if clash.exists():
                raise serializers.ValidationError(
                    "يوجد صف بنفس الاسم والعام الدراسي عند هذا المعلم."
                )
        return attrs
