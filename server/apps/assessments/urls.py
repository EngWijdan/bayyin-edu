from django.urls import path

from .views import (
    AssessmentDetailView,
    AssessmentListCreateView,
    AssessmentQuestionDetailView,
    AssessmentQuestionListCreateView,
    SubmissionAnswersView,
    SubmissionDetailView,
    SubmissionListCreateView,
)

urlpatterns = [
    path("assessments/", AssessmentListCreateView.as_view(), name="assessment-list-create"),
    path(
        "assessments/<uuid:assessment_id>/",
        AssessmentDetailView.as_view(),
        name="assessment-detail",
    ),
    path(
        "assessments/<uuid:assessment_id>/questions/",
        AssessmentQuestionListCreateView.as_view(),
        name="assessment-question-list-create",
    ),
    path(
        "assessments/<uuid:assessment_id>/questions/<uuid:question_id>/",
        AssessmentQuestionDetailView.as_view(),
        name="assessment-question-detail",
    ),
    path(
        "assessments/<uuid:assessment_id>/submissions/",
        SubmissionListCreateView.as_view(),
        name="assessment-submission-list-create",
    ),
    path(
        "assessments/<uuid:assessment_id>/submissions/<uuid:submission_id>/",
        SubmissionDetailView.as_view(),
        name="assessment-submission-detail",
    ),
    path(
        "assessments/<uuid:assessment_id>/submissions/<uuid:submission_id>/answers/",
        SubmissionAnswersView.as_view(),
        name="assessment-submission-answers",
    ),
]
