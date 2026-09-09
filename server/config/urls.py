from django.urls import include, path

urlpatterns = [
    path("api/v1/", include("apps.core.urls")),
    path("api/v1/", include("apps.accounts.urls")),
    path("api/v1/", include("apps.classrooms.urls")),
    path("api/v1/", include("apps.assessments.urls")),
]
