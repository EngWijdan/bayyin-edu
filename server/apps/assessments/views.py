from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.permissions import IsActiveSchoolMember, active_profile

from .models import Assessment
from .serializers import AssessmentDetailSerializer, AssessmentSerializer, QuestionSerializer


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
