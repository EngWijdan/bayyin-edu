"""Grade one confirmed student answer.

Views talk only to `evaluate_answer`. The Gemini client lives behind
`EvaluationProvider` so a later swap does not leak into the API, and tests
can inject a fake provider without a network call.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation
from typing import NoReturn, Protocol

from django.conf import settings
from django.utils import timezone

from apps.assessments.models import AnswerEvaluation, SubmissionAnswer

logger = logging.getLogger(__name__)

GENERIC_FAILURE = "تعذر تقييم الإجابة."
NO_CONFIRMED_ANSWERS = "لا توجد إجابات مؤكدة للتقييم."
EMPTY_FEEDBACK = "لم يُدخل الطالب إجابة."
DETERMINISTIC_MODEL = "deterministic"

ALLOWED_STATUSES = frozenset(AnswerEvaluation.Status.values)
ALLOWED_LOCALES = frozenset({"ar", "en"})
DEFAULT_LOCALE = "ar"


class EvaluationError(Exception):
    """Raised when a grade cannot be produced. Views map it to a safe 400."""


@dataclass(frozen=True)
class EvaluationRequest:
    """Academic payload only. No student identity, files, or teacher names."""

    subject: str
    grade: str
    question: str
    model_answer: str
    max_score: Decimal
    student_answer: str
    locale: str = "ar"


@dataclass(frozen=True)
class EvaluationDraft:
    status: str
    awarded_score: Decimal
    feedback: str
    misconception: str
    model_name: str


class EvaluationProvider(Protocol):
    def complete(self, request: EvaluationRequest) -> dict: ...

    @property
    def model_name(self) -> str: ...


def normalize_locale(value) -> str:
    """Only `ar` and `en` are forwarded to the provider. Anything else is `ar`."""
    if value is None:
        return DEFAULT_LOCALE
    locale = str(value).strip().lower()
    if locale in ALLOWED_LOCALES:
        return locale
    return DEFAULT_LOCALE


def locale_from_request_data(data) -> str:
    if not isinstance(data, dict):
        return DEFAULT_LOCALE
    return normalize_locale(data.get("locale"))


def request_from_answer(
    answer: SubmissionAnswer, locale: str | None = None
) -> EvaluationRequest:
    classroom = answer.submission.assessment.classroom
    return EvaluationRequest(
        subject=classroom.subject,
        grade=classroom.grade,
        question=answer.question.text,
        model_answer=answer.question.model_answer,
        max_score=answer.question.max_score,
        student_answer=answer.answer_text,
        locale=normalize_locale(locale),
    )


def _reject_payload(reason: str, exc: BaseException | None = None) -> NoReturn:
    """Log the real validation failure; the client only ever sees GENERIC_FAILURE."""
    logger.error("Evaluation rejected: %s", reason)
    if exc is None:
        raise EvaluationError(GENERIC_FAILURE)
    raise EvaluationError(GENERIC_FAILURE) from exc


def parse_provider_payload(raw: dict, max_score: Decimal) -> EvaluationDraft:
    """Backend-side contract. A schema on the wire is not trusted alone."""
    if not isinstance(raw, dict):
        _reject_payload("invalid structured output: payload is not an object")
    status = str(raw.get("status") or "").strip().lower()
    if status not in ALLOWED_STATUSES:
        _reject_payload("invalid structured output: status is not allowed")
    try:
        score = Decimal(str(raw.get("awarded_score"))).quantize(Decimal("0.01"))
    except (InvalidOperation, TypeError, ValueError) as exc:
        _reject_payload("invalid structured output: awarded_score is not a number", exc)
    if score < 0 or score > max_score:
        _reject_payload("score validation: awarded_score is outside 0..max_score")
    if status == AnswerEvaluation.Status.CORRECT and score != max_score:
        _reject_payload("score validation: correct status must equal max_score")
    if status == AnswerEvaluation.Status.PARTIAL and not (0 < score < max_score):
        _reject_payload("score validation: partial status must be between 0 and max_score")
    if status == AnswerEvaluation.Status.INCORRECT and score >= max_score:
        _reject_payload("score validation: incorrect status cannot equal max_score")
    feedback = str(raw.get("feedback") or "").strip()
    misconception = str(raw.get("misconception") or "").strip()
    if not feedback:
        _reject_payload("invalid structured output: feedback is blank")
    return EvaluationDraft(
        status=status,
        awarded_score=score,
        feedback=feedback,
        misconception=misconception,
        model_name="",
    )


def empty_answer_draft() -> EvaluationDraft:
    return EvaluationDraft(
        status=AnswerEvaluation.Status.INCORRECT,
        awarded_score=Decimal("0.00"),
        feedback=EMPTY_FEEDBACK,
        misconception="",
        model_name=DETERMINISTIC_MODEL,
    )


def get_provider() -> EvaluationProvider:
    from .gemini import GeminiEvaluationProvider

    return GeminiEvaluationProvider()


def _persist_evaluation(
    answer: SubmissionAnswer, draft: EvaluationDraft
) -> AnswerEvaluation:
    now = timezone.now()
    evaluation, _ = AnswerEvaluation.objects.update_or_create(
        answer=answer,
        defaults={
            "status": draft.status,
            "awarded_score": draft.awarded_score,
            "feedback": draft.feedback,
            "misconception": draft.misconception,
            "model_name": draft.model_name,
            "evaluated_at": now,
        },
    )
    return evaluation


def evaluate_answer(
    answer: SubmissionAnswer,
    provider: EvaluationProvider | None = None,
    locale: str | None = None,
) -> AnswerEvaluation:
    """Create or reuse the single evaluation row for this answer."""
    if not answer.answer_text.strip():
        draft = empty_answer_draft()
    else:
        try:
            active = provider or get_provider()
            raw = active.complete(request_from_answer(answer, locale=locale))
            draft = parse_provider_payload(raw, answer.question.max_score)
            draft = EvaluationDraft(
                status=draft.status,
                awarded_score=draft.awarded_score,
                feedback=draft.feedback,
                misconception=draft.misconception,
                model_name=active.model_name,
            )
        except EvaluationError:
            raise
        except Exception:
            logger.exception("Evaluation provider failed for answer %s", answer.id)
            raise EvaluationError(GENERIC_FAILURE) from None
    return _persist_evaluation(answer, draft)


def evaluate_answers(
    answers: list[SubmissionAnswer],
    provider: EvaluationProvider | None = None,
    locale: str | None = None,
) -> int:
    """Grade every confirmed answer. Returns how many provider calls failed."""
    if not answers:
        return 0
    active = provider or get_provider()
    failed = 0
    pending: list[SubmissionAnswer] = []
    for answer in answers:
        if not answer.answer_text.strip():
            _persist_evaluation(answer, empty_answer_draft())
            continue
        pending.append(answer)
    complete_many = getattr(active, "complete_many", None)
    if callable(complete_many) and pending:
        try:
            payloads = complete_many(
                [request_from_answer(answer, locale=locale) for answer in pending]
            )
        except EvaluationError:
            return failed + len(pending)
        except Exception:
            logger.exception("Evaluation provider failed for bulk answers")
            return failed + len(pending)
        if not isinstance(payloads, list):
            return failed + len(pending)
        for answer, raw in zip(pending, payloads):
            if raw is None:
                failed += 1
                continue
            try:
                draft = parse_provider_payload(raw, answer.question.max_score)
                _persist_evaluation(
                    answer,
                    EvaluationDraft(
                        status=draft.status,
                        awarded_score=draft.awarded_score,
                        feedback=draft.feedback,
                        misconception=draft.misconception,
                        model_name=active.model_name,
                    ),
                )
            except EvaluationError:
                failed += 1
            except Exception:
                logger.exception(
                    "Evaluation provider failed for answer %s", answer.id
                )
                failed += 1
        if len(payloads) < len(pending):
            failed += len(pending) - len(payloads)
        return failed
    for answer in pending:
        try:
            evaluate_answer(answer, provider=active, locale=locale)
        except EvaluationError:
            failed += 1
    return failed
