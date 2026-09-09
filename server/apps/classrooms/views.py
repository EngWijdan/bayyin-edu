from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.permissions import IsActiveManager, IsActiveSchoolMember, active_profile

from .models import Classroom
from .serializers import ClassroomSerializer, StudentSerializer


class ScopedClassroomView(APIView):
    """Reads are open to any active member but scoped by role; writes stay manager-only."""

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
            .prefetch_related("students")
        )
        return Response(ClassroomSerializer(classrooms, many=True).data)

    def post(self, request):
        serializer = ClassroomSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        classroom = serializer.save()
        return Response(ClassroomSerializer(classroom).data, status=status.HTTP_201_CREATED)


class ClassroomStudentListCreateView(ScopedClassroomView):
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
