"""Class-level insights derived from current evaluation rows.

Nothing is stored: the payload is rebuilt from Classroom students,
Submissions, and AnswerEvaluation so a re-grade cannot leave a stale
snapshot. Gemini is not called here.
"""

from __future__ import annotations

from collections import Counter
from dataclasses import dataclass
from decimal import Decimal

from apps.assessments.models import AnswerEvaluation, Assessment
from apps.assessments.services.results import (
    HUNDRED,
    ZERO,
    _evaluation_of,
    build_submission_result,
)


FOUNDATION_BELOW = Decimal("60")
READY_AT_OR_ABOVE = Decimal("80")

GROUP_FOUNDATION = "foundation"
GROUP_PRACTICE = "practice"
GROUP_READY = "ready"

PENDING_INCOMPLETE_EVALUATION = "incomplete evaluation"
PENDING_NO_QUESTIONS = "no questions"


@dataclass(frozen=True)
class ClassSummary:
    total_students_in_class: int
    students_with_submission: int
    students_without_submission: int
    complete_results: int
    incomplete_results: int
    average_percentage: Decimal | None


@dataclass(frozen=True)
class ClassQuestionGap:
    question_id: object
    question_order: int
    question_text: str
    max_score: Decimal
    evaluated_students: int
    correct_count: int
    partial_count: int
    incorrect_count: int
    gap_count: int
    gap_percentage: Decimal | None


@dataclass(frozen=True)
class MisconceptionCount:
    text: str
    count: int


@dataclass(frozen=True)
class GroupedStudent:
    student_id: object
    display_name: str
    student_code: str
    percentage: Decimal
    group: str


@dataclass(frozen=True)
class PendingStudent:
    student_id: object
    display_name: str
    student_code: str
    reason: str


@dataclass(frozen=True)
class ClassGroups:
    foundation: tuple[GroupedStudent, ...]
    practice: tuple[GroupedStudent, ...]
    ready: tuple[GroupedStudent, ...]


@dataclass(frozen=True)
class ClassInsights:
    summary: ClassSummary
    question_gaps: tuple[ClassQuestionGap, ...]
    misconceptions: tuple[MisconceptionCount, ...]
    groups: ClassGroups
    pending_students: tuple[PendingStudent, ...]


def assign_group(percentage: Decimal) -> str:
    """MVP bands live here so Flutter never hardcodes the cut-offs."""
    if percentage < FOUNDATION_BELOW:
        return GROUP_FOUNDATION
    if percentage < READY_AT_OR_ABOVE:
        return GROUP_PRACTICE
    return GROUP_READY


def _gap_percentage(gap_count: int, evaluated: int) -> Decimal | None:
    if evaluated == 0:
        return None
    return (Decimal(gap_count) / Decimal(evaluated) * HUNDRED).quantize(
        Decimal("0.01")
    )


def _average(percentages: list[Decimal]) -> Decimal | None:
    if not percentages:
        return None
    total = sum(percentages, ZERO)
    return (total / Decimal(len(percentages))).quantize(Decimal("0.01"))


def _student_member(student, percentage: Decimal, group: str) -> GroupedStudent:
    return GroupedStudent(
        student_id=student.id,
        display_name=student.display_name,
        student_code=student.internal_code,
        percentage=percentage,
        group=group,
    )


def _pending_member(
    student, reason: str = PENDING_INCOMPLETE_EVALUATION
) -> PendingStudent:
    return PendingStudent(
        student_id=student.id,
        display_name=student.display_name,
        student_code=student.internal_code,
        reason=reason,
    )


def _question_gaps(questions, submissions) -> tuple[ClassQuestionGap, ...]:
    gaps: list[ClassQuestionGap] = []
    for question in questions:
        correct = partial = incorrect = 0
        for submission in submissions:
            answers = {answer.question_id: answer for answer in submission.answers.all()}
            evaluation = _evaluation_of(answers.get(question.id))
            if evaluation is None:
                continue
            if evaluation.status == AnswerEvaluation.Status.CORRECT:
                correct += 1
            elif evaluation.status == AnswerEvaluation.Status.PARTIAL:
                partial += 1
            elif evaluation.status == AnswerEvaluation.Status.INCORRECT:
                incorrect += 1
        evaluated = correct + partial + incorrect
        gap_count = partial + incorrect
        gaps.append(
            ClassQuestionGap(
                question_id=question.id,
                question_order=question.order,
                question_text=question.text,
                max_score=question.max_score,
                evaluated_students=evaluated,
                correct_count=correct,
                partial_count=partial,
                incorrect_count=incorrect,
                gap_count=gap_count,
                gap_percentage=_gap_percentage(gap_count, evaluated),
            )
        )
    gaps.sort(
        key=lambda gap: (
            gap.gap_percentage is None,
            -(gap.gap_percentage or ZERO),
            gap.question_order,
        )
    )
    return tuple(gaps)


def _misconceptions(submissions) -> tuple[MisconceptionCount, ...]:
    counts: Counter[str] = Counter()
    for submission in submissions:
        for answer in submission.answers.all():
            evaluation = _evaluation_of(answer)
            if evaluation is None:
                continue
            text = evaluation.misconception.strip()
            if text:
                counts[text] += 1
    ranked = sorted(counts.items(), key=lambda item: (-item[1], item[0]))
    return tuple(MisconceptionCount(text=text, count=count) for text, count in ranked)


def build_class_insights(assessment: Assessment) -> ClassInsights:
    questions = list(assessment.questions.all())
    students = list(assessment.classroom.students.all())
    submissions = list(
        assessment.submissions.select_related("student").prefetch_related(
            "answers__evaluation"
        )
    )
    complete: list[tuple[object, Decimal]] = []
    pending: list[PendingStudent] = []
    for submission in submissions:
        result = build_submission_result(submission)
        if result.is_complete:
            complete.append((submission.student, result.percentage))
        else:
            reason = (
                PENDING_NO_QUESTIONS
                if not result.is_evaluable
                else PENDING_INCOMPLETE_EVALUATION
            )
            pending.append(_pending_member(submission.student, reason))
    pending.sort(key=lambda item: item.student_code)


    grouped = {GROUP_FOUNDATION: [], GROUP_PRACTICE: [], GROUP_READY: []}
    for student, percentage in complete:
        group = assign_group(percentage)
        grouped[group].append(_student_member(student, percentage, group))
    for members in grouped.values():
        members.sort(key=lambda item: (item.percentage, item.student_code))

    complete_count = len(complete)
    with_submission = len(submissions)
    total = len(students)
    return ClassInsights(
        summary=ClassSummary(
            total_students_in_class=total,
            students_with_submission=with_submission,
            students_without_submission=total - with_submission,
            complete_results=complete_count,
            incomplete_results=len(pending),
            average_percentage=_average([percentage for _, percentage in complete]),
        ),
        question_gaps=_question_gaps(questions, submissions),
        misconceptions=_misconceptions(submissions),
        groups=ClassGroups(
            foundation=tuple(grouped[GROUP_FOUNDATION]),
            practice=tuple(grouped[GROUP_PRACTICE]),
            ready=tuple(grouped[GROUP_READY]),
        ),
        pending_students=tuple(pending),
    )
