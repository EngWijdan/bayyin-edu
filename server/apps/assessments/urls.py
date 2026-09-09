from django.urls import path

from .views import (
    AssessmentDetailView,
    AssessmentListCreateView,
    AssessmentQuestionDetailView,
    AssessmentQuestionListCreateView,
    SubmissionAnswersView,
    SubmissionAttachmentDetailView,
    SubmissionAttachmentDownloadView,
    SubmissionAttachmentListCreateView,
    SubmissionDetailView,
    SubmissionListCreateView,
)

_SUBMISSION = "assessments/<uuid:assessment_id>/submissions/<uuid:submission_id>"

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
        f"{_SUBMISSION}/",
        SubmissionDetailView.as_view(),
        name="assessment-submission-detail",
    ),
    path(
        f"{_SUBMISSION}/answers/",
        SubmissionAnswersView.as_view(),
        name="assessment-submission-answers",
    ),
    path(
        f"{_SUBMISSION}/attachments/",
        SubmissionAttachmentListCreateView.as_view(),
        name="assessment-submission-attachment-list-create",
    ),
    path(
        f"{_SUBMISSION}/attachments/<uuid:attachment_id>/",
        SubmissionAttachmentDetailView.as_view(),
        name="assessment-submission-attachment-detail",
    ),
    path(
        f"{_SUBMISSION}/attachments/<uuid:attachment_id>/download/",
        SubmissionAttachmentDownloadView.as_view(),
        name="assessment-submission-attachment-download",
    ),
]
