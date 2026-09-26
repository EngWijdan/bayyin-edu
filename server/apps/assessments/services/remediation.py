"""Generate one remediation plan for a student group on an assessment.

Views talk only to `generate_remediation_plan`. Gemini lives behind
`RemediationProvider` so tests inject a fake without a network call.
Student names, codes, files, and teacher identity never enter the payload.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from decimal import Decimal
from typing import Protocol

from django.utils import timezone

from apps.assessments.models import Assessment, RemediationPlan
from apps.assessments.services.class_insights import (
    GROUP_FOUNDATION,
    GROUP_PRACTICE,
    GROUP_READY,
    _misconceptions,
    _question_gaps,
    build_class_insights,
)
from apps.assessments.services.evaluation import normalize_locale
from apps.assessments.services.results import ZERO

logger = logging.getLogger(__name__)

GENERIC_FAILURE = "تعذر إنشاء الخطة."
INVALID_GROUP = "المجموعة غير صالحة."
ALLOWED_GROUPS = frozenset(
    {GROUP_FOUNDATION, GROUP_PRACTICE, GROUP_READY}
)
MAX_GAP_QUESTIONS = 8

GROUP_FOCUS = {
    GROUP_FOUNDATION: (
        "Foundation: rebuild core concepts, simplify the skill, use guided "
        "examples, and keep activities short."
    ),
    GROUP_PRACTICE: (
        "Practice: extra drills, address common errors, vary the questions, "
        "and grow independence."
    ),
    GROUP_READY: (
        "Ready: these students are relatively strong. Do not treat them as "
        "struggling. Focus on enrichment, harder challenges, deeper "
        "applications, and extension activities."
    ),
}


class RemediationError(Exception):
    """Raised when a plan cannot be produced. Views map it to a safe 400."""


@dataclass(frozen=True)
class RemediationQuestionContext:
    question_order: int
    question_text: str
    model_answer: str
    max_score: Decimal
    partial_count: int
    incorrect_count: int
    gap_count: int
    gap_percentage: Decimal | None


@dataclass(frozen=True)
class RemediationMisconception:
    text: str
    count: int


@dataclass(frozen=True)
class RemediationRequest:
    """Academic payload only. No student identity, files, or teacher names."""

    locale: str
    subject: str
    grade: str
    assessment_title: str
    group: str
    group_size: int
    percentage_min: Decimal
    percentage_max: Decimal
    percentage_average: Decimal
    highest_gap_questions: tuple[RemediationQuestionContext, ...]
    misconceptions: tuple[RemediationMisconception, ...]
    focus: str


@dataclass(frozen=True)
class RemediationDraft:
    title: str
    summary: str
    objectives: list[str]
    activities: list[dict]
    teacher_guidance: str
    model_name: str


@dataclass(frozen=True)
class RemediationGenerateResult:
    group_empty: bool
    group: str
    plan: RemediationPlan | None


class RemediationProvider(Protocol):
    def complete(self, request: RemediationRequest) -> dict: ...

    @property
    def model_name(self) -> str: ...


def get_remediation_provider() -> RemediationProvider:
    from .gemini import GeminiRemediationProvider

    return GeminiRemediationProvider()


def _members_for(insights, group: str):
    if group == GROUP_FOUNDATION:
        return insights.groups.foundation
    if group == GROUP_PRACTICE:
        return insights.groups.practice
    return insights.groups.ready


def _member_submissions(assessment: Assessment, members) -> list:
    member_ids = {member.student_id for member in members}
    return [
        submission
        for submission in assessment.submissions.select_related("student").prefetch_related(
            "answers__evaluation"
        )
        if submission.student_id in member_ids
    ]


def _gap_questions(assessment: Assessment, submissions) -> tuple[RemediationQuestionContext, ...]:
    questions = list(assessment.questions.all())
    by_id = {question.id: question for question in questions}
    items: list[RemediationQuestionContext] = []
    for gap in _question_gaps(questions, submissions):
        if gap.gap_count <= 0:
            continue
        if len(items) >= MAX_GAP_QUESTIONS:
            break
        question = by_id.get(gap.question_id)
        items.append(
            RemediationQuestionContext(
                question_order=gap.question_order,
                question_text=gap.question_text,
                model_answer=question.model_answer if question is not None else "",
                max_score=gap.max_score,
                partial_count=gap.partial_count,
                incorrect_count=gap.incorrect_count,
                gap_count=gap.gap_count,
                gap_percentage=gap.gap_percentage,
            )
        )
    return tuple(items)


def build_remediation_request(
    assessment: Assessment, group: str, locale: str | None = None
) -> RemediationRequest | None:
    """None when the group has no complete-result students."""
    normalized = group.strip().lower()
    if normalized not in ALLOWED_GROUPS:
        raise RemediationError(INVALID_GROUP)
    insights = build_class_insights(assessment)
    members = _members_for(insights, normalized)
    if not members:
        return None
    member_submissions = _member_submissions(assessment, members)
    percentages = [member.percentage for member in members]
    classroom = assessment.classroom
    return RemediationRequest(
        locale=normalize_locale(locale),
        subject=classroom.subject,
        grade=classroom.grade,
        assessment_title=assessment.title,
        group=normalized,
        group_size=len(members),
        percentage_min=min(percentages),
        percentage_max=max(percentages),
        percentage_average=(
            sum(percentages, ZERO) / Decimal(len(percentages))
        ).quantize(Decimal("0.01")),
        highest_gap_questions=_gap_questions(assessment, member_submissions),
        misconceptions=tuple(
            RemediationMisconception(text=item.text, count=item.count)
            for item in _misconceptions(member_submissions)
        ),
        focus=GROUP_FOCUS[normalized],
    )


def _as_text(value) -> str:
    text = str(value or "").strip()
    if not text:
        raise RemediationError(GENERIC_FAILURE)
    return text


def _parse_activity(raw) -> dict:
    if not isinstance(raw, dict):
        raise RemediationError(GENERIC_FAILURE)
    duration = raw.get("duration_minutes")
    if duration is None or duration == "":
        minutes = None
    else:
        try:
            minutes = int(duration)
        except (TypeError, ValueError) as exc:
            raise RemediationError(GENERIC_FAILURE) from exc
        if minutes < 1:
            raise RemediationError(GENERIC_FAILURE)
    return {
        "title": _as_text(raw.get("title")),
        "description": _as_text(raw.get("description")),
        "duration_minutes": minutes,
    }


def parse_provider_payload(raw: dict) -> RemediationDraft:
    """Backend-side contract. A schema on the wire is not trusted alone."""
    if not isinstance(raw, dict):
        raise RemediationError(GENERIC_FAILURE)
    objectives_raw = raw.get("objectives")
    activities_raw = raw.get("activities")
    if not isinstance(objectives_raw, list) or not objectives_raw:
        raise RemediationError(GENERIC_FAILURE)
    if not isinstance(activities_raw, list) or not activities_raw:
        raise RemediationError(GENERIC_FAILURE)
    objectives = [_as_text(item) for item in objectives_raw]
    activities = [_parse_activity(item) for item in activities_raw]
    return RemediationDraft(
        title=_as_text(raw.get("title"))[:200],
        summary=_as_text(raw.get("summary")),
        objectives=objectives,
        activities=activities,
        teacher_guidance=_as_text(raw.get("teacher_guidance")),
        model_name="",
    )


def generate_remediation_plan(
    assessment: Assessment,
    group: str,
    provider: RemediationProvider | None = None,
    locale: str | None = None,
) -> RemediationGenerateResult:
    request = build_remediation_request(assessment, group, locale=locale)
    if request is None:
        return RemediationGenerateResult(
            group_empty=True, group=group.strip().lower(), plan=None
        )
    try:
        active = provider or get_remediation_provider()
        raw = active.complete(request)
        draft = parse_provider_payload(raw)
    except RemediationError:
        raise
    except Exception:
        logger.exception(
            "Remediation provider failed for assessment %s group %s",
            assessment.id,
            request.group,
        )
        raise RemediationError(GENERIC_FAILURE) from None
    now = timezone.now()
    plan, _ = RemediationPlan.objects.update_or_create(
        assessment=assessment,
        group=request.group,
        defaults={
            "status": RemediationPlan.Status.COMPLETED,
            "title": draft.title,
            "summary": draft.summary,
            "objectives": draft.objectives,
            "activities": draft.activities,
            "teacher_guidance": draft.teacher_guidance,
            "model_name": active.model_name,
            "generated_at": now,
        },
    )
    return RemediationGenerateResult(
        group_empty=False, group=request.group, plan=plan
    )
