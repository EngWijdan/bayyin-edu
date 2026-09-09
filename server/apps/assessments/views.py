from django.http import FileResponse
from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.parsers import FormParser, MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.permissions import IsActiveSchoolMember, active_profile

from .models import Assessment
from .serializers import (
    AnswerBulkWriteSerializer,
    AssessmentDetailSerializer,
    AssessmentSerializer,
    QuestionSerializer,
    SubmissionAttachmentSerializer,
    SubmissionDetailSerializer,
    SubmissionSerializer,
)


class ScopedAssessmentView(APIView):
    """Teachers author their own assessments, so reads and writes share one
    permission and the row-level limit comes from the scoped queryset."""

    permission_classes = (IsActiveSchoolMember,)

    def visible_assessments(self, request):
        return (
            Assessment.objects.visible_to(active_profile(request))
            .select_related("classroom")
            .prefetch_related("questions")
        )

    def get_assessment(self, request, assessment_id):
        # Scoping the lookup means another teacher's assessment is a 404, not a
        # 403, so the API never confirms that the id exists.
        return get_object_or_404(self.visible_assessments(request), id=assessment_id)

    def serializer_context(self, request):
        return {"profile": active_profile(request)}


class AssessmentListCreateView(ScopedAssessmentView):
    def get(self, request):
        assessments = self.visible_assessments(request)
        return Response(
            AssessmentSerializer(
                assessments, many=True, context=self.serializer_context(request)
            ).data
        )

    def post(self, request):
        context = self.serializer_context(request)
        serializer = AssessmentSerializer(data=request.data, context=context)
        serializer.is_valid(raise_exception=True)
        assessment = serializer.save(created_by=active_profile(request))
        return Response(
            AssessmentDetailSerializer(assessment, context=context).data,
            status=status.HTTP_201_CREATED,
        )


class AssessmentDetailView(ScopedAssessmentView):
    def get(self, request, assessment_id):
        assessment = self.get_assessment(request, assessment_id)
        return Response(
            AssessmentDetailSerializer(
                assessment, context=self.serializer_context(request)
            ).data
        )

    def patch(self, request, assessment_id):
        assessment = self.get_assessment(request, assessment_id)
        context = self.serializer_context(request)
        serializer = AssessmentDetailSerializer(
            assessment, data=request.data, partial=True, context=context
        )
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(serializer.data)


class AssessmentQuestionListCreateView(ScopedAssessmentView):
    def get(self, request, assessment_id):
        assessment = self.get_assessment(request, assessment_id)
        return Response(QuestionSerializer(assessment.questions.all(), many=True).data)

    def post(self, request, assessment_id):
        assessment = self.get_assessment(request, assessment_id)
        serializer = QuestionSerializer(
            data=request.data, context={"assessment": assessment}
        )
        serializer.is_valid(raise_exception=True)
        question = serializer.save()
        return Response(QuestionSerializer(question).data, status=status.HTTP_201_CREATED)


class AssessmentQuestionDetailView(ScopedAssessmentView):
    def get_question(self, request, assessment_id, question_id):
        assessment = self.get_assessment(request, assessment_id)
        return assessment, get_object_or_404(assessment.questions, id=question_id)

    def patch(self, request, assessment_id, question_id):
        assessment, question = self.get_question(request, assessment_id, question_id)
        serializer = QuestionSerializer(
            question,
            data=request.data,
            partial=True,
            context={"assessment": assessment},
        )
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(serializer.data)

    def delete(self, request, assessment_id, question_id):
        _, question = self.get_question(request, assessment_id, question_id)
        question.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


class ScopedSubmissionView(ScopedAssessmentView):
    """Submissions inherit the assessment's scope: an assessment the caller
    cannot see is already a 404, so everything under it is out of reach."""

    def get_submission(self, request, assessment_id, submission_id):
        assessment = self.get_assessment(request, assessment_id)
        submission = get_object_or_404(
            assessment.submissions.select_related(
                "student", "assessment"
            ).prefetch_related("answers"),
            id=submission_id,
        )
        return assessment, submission


class SubmissionListCreateView(ScopedSubmissionView):
    def get(self, request, assessment_id):
        assessment = self.get_assessment(request, assessment_id)
        submissions = assessment.submissions.select_related("student")
        return Response(SubmissionSerializer(submissions, many=True).data)

    def post(self, request, assessment_id):
        assessment = self.get_assessment(request, assessment_id)
        context = {"assessment": assessment}
        serializer = SubmissionSerializer(data=request.data, context=context)
        serializer.is_valid(raise_exception=True)
        submission = serializer.save(
            assessment=assessment, created_by=active_profile(request)
        )
        return Response(
            SubmissionDetailSerializer(submission, context=context).data,
            status=status.HTTP_201_CREATED,
        )


class SubmissionDetailView(ScopedSubmissionView):
    def get(self, request, assessment_id, submission_id):
        assessment, submission = self.get_submission(
            request, assessment_id, submission_id
        )
        return Response(
            SubmissionDetailSerializer(
                submission, context={"assessment": assessment}
            ).data
        )


class SubmissionAnswersView(ScopedSubmissionView):
    def put(self, request, assessment_id, submission_id):
        assessment, submission = self.get_submission(
            request, assessment_id, submission_id
        )
        serializer = AnswerBulkWriteSerializer(
            data=request.data, context={"submission": submission}
        )
        serializer.is_valid(raise_exception=True)
        serializer.save()
        submission.refresh_from_db()
        return Response(
            SubmissionDetailSerializer(
                submission, context={"assessment": assessment}
            ).data
        )


class SubmissionAttachmentListCreateView(ScopedSubmissionView):
    parser_classes = (MultiPartParser, FormParser)

    def get(self, request, assessment_id, submission_id):
        _, submission = self.get_submission(request, assessment_id, submission_id)
        attachments = submission.attachments.select_related("submission")
        return Response(SubmissionAttachmentSerializer(attachments, many=True).data)

    def post(self, request, assessment_id, submission_id):
        _, submission = self.get_submission(request, assessment_id, submission_id)
        # The submission comes from the URL and the uploader from the token, so
        # neither relationship can be forged through the request body.
        serializer = SubmissionAttachmentSerializer(
            data=request.data,
            context={"submission": submission, "profile": active_profile(request)},
        )
        serializer.is_valid(raise_exception=True)
        attachment = serializer.save()
        return Response(
            SubmissionAttachmentSerializer(attachment).data,
            status=status.HTTP_201_CREATED,
        )


class ScopedAttachmentView(ScopedSubmissionView):
    def get_attachment(self, request, assessment_id, submission_id, attachment_id):
        _, submission = self.get_submission(request, assessment_id, submission_id)
        # Looking the attachment up through the submission means an id that
        # belongs to a different submission is a 404.
        return get_object_or_404(submission.attachments, id=attachment_id)


class SubmissionAttachmentDetailView(ScopedAttachmentView):
    def delete(self, request, assessment_id, submission_id, attachment_id):
        attachment = self.get_attachment(
            request, assessment_id, submission_id, attachment_id
        )
        attachment.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


class SubmissionAttachmentDownloadView(ScopedAttachmentView):
    """Streams the stored file behind the same scope check as everything else,
    which is why MEDIA_ROOT is not exposed as static files."""

    def get(self, request, assessment_id, submission_id, attachment_id):
        attachment = self.get_attachment(
            request, assessment_id, submission_id, attachment_id
        )
        return FileResponse(
            attachment.file.open("rb"),
            content_type=attachment.content_type,
            as_attachment=True,
            filename=attachment.original_filename,
        )
