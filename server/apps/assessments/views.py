import logging

from django.conf import settings
from django.http import FileResponse
from django.shortcuts import get_object_or_404
from django.db import transaction
from rest_framework import status
from rest_framework.exceptions import ValidationError
from rest_framework.parsers import FormParser, MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.permissions import (
    IsActiveManager,
    IsActiveSchoolMember,
    active_profile,
)

from .models import (
    AnswerEvaluation,
    Assessment,
    AttachmentOcrResult,
    OcrAnswerCandidate,
)
from .serializers import (
    AnswerBulkWriteSerializer,
    AnswerEvaluationSerializer,
    AssessmentDetailSerializer,
    AssessmentQuestionCandidateSerializer,
    AssessmentSerializer,
    AssessmentSourceAttachmentSerializer,
    ClassInsightsSerializer,
    AttachmentOcrResultSerializer,
    ManagerInsightsSerializer,
    OcrMappingSerializer,
    QuestionCandidateConfirmSerializer,
    QuestionSerializer,
    RemediationGenerateSerializer,
    RemediationPlanSerializer,
    SubmissionAttachmentSerializer,
    SubmissionDetailSerializer,
    SubmissionResultSerializer,
    SubmissionSerializer,
)
from .services.answer_mapping import (
    NoExtractedTextError,
    collect_completed_ocr,
    map_ocr_text_to_questions,
)
from .services.class_insights import build_class_insights
from .services.manager_insights import build_manager_insights
from .services.evaluation import (
    GENERIC_FAILURE,
    NO_CONFIRMED_ANSWERS,
    EvaluationError,
    evaluate_answer,
    evaluate_answers,
    locale_from_request_data,
)
from .services.remediation import (
    INVALID_GROUP,
    ALLOWED_GROUPS,
    RemediationError,
    generate_remediation_plan,
)
from .services.ocr import run_ocr
from .services.question_extraction import (
    QuestionExtractionError,
    QuestionExtractionService,
    default_extraction_provider,
)
from .services.results import build_submission_result

logger = logging.getLogger(__name__)


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
    _STATUS_FILTERS = {"active", "archived", "all"}

    def get(self, request):
        assessments = self.listed_assessments(request)
        return Response(
            AssessmentSerializer(
                assessments, many=True, context=self.serializer_context(request)
            ).data
        )

    def listed_assessments(self, request):
        queryset = self.visible_assessments(request)
        status_filter = request.query_params.get("status", "active")
        if status_filter not in self._STATUS_FILTERS:
            raise ValidationError({"status": "Use active, archived, or all."})
        if status_filter == "archived":
            return queryset.archived()
        if status_filter == "all":
            return queryset
        return queryset.active()

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

    def delete(self, request, assessment_id):
        assessment = self.get_assessment(request, assessment_id)
        assessment.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


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
            ).prefetch_related("answers__evaluation", "assessment__questions"),
            id=submission_id,
        )
        return assessment, submission

    def get_answer(self, request, assessment_id, submission_id, answer_id):
        _, submission = self.get_submission(request, assessment_id, submission_id)
        return get_object_or_404(
            submission.answers.select_related(
                "question", "submission__assessment__classroom"
            ),
            id=answer_id,
        )


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
        _, submission = self.get_submission(request, assessment_id, submission_id)
        serializer = AnswerBulkWriteSerializer(
            data=request.data, context={"submission": submission}
        )
        serializer.is_valid(raise_exception=True)
        serializer.save()
        assessment, submission = self.get_submission(
            request, assessment_id, submission_id
        )
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


class SubmissionAttachmentOcrView(ScopedAttachmentView):
    """GET returns the current result (404 if OCR has never run). POST runs
    or re-runs OCR on the same row and returns it. The engine is synchronous
    in the MVP; status is still persisted so a worker can take this over."""

    def get(self, request, assessment_id, submission_id, attachment_id):
        attachment = self.get_attachment(
            request, assessment_id, submission_id, attachment_id
        )
        result = AttachmentOcrResult.objects.filter(attachment=attachment).first()
        if result is None:
            return Response(status=status.HTTP_404_NOT_FOUND)
        return Response(AttachmentOcrResultSerializer(result).data)

    def post(self, request, assessment_id, submission_id, attachment_id):
        attachment = self.get_attachment(
            request, assessment_id, submission_id, attachment_id
        )
        result = run_ocr(attachment)
        return Response(AttachmentOcrResultSerializer(result).data)


def _mapping_payload(submission, candidates, incomplete_ocr):
    answers = {}
    for answer in submission.answers.all():
        answers[answer.question_id] = answer.answer_text
        answers[str(answer.question_id)] = answer.answer_text
    return OcrMappingSerializer(
        {"candidates": candidates, "incomplete_ocr": incomplete_ocr},
        context={"answers_by_question": answers},
    ).data


class SubmissionOcrMappingView(ScopedSubmissionView):
    def get(self, request, assessment_id, submission_id):
        _, submission = self.get_submission(request, assessment_id, submission_id)
        _, incomplete = collect_completed_ocr(submission)
        candidates = submission.ocr_candidates.select_related("question")
        return Response(_mapping_payload(submission, candidates, incomplete))

    def post(self, request, assessment_id, submission_id):
        _, submission = self.get_submission(request, assessment_id, submission_id)
        try:
            outcome = map_ocr_text_to_questions(submission)
        except NoExtractedTextError as exc:
            raise ValidationError({"detail": str(exc)}) from exc
        return Response(
            _mapping_payload(submission, outcome.candidates, outcome.incomplete_ocr)
        )


class SubmissionOcrMappingConfirmView(ScopedSubmissionView):
    def put(self, request, assessment_id, submission_id):
        _, submission = self.get_submission(request, assessment_id, submission_id)
        serializer = AnswerBulkWriteSerializer(
            data=request.data, context={"submission": submission}
        )
        serializer.is_valid(raise_exception=True)
        with transaction.atomic():
            serializer.save()
            question_ids = [
                entry["question_id"] for entry in serializer.validated_data["answers"]
            ]
            OcrAnswerCandidate.objects.filter(
                submission=submission, question_id__in=question_ids
            ).update(status=OcrAnswerCandidate.Status.CONFIRMED)
        _, submission = self.get_submission(request, assessment_id, submission_id)
        _, incomplete = collect_completed_ocr(submission)
        candidates = submission.ocr_candidates.select_related("question")
        return Response(_mapping_payload(submission, candidates, incomplete))


class SubmissionAnswerEvaluateView(ScopedSubmissionView):
    """GET the current grade for one confirmed answer, or POST to (re)grade it."""

    def get(self, request, assessment_id, submission_id, answer_id):
        answer = self.get_answer(request, assessment_id, submission_id, answer_id)
        try:
            evaluation = answer.evaluation
        except AnswerEvaluation.DoesNotExist:
            return Response(status=status.HTTP_404_NOT_FOUND)
        return Response(AnswerEvaluationSerializer(evaluation).data)

    def post(self, request, assessment_id, submission_id, answer_id):
        answer = self.get_answer(request, assessment_id, submission_id, answer_id)
        try:
            evaluation = evaluate_answer(
                answer, locale=locale_from_request_data(request.data)
            )
        except EvaluationError as exc:
            raise ValidationError({"detail": str(exc)}) from exc
        return Response(AnswerEvaluationSerializer(evaluation).data)


class SubmissionEvaluateView(ScopedSubmissionView):
    """Grades every confirmed SubmissionAnswer on the sheet. Questions the
    teacher has not saved are skipped; one failure does not roll back the rest."""

    def post(self, request, assessment_id, submission_id):
        assessment, submission = self.get_submission(
            request, assessment_id, submission_id
        )
        answers = list(
            submission.answers.select_related(
                "question", "submission__assessment__classroom"
            )
        )
        if not answers:
            raise ValidationError({"detail": NO_CONFIRMED_ANSWERS})
        locale = locale_from_request_data(request.data)
        if settings.DEBUG:
            answered_question_ids = {answer.question_id for answer in answers}
            for question in assessment.questions.all():
                if question.id not in answered_question_ids:
                    logger.info(
                        "evaluation result question_order=%s outcome=skipped",
                        question.order,
                    )
        failed = evaluate_answers(answers, locale=locale)
        if failed:
            logger.error(
                "Bulk evaluation incomplete submission_id=%s failed=%s total=%s",
                submission.id,
                failed,
                len(answers),
            )
        if failed == len(answers):
            raise ValidationError({"detail": GENERIC_FAILURE})
        _, submission = self.get_submission(request, assessment_id, submission_id)
        payload = SubmissionDetailSerializer(
            submission, context={"assessment": assessment}
        ).data
        payload["failed_count"] = failed
        return Response(payload)


class ManagerInsightsView(APIView):
    """School-wide operational overview. Managers only; no student roster."""

    permission_classes = (IsActiveManager,)

    def get(self, request):
        return Response(ManagerInsightsSerializer(build_manager_insights()).data)


class AssessmentClassInsightsView(ScopedAssessmentView):
    """Class summary, gaps, misconceptions, and groups for one assessment."""

    def get(self, request, assessment_id):
        assessment = self.get_assessment(request, assessment_id)
        return Response(
            ClassInsightsSerializer(build_class_insights(assessment)).data
        )


class RemediationPlanListView(ScopedAssessmentView):
    """Stored plans only. GET does not call Gemini or refresh stale rows."""

    def get(self, request, assessment_id):
        assessment = self.get_assessment(request, assessment_id)
        plans = assessment.remediation_plans.order_by("group")
        return Response(RemediationPlanSerializer(plans, many=True).data)


class RemediationPlanGenerateView(ScopedAssessmentView):
    """Create or replace the single plan row for one group."""

    def post(self, request, assessment_id, group):
        assessment = self.get_assessment(request, assessment_id)
        key = str(group or "").strip().lower()
        if key not in ALLOWED_GROUPS:
            raise ValidationError({"detail": INVALID_GROUP})
        try:
            result = generate_remediation_plan(
                assessment,
                key,
                locale=locale_from_request_data(request.data),
            )
        except RemediationError as exc:
            raise ValidationError({"detail": str(exc)}) from exc
        return Response(RemediationGenerateSerializer(result).data)


class SubmissionResultView(ScopedSubmissionView):
    """Totals and gaps derived from the current AnswerEvaluation rows."""

    def get(self, request, assessment_id, submission_id):
        _, submission = self.get_submission(request, assessment_id, submission_id)
        return Response(
            SubmissionResultSerializer(build_submission_result(submission)).data
        )


class AssessmentSourceAttachmentListCreateView(ScopedAssessmentView):
    parser_classes = (MultiPartParser, FormParser)

    def get(self, request, assessment_id):
        assessment = self.get_assessment(request, assessment_id)
        attachments = assessment.source_attachments.all()
        return Response(
            AssessmentSourceAttachmentSerializer(attachments, many=True).data
        )

    def post(self, request, assessment_id):
        assessment = self.get_assessment(request, assessment_id)
        serializer = AssessmentSourceAttachmentSerializer(
            data=request.data,
            context={
                "assessment": assessment,
                "profile": active_profile(request),
            },
        )
        serializer.is_valid(raise_exception=True)
        attachment = serializer.save()
        return Response(
            AssessmentSourceAttachmentSerializer(attachment).data,
            status=status.HTTP_201_CREATED,
        )


class AssessmentSourceAttachmentDownloadView(ScopedAssessmentView):
    def get(self, request, assessment_id, attachment_id):
        assessment = self.get_assessment(request, assessment_id)
        attachment = get_object_or_404(
            assessment.source_attachments, id=attachment_id
        )
        return FileResponse(
            attachment.file.open("rb"),
            content_type=attachment.content_type,
            as_attachment=True,
            filename=attachment.original_filename,
        )


class AssessmentExtractQuestionsView(ScopedAssessmentView):
    def post(self, request, assessment_id):
        assessment = self.get_assessment(request, assessment_id)
        service = QuestionExtractionService(provider=default_extraction_provider())
        try:
            candidates = service.extract_from_assessment(assessment)
        except QuestionExtractionError as exc:
            raise ValidationError({"detail": str(exc)}) from exc
        return Response(
            AssessmentQuestionCandidateSerializer(candidates, many=True).data
        )


class AssessmentQuestionCandidateListView(ScopedAssessmentView):
    def get(self, request, assessment_id):
        assessment = self.get_assessment(request, assessment_id)
        candidates = assessment.question_candidates.order_by("order")
        return Response(
            AssessmentQuestionCandidateSerializer(candidates, many=True).data
        )


class AssessmentQuestionCandidateDetailView(ScopedAssessmentView):
    def get_candidate(self, request, assessment_id, candidate_id):
        assessment = self.get_assessment(request, assessment_id)
        return assessment, get_object_or_404(
            assessment.question_candidates, id=candidate_id
        )

    def patch(self, request, assessment_id, candidate_id):
        assessment, candidate = self.get_candidate(
            request, assessment_id, candidate_id
        )
        serializer = AssessmentQuestionCandidateSerializer(
            candidate,
            data=request.data,
            partial=True,
            context={"assessment": assessment},
        )
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(serializer.data)

    def delete(self, request, assessment_id, candidate_id):
        _, candidate = self.get_candidate(request, assessment_id, candidate_id)
        candidate.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


class AssessmentQuestionCandidateConfirmView(ScopedAssessmentView):
    def put(self, request, assessment_id):
        assessment = self.get_assessment(request, assessment_id)
        serializer = QuestionCandidateConfirmSerializer(
            data=request.data, context={"assessment": assessment}
        )
        serializer.is_valid(raise_exception=True)
        confirmed = serializer.save()
        assessment = self.get_assessment(request, assessment_id)
        return Response(
            {
                "candidates": AssessmentQuestionCandidateSerializer(
                    confirmed, many=True
                ).data,
                "assessment": AssessmentDetailSerializer(
                    assessment, context=self.serializer_context(request)
                ).data,
            }
        )
