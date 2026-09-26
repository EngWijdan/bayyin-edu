"""Turn exam-paper OCR text into suggested questions.

Heuristics run first. A structured provider (Gemini) is optional and only
consulted when the parser finds nothing. Neither path writes Question rows.
"""

from __future__ import annotations

import logging
import re
import unicodedata
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation

from django.conf import settings
from django.db import transaction

from apps.assessments.models import (
    Assessment,
    AssessmentQuestionCandidate,
    AssessmentSourceAttachment,
)
from apps.assessments.services.ocr import extract_stored_file

logger = logging.getLogger(__name__)

GENERIC_FAILURE = "تعذر استخراج الأسئلة."
NO_EXAM_PAPER = "ارفع ورقة الاختبار أولًا."
MAX_QUESTION_ORDER = 80
_DIGITS = str.maketrans("٠١٢٣٤٥٦٧٨٩", "0123456789")
# PDF RTL layers insert these; they are not question content.
_FORMAT_CHARS = re.compile(
    r"[\u200B-\u200F\u202A-\u202E\u2060-\u206F\uFEFF\u00AD]"
)
# Colon may sit between the label and the number: `س :1`, `السؤال : 1`.
_LABEL_GAP = r"[ \t]*[:：]?"
_AFTER_NUMBER = r"[ \t]*[\.\:\)\-\u060c،]?"

_MARKER = re.compile(
    r"(?m)^[ \t]*(?:"
    r"(?:السؤال|سؤال)" + _LABEL_GAP + r"[ \t]*(?P<n1>[\d٠-٩]+)"
    r"|س" + _LABEL_GAP + r"[ \t]*(?P<n2>[\d٠-٩]+)"
    r"|Question" + _LABEL_GAP + r"[ \t]*(?P<n3>[\d٠-٩]+)"
    r"|Q" + _LABEL_GAP + r"[ \t]*(?P<n4>[\d٠-٩]+)"
    r"|(?P<n5>[\d٠-٩]+)"
    r")"
    + _AFTER_NUMBER
    + r"[ \t]*",
    re.IGNORECASE,
)

_SCORE = re.compile(
    r"(?:"
    r"[\(\[\{]\s*(?:"
    r"(?P<n>[\d٠-٩]+(?:[.,]\d+)?)\s*"
    r"(?:درجة|درجات|درجه|علام(?:ة|ات)?|mark|marks|point|points)?"
    r"|(?P<dual>درجتان|درجتين)"
    r"|(?P<one>درجة(?:\s+واحدة)?)"
    r")\s*[\)\]\}]"
    r"|(?:^|\s)(?P<bare_dual>درجتان|درجتين)(?:\s|$)"
    r"|(?:^|\s)(?P<bare_one>درجة\s+واحدة)(?:\s|$)"
    r")",
    re.IGNORECASE,
)

_MODEL_ANSWER = re.compile(
    r"(?im)^[ \t]*(?:ال[إا]جابة(?:\s*النموذجية)?|النموذج|Model\s*answer|Answer)"
    r"[ \t]*[:：][ \t]*",
)

# pypdf RTL often drops the number and leaves a lone `س` at line start.
_UNNUMBERED_MARKER = re.compile(
    r"(?m)^(?:السؤال|سؤال|س)(?=$|[\s:：.\)\-\u060c،])[ \t]*[:：]?[ \t]*"
)


class QuestionExtractionError(Exception):
    """The exam paper could not be turned into suggestions."""


@dataclass(frozen=True)
class ExtractedQuestion:
    order: int
    extracted_text: str
    proposed_max_score: Decimal | None = None
    proposed_model_answer: str = ""


class QuestionExtractionService:
    """Deterministic parse first; optional provider only when that is empty."""

    def __init__(self, provider=None, ocr=None):
        self.provider = provider
        self._ocr = ocr

    def extract_from_assessment(self, assessment: Assessment):
        attachment = assessment.source_attachments.order_by("-created_at").first()
        if attachment is None:
            raise QuestionExtractionError(NO_EXAM_PAPER)
        return self.extract_from_attachment(assessment, attachment)

    def extract_from_attachment(
        self,
        assessment: Assessment,
        attachment: AssessmentSourceAttachment,
    ):
        ocr = self._ocr or extract_stored_file
        try:
            text = ocr(attachment.file, attachment.content_type)
        except QuestionExtractionError:
            raise
        except Exception:
            logger.exception("Exam OCR failed for attachment %s", attachment.id)
            raise QuestionExtractionError(GENERIC_FAILURE) from None
        drafts = extract_question_candidates(text, provider=self.provider)
        return persist_suggested_candidates(assessment, drafts)


def extract_question_candidates(text: str, *, provider=None) -> list[ExtractedQuestion]:
    normalized = normalize_exam_text(text or "")
    parsed = parse_exam_text(normalized)
    if parsed:
        return parsed
    if provider is None:
        return []
    try:
        assisted = provider.extract(normalized)
    except QuestionExtractionError:
        raise
    except Exception:
        logger.exception("Question extraction provider failed")
        raise QuestionExtractionError(GENERIC_FAILURE) from None
    sanitized = _sanitize_assisted(assisted)
    if sanitized:
        return sanitized
    return []


def normalize_exam_text(text: str) -> str:
    """Prep RTL/PDF extraction noise without reversing Arabic or fractions.

    pypdf often emits `س :1` and bidi marks instead of `س1`. Strip formatting
    characters and collapse horizontal whitespace; leave digits and `/` as-is.
    """
    text = unicodedata.normalize("NFC", text)
    text = _FORMAT_CHARS.sub("", text)
    text = "".join(ch for ch in text if unicodedata.category(ch) != "Cf")
    text = re.sub(r"[^\S\n]+", " ", text)
    return "\n".join(line.strip() for line in text.splitlines())


def parse_exam_text(text: str) -> list[ExtractedQuestion]:
    text = normalize_exam_text(text)
    numbered = _questions_from_markers(
        text,
        [match for match in _MARKER.finditer(text) if _usable_marker(match)],
        numbered=True,
    )
    if numbered:
        return numbered
    return _questions_from_markers(
        text,
        list(_UNNUMBERED_MARKER.finditer(text)),
        numbered=False,
    )


def _questions_from_markers(text: str, matches: list[re.Match], *, numbered: bool):
    questions = []
    seen_orders: set[int] = set()
    sequential = 0
    for index, match in enumerate(matches):
        if numbered:
            order = _marker_order(match)
            if order in seen_orders:
                continue
        else:
            sequential += 1
            order = sequential
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        body = text[match.end() : end].strip()
        if not body:
            continue
        score, body = _split_score(body)
        model_answer, body = _split_model_answer(body)
        question_text = _clean_question_text(body)
        if not question_text:
            continue
        seen_orders.add(order)
        questions.append(
            ExtractedQuestion(
                order=order,
                extracted_text=question_text,
                proposed_max_score=score,
                proposed_model_answer=model_answer,
            )
        )
    return questions


def persist_suggested_candidates(
    assessment: Assessment, drafts: list[ExtractedQuestion]
) -> list[AssessmentQuestionCandidate]:
    """Replace suggested rows only. Confirmed candidates and Question rows stay."""
    with transaction.atomic():
        AssessmentQuestionCandidate.objects.filter(
            assessment=assessment,
            status=AssessmentQuestionCandidate.Status.SUGGESTED,
        ).delete()
        confirmed_orders = set(
            AssessmentQuestionCandidate.objects.filter(
                assessment=assessment,
                status=AssessmentQuestionCandidate.Status.CONFIRMED,
            ).values_list("order", flat=True)
        )
        for draft in drafts:
            if draft.order in confirmed_orders:
                continue
            AssessmentQuestionCandidate.objects.create(
                assessment=assessment,
                order=draft.order,
                extracted_text=draft.extracted_text,
                proposed_max_score=draft.proposed_max_score,
                proposed_model_answer=draft.proposed_model_answer,
                status=AssessmentQuestionCandidate.Status.SUGGESTED,
            )
    return list(assessment.question_candidates.order_by("order"))


def default_extraction_provider():
    """None unless Gemini is configured, so tests stay offline by default."""
    if not settings.GEMINI_API_KEY:
        return None
    from apps.assessments.services.gemini import GeminiQuestionExtractionProvider

    return GeminiQuestionExtractionProvider()


def _usable_marker(match: re.Match) -> bool:
    order = _marker_order(match)
    if order < 1 or order > MAX_QUESTION_ORDER:
        return False
    rest = match.string[match.end() : match.end() + 1]
    # A line that starts `1/2` is a fraction, not question 1.
    if rest == "/":
        return False
    return True


def _marker_order(match: re.Match) -> int:
    raw = next(value for value in match.groups() if value)
    return int(raw.translate(_DIGITS))


def _split_score(body: str) -> tuple[Decimal | None, str]:
    match = _SCORE.search(body)
    if match is None:
        return None, body
    score = _score_from_match(match)
    cleaned = (body[: match.start()] + " " + body[match.end() :]).strip()
    return score, cleaned


def _score_from_match(match: re.Match) -> Decimal | None:
    if match.group("dual") or match.group("bare_dual"):
        return Decimal("2")
    if match.group("one") or match.group("bare_one"):
        return Decimal("1")
    raw = match.group("n")
    if not raw:
        return None
    try:
        value = Decimal(raw.translate(_DIGITS).replace(",", "."))
    except InvalidOperation:
        return None
    return value if value > 0 else None


def _split_model_answer(body: str) -> tuple[str, str]:
    match = _MODEL_ANSWER.search(body)
    if match is None:
        return "", body
    answer = body[match.end() :].strip()
    question = body[: match.start()].strip()
    return answer, question


def _clean_question_text(body: str) -> str:
    return re.sub(r"[ \t]+", " ", body).strip(" \t\n:-")


def _sanitize_assisted(items) -> list[ExtractedQuestion]:
    if not isinstance(items, list):
        return []
    questions = []
    seen: set[int] = set()
    for item in items:
        if not isinstance(item, dict):
            continue
        try:
            order = int(item.get("order"))
        except (TypeError, ValueError):
            continue
        if order < 1 or order > MAX_QUESTION_ORDER or order in seen:
            continue
        text = str(item.get("question_text") or item.get("extracted_text") or "").strip()
        if not text:
            continue
        score = _optional_decimal(item.get("max_score") or item.get("proposed_max_score"))
        answer = str(item.get("model_answer") or item.get("proposed_model_answer") or "").strip()
        seen.add(order)
        questions.append(
            ExtractedQuestion(
                order=order,
                extracted_text=text,
                proposed_max_score=score,
                proposed_model_answer=answer,
            )
        )
    return questions


def _optional_decimal(value) -> Decimal | None:
    if value in (None, ""):
        return None
    try:
        parsed = Decimal(str(value))
    except InvalidOperation:
        return None
    return parsed if parsed > 0 else None
