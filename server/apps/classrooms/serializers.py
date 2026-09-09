from rest_framework import serializers

from apps.accounts.models import UserProfile

from .models import Classroom, Student


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
        queryset=UserProfile.objects.filter(
            role=UserProfile.Role.TEACHER,
            is_active=True,
            user__is_active=True,
        ),
        write_only=True,
    )
    teacher_id = serializers.IntegerField(source="teacher.user_id", read_only=True)
    teacher_name = serializers.SerializerMethodField()
    students_count = serializers.IntegerField(source="students.count", read_only=True)

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
        )
        read_only_fields = ("id", "is_active", "teacher_id", "teacher_name", "students_count")

    def get_teacher_name(self, classroom):
        return classroom.teacher.display_name
