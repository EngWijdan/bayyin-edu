"""Derived assessment result for one submission.

Nothing is stored: totals, gaps, and misconceptions are read from the
current questions and their AnswerEvaluation rows so a stale snapshot cannot
outlive a re-grade or an edited answer.
"""

from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal

from apps.assessments.models import AnswerEvaluation, Submission


ZERO = Decimal("0.00")
HUNDRED = Decimal("100")
GAP_STATUSES = frozenset(
    {AnswerEvaluation.Status.PARTIAL, AnswerEvaluation.Status.INCORRECT}
)


@dataclass(frozen=True)
class QuestionGap:
    question_id: object
    question_order: int
    question_text: str
    status: str
    awarded_score: Decimal
    max_score: Decimal
    feedback: str
    misconception: str


@dataclass(frozen=True)
class SubmissionResult:
    is_evaluable: bool
    is_complete: bool
    awarded_score_total: Decimal
    max_score_total: Decimal
    percentage: Decimal
    evaluated_questions: int
    total_questions: int
    correct_count: int
    partial_count: int
    incorrect_count: int
    unevaluated_count: int
    gaps: tuple[QuestionGap, ...]
    misconceptions: tuple[str, ...]


def _evaluation_of(answer):
    if answer is None:
        return None
    try:
        return answer.evaluation
    except AnswerEvaluation.DoesNotExist:
        return None


def _percentage(awarded: Decimal, evaluated_max: Decimal) -> Decimal:
    """Share of the evaluated questions only, so unevaluated items are not zeros."""
    if evaluated_max <= 0:
        return ZERO
    return (awarded / evaluated_max * HUNDRED).quantize(Decimal("0.01"))


def build_submission_result(submission: Submission) -> SubmissionResult:
    questions = list(submission.assessment.questions.all())
    answers = {answer.question_id: answer for answer in submission.answers.all()}
    max_total = sum((question.max_score for question in questions), ZERO)
    awarded = ZERO
    evaluated_max = ZERO
    correct = partial = incorrect = 0
    gaps: list[QuestionGap] = []
    seen_misconceptions: list[str] = []
    seen_exact: set[str] = set()

    for question in questions:
        evaluation = _evaluation_of(answers.get(question.id))
        if evaluation is None:
            continue
        awarded += evaluation.awarded_score
        evaluated_max += question.max_score
        if evaluation.status == AnswerEvaluation.Status.CORRECT:
            correct += 1
        elif evaluation.status == AnswerEvaluation.Status.PARTIAL:
            partial += 1
        elif evaluation.status == AnswerEvaluation.Status.INCORRECT:
            incorrect += 1
        if evaluation.status in GAP_STATUSES:
            gaps.append(
                QuestionGap(
                    question_id=question.id,
                    question_order=question.order,
                    question_text=question.text,
                    status=evaluation.status,
                    awarded_score=evaluation.awarded_score,
                    max_score=question.max_score,
                    feedback=evaluation.feedback,
                    misconception=evaluation.misconception,
                )
            )
        misconception = evaluation.misconception.strip()
        if misconception and misconception not in seen_exact:
            seen_exact.add(misconception)
            seen_misconceptions.append(misconception)

    evaluated = correct + partial + incorrect
    total = len(questions)
    unevaluated = total - evaluated
    is_evaluable = total > 0
    return SubmissionResult(
        is_evaluable=is_evaluable,
        is_complete=is_evaluable and unevaluated == 0,
        awarded_score_total=awarded,
        max_score_total=max_total,
        percentage=_percentage(awarded, evaluated_max),
        evaluated_questions=evaluated,
        total_questions=total,
        correct_count=correct,
        partial_count=partial,
        incorrect_count=incorrect,
        unevaluated_count=unevaluated,
        gaps=tuple(gaps),
        misconceptions=tuple(seen_misconceptions),
    )
