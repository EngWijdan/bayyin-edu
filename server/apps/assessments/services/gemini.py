"""Gemini adapter. Imported only when a real evaluation needs the network."""

from __future__ import annotations

import json
import logging
import time

from django.conf import settings

from .evaluation import EvaluationError, EvaluationRequest, GENERIC_FAILURE
from .question_extraction import GENERIC_FAILURE as EXTRACTION_FAILURE
from .remediation import (
    GENERIC_FAILURE as REMEDIATION_FAILURE,
    RemediationError,
    RemediationRequest,
)

logger = logging.getLogger(__name__)

_QUOTA_RETRY_WAIT_S = 8
_TRANSIENT_RETRY_WAIT_S = 2
_TRANSIENT_STATUS_CODES = frozenset({408, 429, 503, 504})


def _generation_config(schema: dict) -> dict:
    return {
        "response_mime_type": "application/json",
        "response_schema": schema,
        "thinking_config": {"thinking_level": "MINIMAL"},
    }


def _models_to_try(primary: str) -> list[str]:
    models = [primary]
    fallback = str(getattr(settings, "GEMINI_FALLBACK_MODEL", "") or "").strip()
    if fallback and fallback not in models:
        models.append(fallback)
    return models


def _http_options() -> dict:
    # The SDK retries 5xx/429 up to 5 times by default, which makes a 6-question
    # sheet look like it is stuck on "evaluating" for minutes.
    return {
        "timeout": settings.GEMINI_TIMEOUT_MS,
        "retry_options": {"attempts": 1},
    }


def _status_code(exc: BaseException) -> int | None:
    code = getattr(exc, "code", None)
    if code is None:
        code = getattr(exc, "status_code", None)
    try:
        return int(code)
    except (TypeError, ValueError):
        return None


def _retry_wait_seconds(exc: BaseException) -> float | None:
    code = _status_code(exc)
    if code == 429:
        return float(_QUOTA_RETRY_WAIT_S)
    if code in _TRANSIENT_STATUS_CODES:
        return float(_TRANSIENT_RETRY_WAIT_S)
    return None

EVALUATION_SCHEMA = {
    "type": "OBJECT",
    "properties": {
        "status": {
            "type": "STRING",
            "enum": ["correct", "partial", "incorrect"],
        },
        "awarded_score": {"type": "NUMBER"},
        "feedback": {"type": "STRING"},
        "misconception": {"type": "STRING"},
    },
    "required": ["status", "awarded_score", "feedback", "misconception"],
}

_PROMPT = """You are grading one student answer for a teacher.
Return JSON that matches the schema. Do not add extra keys.

Rules:
- correct: the answer meets the requirement. awarded_score MUST equal max_score.
- partial: the answer is partly right. awarded_score MUST be strictly between 0 and max_score.
- incorrect: the answer does not meet the requirement. awarded_score is 0, or a small value only with a clear academic reason, and MUST be less than max_score.
- misconception: a short description of a wrong concept if one is present, otherwise an empty string. Do not invent one.
- Write both feedback and misconception in the language of locale.
- locale=ar means Arabic. locale=en means English.
- status must stay one of: correct, partial, incorrect.

Locale: {locale}
Subject: {subject}
Grade: {grade}
Question: {question}
Model answer: {model_answer}
Maximum score: {max_score}
Student answer: {student_answer}
"""

BATCH_EVALUATION_SCHEMA = {
    "type": "OBJECT",
    "properties": {
        "evaluations": {
            "type": "ARRAY",
            "items": {
                "type": "OBJECT",
                "properties": {
                    "index": {"type": "INTEGER"},
                    "status": {
                        "type": "STRING",
                        "enum": ["correct", "partial", "incorrect"],
                    },
                    "awarded_score": {"type": "NUMBER"},
                    "feedback": {"type": "STRING"},
                    "misconception": {"type": "STRING"},
                },
                "required": [
                    "index",
                    "status",
                    "awarded_score",
                    "feedback",
                    "misconception",
                ],
            },
        }
    },
    "required": ["evaluations"],
}

_BATCH_PROMPT = """You are grading student answers for a teacher.
Return JSON that matches the schema. Do not add extra keys.

Rules:
- Grade every item. evaluations[i].index MUST equal that item's index.
- correct: the answer meets the requirement. awarded_score MUST equal max_score.
- partial: the answer is partly right. awarded_score MUST be strictly between 0 and max_score.
- incorrect: the answer does not meet the requirement. awarded_score is 0, or a small value only with a clear academic reason, and MUST be less than max_score.
- misconception: a short description of a wrong concept if one is present, otherwise an empty string. Do not invent one.
- Write both feedback and misconception in the language of locale.
- locale=ar means Arabic. locale=en means English.
- status must stay one of: correct, partial, incorrect.

Locale: {locale}
Subject: {subject}
Grade: {grade}

Items:
{items}
"""

REMEDIATION_SCHEMA = {
    "type": "OBJECT",
    "properties": {
        "title": {"type": "STRING"},
        "summary": {"type": "STRING"},
        "objectives": {"type": "ARRAY", "items": {"type": "STRING"}},
        "activities": {
            "type": "ARRAY",
            "items": {
                "type": "OBJECT",
                "properties": {
                    "title": {"type": "STRING"},
                    "description": {"type": "STRING"},
                    "duration_minutes": {"type": "INTEGER"},
                },
                "required": ["title", "description", "duration_minutes"],
            },
        },
        "teacher_guidance": {"type": "STRING"},
    },
    "required": [
        "title",
        "summary",
        "objectives",
        "activities",
        "teacher_guidance",
    ],
}

_REMEDIATION_PROMPT = """You write one classroom remediation plan for a teacher.
Return JSON that matches the schema. Do not add extra keys.

Rules:
- Write title, summary, objectives, activity titles, activity descriptions, and teacher_guidance in the language of locale.
- locale=ar means Arabic. locale=en means English.
- Follow the group focus exactly. Ready is enrichment, not remediation for weak students.
- Use only the listed gaps and misconceptions. If none are listed, write a general reinforcement or enrichment plan from the subject, grade, and assessment title. Do not invent misconceptions or student errors.
- Do not name students. Do not mention files, usernames, or codes.
- Keep activities practical and classroom-ready.

Locale: {locale}
Subject: {subject}
Grade: {grade}
Assessment title: {assessment_title}
Group: {group}
Group size: {group_size}
Percentage min: {percentage_min}
Percentage max: {percentage_max}
Percentage average: {percentage_average}
Focus: {focus}
Highest-gap questions:
{gaps}
Common misconceptions:
{misconceptions}
"""


def _format_gaps(request: RemediationRequest) -> str:
    if not request.highest_gap_questions:
        return "(none listed)"
    lines = []
    for item in request.highest_gap_questions:
        percent = (
            "n/a" if item.gap_percentage is None else f"{item.gap_percentage}"
        )
        lines.append(
            f"- Q{item.question_order} (gap {percent}%, partial {item.partial_count}, "
            f"incorrect {item.incorrect_count}, max {item.max_score}): "
            f"{item.question_text} | model answer: {item.model_answer}"
        )
    return "\n".join(lines)


def _format_misconceptions(request: RemediationRequest) -> str:
    if not request.misconceptions:
        return "(none listed)"
    return "\n".join(
        f"- {item.text} (count {item.count})" for item in request.misconceptions
    )


def _structured_dict(response) -> dict | None:
    parsed = getattr(response, "parsed", None)
    if isinstance(parsed, dict):
        return parsed
    text = getattr(response, "text", None) or ""
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        return None
    return data if isinstance(data, dict) else None


def _format_batch_items(requests: list[EvaluationRequest]) -> str:
    blocks = []
    for index, request in enumerate(requests):
        blocks.append(
            "\n".join(
                [
                    f"[{index}]",
                    f"Question: {request.question}",
                    f"Model answer: {request.model_answer}",
                    f"Maximum score: {request.max_score}",
                    f"Student answer: {request.student_answer}",
                ]
            )
        )
    return "\n\n".join(blocks)


class GeminiEvaluationProvider:
    def __init__(self, client=None):
        self._client = client
        self.model_name = settings.GEMINI_MODEL

    def complete(self, request: EvaluationRequest) -> dict:
        prompt = _PROMPT.format(
            locale=request.locale,
            subject=request.subject,
            grade=request.grade,
            question=request.question,
            model_answer=request.model_answer,
            max_score=request.max_score,
            student_answer=request.student_answer,
        )
        data = self._generate_json(prompt, EVALUATION_SCHEMA)
        if data is None:
            logger.error(
                "Evaluation aborted: malformed Gemini structured output model=%s",
                self.model_name,
            )
            raise EvaluationError(GENERIC_FAILURE)
        return data

    def complete_many(self, requests: list[EvaluationRequest]) -> list[dict | None]:
        if not requests:
            return []
        if len(requests) == 1:
            return [self.complete(requests[0])]
        first = requests[0]
        prompt = _BATCH_PROMPT.format(
            locale=first.locale,
            subject=first.subject,
            grade=first.grade,
            items=_format_batch_items(requests),
        )
        data = self._generate_json(prompt, BATCH_EVALUATION_SCHEMA)
        if data is None:
            logger.error(
                "Evaluation aborted: malformed Gemini batch output model=%s",
                self.model_name,
            )
            raise EvaluationError(GENERIC_FAILURE)
        items = data.get("evaluations")
        if not isinstance(items, list):
            raise EvaluationError(GENERIC_FAILURE)
        mapped: list[dict | None] = [None] * len(requests)
        for offset, item in enumerate(items):
            if not isinstance(item, dict):
                continue
            try:
                index = int(item.get("index", offset))
            except (TypeError, ValueError):
                continue
            if 0 <= index < len(mapped) and mapped[index] is None:
                mapped[index] = item
        return mapped

    def _generate_json(self, prompt: str, schema: dict) -> dict | None:
        client = self._get_client()
        config = _generation_config(schema)
        last_error: BaseException | None = None
        for model in _models_to_try(self.model_name):
            for attempt in range(2):
                try:
                    response = client.models.generate_content(
                        model=model,
                        contents=prompt,
                        config=config,
                    )
                    if model != self.model_name:
                        logger.warning(
                            "Gemini fallback succeeded from=%s to=%s",
                            self.model_name,
                            model,
                        )
                        self.model_name = model
                    return _structured_dict(response)
                except EvaluationError:
                    raise
                except Exception as exc:
                    last_error = exc
                    wait = _retry_wait_seconds(exc)
                    if wait is not None and attempt == 0:
                        logger.warning(
                            "Gemini retry model=%s status=%s wait_s=%s",
                            model,
                            _status_code(exc),
                            wait,
                        )
                        time.sleep(wait)
                        continue
                    logger.exception(
                        "Gemini request failed model=%s error_type=%s status=%s",
                        model,
                        type(exc).__name__,
                        _status_code(exc),
                    )
                    break
        if last_error is not None:
            raise EvaluationError(GENERIC_FAILURE) from None
        return None

    def _get_client(self):
        if self._client is None:
            self._client = self._build_client()
        return self._client

    def _build_client(self):
        if not settings.GEMINI_API_KEY:
            logger.error("Evaluation aborted: GEMINI_API_KEY is missing")
            raise EvaluationError(GENERIC_FAILURE)
        try:
            from google import genai
        except ImportError:
            logger.exception("Gemini SDK is not installed")
            raise EvaluationError(GENERIC_FAILURE) from None
        return genai.Client(
            api_key=settings.GEMINI_API_KEY,
            http_options=_http_options(),
        )


class GeminiRemediationProvider:
    def __init__(self, client=None):
        self._client = client
        self.model_name = settings.GEMINI_MODEL

    def complete(self, request: RemediationRequest) -> dict:
        client = self._client or self._build_client()
        prompt = _REMEDIATION_PROMPT.format(
            locale=request.locale,
            subject=request.subject,
            grade=request.grade,
            assessment_title=request.assessment_title,
            group=request.group,
            group_size=request.group_size,
            percentage_min=request.percentage_min,
            percentage_max=request.percentage_max,
            percentage_average=request.percentage_average,
            focus=request.focus,
            gaps=_format_gaps(request),
            misconceptions=_format_misconceptions(request),
        )
        try:
            response = client.models.generate_content(
                model=self.model_name,
                contents=prompt,
                config={
                    "response_mime_type": "application/json",
                    "response_schema": REMEDIATION_SCHEMA,
                },
            )
        except RemediationError:
            raise
        except Exception:
            logger.exception("Gemini remediation request failed")
            raise RemediationError(REMEDIATION_FAILURE) from None
        data = _structured_dict(response)
        if data is None:
            raise RemediationError(REMEDIATION_FAILURE)
        return data

    def _build_client(self):
        if not settings.GEMINI_API_KEY:
            raise RemediationError(REMEDIATION_FAILURE)
        try:
            from google import genai
        except ImportError:
            logger.exception("Gemini SDK is not installed")
            raise RemediationError(REMEDIATION_FAILURE) from None
        return genai.Client(
            api_key=settings.GEMINI_API_KEY,
            http_options=_http_options(),
        )


QUESTION_EXTRACTION_SCHEMA = {
    "type": "OBJECT",
    "properties": {
        "questions": {
            "type": "ARRAY",
            "items": {
                "type": "OBJECT",
                "properties": {
                    "order": {"type": "INTEGER"},
                    "question_text": {"type": "STRING"},
                    "max_score": {"type": "NUMBER", "nullable": True},
                    "model_answer": {"type": "STRING"},
                },
                "required": ["order", "question_text", "model_answer"],
            },
        }
    },
    "required": ["questions"],
}

_QUESTION_EXTRACTION_PROMPT = """You extract exam questions from OCR text of a teacher exam paper.
Return JSON that matches the schema. Do not add extra keys.

Rules:
- Use only questions that are clearly present in the text.
- Do not invent questions, scores, or model answers.
- If a score is not written, set max_score to null.
- If a model answer is not written, set model_answer to an empty string.
- This is an exam paper only. There is no student data.
- If you are unsure, omit the question.

Exam paper text:
{text}
"""


class GeminiQuestionExtractionProvider:
    def __init__(self, client=None):
        self._client = client
        self.model_name = settings.GEMINI_MODEL

    def extract(self, text: str) -> list:
        client = self._client or self._build_client()
        try:
            response = client.models.generate_content(
                model=self.model_name,
                contents=_QUESTION_EXTRACTION_PROMPT.format(text=text),
                config={
                    "response_mime_type": "application/json",
                    "response_schema": QUESTION_EXTRACTION_SCHEMA,
                },
            )
        except Exception:
            logger.exception("Gemini question extraction failed")
            raise RuntimeError(EXTRACTION_FAILURE) from None
        data = _structured_dict(response)
        if data is None:
            return []
        questions = data.get("questions")
        return questions if isinstance(questions, list) else []

    def _build_client(self):
        if not settings.GEMINI_API_KEY:
            raise RuntimeError(EXTRACTION_FAILURE)
        try:
            from google import genai
        except ImportError:
            logger.exception("Gemini SDK is not installed")
            raise RuntimeError(EXTRACTION_FAILURE) from None
        return genai.Client(
            api_key=settings.GEMINI_API_KEY,
            http_options=_http_options(),
        )
