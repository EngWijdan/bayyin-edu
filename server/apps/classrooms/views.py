from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.permissions import IsActiveManager, IsActiveSchoolMember, active_profile

from .models import Classroom
from .serializers import ClassroomSerializer, StudentSerializer


class ScopedClassroomView(APIView):
    """Reads are scoped by role. Creating or editing a classroom stays manager-only."""

    def get_permissions(self):
        if self.request.method in ("GET", "HEAD", "OPTIONS"):
            return [IsActiveSchoolMember()]
        return [IsActiveManager()]

    def visible_classrooms(self, request):
        return Classroom.objects.visible_to(active_profile(request))


class ClassroomListCreateView(ScopedClassroomView):
    def get(self, request):
        classrooms = (
            self.visible_classrooms(request)
            .select_related("teacher__user")
            .prefetch_related("students", "assessments")
        )
        return Response(ClassroomSerializer(classrooms, many=True).data)

    def post(self, request):
        serializer = ClassroomSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        classroom = serializer.save()
        return Response(self._serialized(classroom), status=status.HTTP_201_CREATED)

    def _serialized(self, classroom):
        classroom = (
            Classroom.objects.select_related("teacher__user")
            .prefetch_related("students", "assessments")
            .get(pk=classroom.pk)
        )
        return ClassroomSerializer(classroom).data


class ClassroomDetailView(ScopedClassroomView):
    def get(self, request, classroom_id):
        return Response(ClassroomSerializer(self._classroom(request, classroom_id)).data)

    def patch(self, request, classroom_id):
        classroom = self._classroom(request, classroom_id)
        serializer = ClassroomSerializer(classroom, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        classroom = serializer.save()
        classroom = (
            Classroom.objects.select_related("teacher__user")
            .prefetch_related("students", "assessments")
            .get(pk=classroom.pk)
        )
        return Response(ClassroomSerializer(classroom).data)

    def delete(self, request, classroom_id):
        classroom = self._classroom(request, classroom_id)
        classroom.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)

    def _classroom(self, request, classroom_id):
        return get_object_or_404(
            self.visible_classrooms(request)
            .select_related("teacher__user")
            .prefetch_related("students", "assessments"),
            id=classroom_id,
        )


class ClassroomStudentListCreateView(ScopedClassroomView):
    def get_permissions(self):
        # A teacher may add students to a classroom they can already see.
        # Another teacher's classroom still 404s via visible_classrooms().
        return [IsActiveSchoolMember()]

    def get(self, request, classroom_id):
        # Scoping the lookup means another teacher's classroom is a 404, not a 403,
        # so the API never confirms that the id exists.
        classroom = get_object_or_404(self.visible_classrooms(request), id=classroom_id)
        return Response(StudentSerializer(classroom.students.all(), many=True).data)

    def post(self, request, classroom_id):
        classroom = get_object_or_404(self.visible_classrooms(request), id=classroom_id)
        serializer = StudentSerializer(data=request.data, context={"classroom": classroom})
        serializer.is_valid(raise_exception=True)
        student = serializer.save(classroom=classroom)
        return Response(StudentSerializer(student).data, status=status.HTTP_201_CREATED)
