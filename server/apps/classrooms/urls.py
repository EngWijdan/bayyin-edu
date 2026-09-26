from django.urls import path

from .views import ClassroomDetailView, ClassroomListCreateView, ClassroomStudentListCreateView

urlpatterns = [
    path("management/classrooms/", ClassroomListCreateView.as_view(), name="classroom-list-create"),
    path(
        "management/classrooms/<uuid:classroom_id>/",
        ClassroomDetailView.as_view(),
        name="classroom-detail",
    ),
    path(
        "management/classrooms/<uuid:classroom_id>/students/",
        ClassroomStudentListCreateView.as_view(),
        name="classroom-student-list-create",
    ),
]
