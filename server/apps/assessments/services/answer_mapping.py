"""Turn completed OCR pages into one suggested answer per question.

Deterministic only: numbered markers in the extracted text, never an LLM.
Empty suggestions are left empty for the teacher to fill in.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

from django.db import transaction

from apps.assessments.models import (
    AttachmentOcrResult,
    OcrAnswerCandidate,
    Submission,
)

NO_EXTRACTED_TEXT = "لا يوجد نص مستخرج يمكن استخدامه بعد."

# Keywords first so "Question 1" is not eaten as "Q" + leftover.
# A bare number counts only with a delimiter, or as its own line, or when
# followed by a space that is not starting a fraction like 1/2.
# RTL papers often store `س:1` / `س :1` with the colon between label and number.
_MARKER = re.compile(
    r"(?im)^[ \t]*(?:"
    r"(?:السؤال|سؤال|question)[ \t]*[:：]?[ \t]*(?P<n1>\d+)[ \t]*[.)\-:]*"
    r"|(?:س|q)[ \t]*[:：]?[ \t]*(?P<n2>\d+)[ \t]*[.)\-:]*"
    r"|(?P<n3>\d+)\s*[.)\-:]+"
    r"|(?P<n4>\d+)[ \t]*$"
    r"|(?P<n5>\d+)[ \t]+(?!/)"
    r")"
)

# pypdf/RTL often drops the number and leaves a lone `س` at line start.
_UNNUMBERED_MARKER = re.compile(
    r"(?im)^[ \t]*(?:السؤال|سؤال|question|س|q)(?=$|[\s:：.\)\-\u060c،])[ \t]*[:：]?[ \t]*"
)
_ANSWER_LABEL = re.compile(
    r"(?im)(?:^|\n)[ \t]*(?:الإجابة|الاجابة|answer)[ \t]*[:：][ \t]*"
)
_TRAILING_NOISE = re.compile(
    r"(?im)(?:^|\n)[ \t]*(?:"
    r"هذه الورقة"
    r"|اختبار تجريبي"
    r"|ورقة طالب تجريبية"
    r"|اسم الطالب"
    r"|رمز الطالب"
    r")\b[\s\S]*$"
)
_LETTER_DIGIT = re.compile(r"([\u0600-\u06FF])(\d)")
_DIGIT_LETTER = re.compile(r"(\d)([\u0600-\u06FF])")


class NoExtractedTextError(ValueError):
    """Raised when mapping is asked to run with no completed OCR pages."""


@dataclass(frozen=True)
class MappingOutcome:
    candidates: list[OcrAnswerCandidate]
    incomplete_ocr: bool


def collect_completed_ocr(submission: Submission) -> tuple[list[str], bool]:
    """Completed OCR texts in upload order, plus whether any file is still raw."""
    texts: list[str] = []
    incomplete = False
    attachments = submission.attachments.order_by("created_at", "id")
    for attachment in attachments:
        result = (
            AttachmentOcrResult.objects.filter(
                attachment=attachment,
                status=AttachmentOcrResult.Status.COMPLETED,
            ).first()
        )
        if result is None:
            incomplete = True
            continue
        texts.append(result.extracted_text or "")
    return texts, incomplete


def _clean_extracted_answer(text: str) -> str:
    """Keep only the student's reply; drop headers/footers glued by PDF order."""
    text = _TRAILING_NOISE.sub("", text)
    text = _LETTER_DIGIT.sub(r"\1 \2", text)
    text = _DIGIT_LETTER.sub(r"\1 \2", text)
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r" *\n+ *", "\n", text)
    return text.strip().rstrip(".").strip()


def _answer_body(chunk: str) -> str:
    """Prefer the labelled student answer when the block still has the stem."""
    match = _ANSWER_LABEL.search(chunk)
    body = chunk[match.end() :] if match else chunk
    return _clean_extracted_answer(body)


def split_answers_by_markers(text: str) -> dict[int, str]:
    """Map question order → answer body. Unrecognised text is dropped, not guessed."""
    matches = list(_MARKER.finditer(text))
    numbered = bool(matches)
    if not matches:
        matches = list(_UNNUMBERED_MARKER.finditer(text))
    if not matches:
        return {}
    blocks: dict[int, str] = {}
    sequential = 0
    for index, match in enumerate(matches):
        if numbered:
            number = int(next(group for group in match.groups() if group is not None))
        else:
            sequential += 1
            number = sequential
        start = match.end()
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        chunk = _answer_body(text[start:end])
        if number in blocks and chunk:
            blocks[number] = f"{blocks[number]}\n{chunk}".strip()
        elif number not in blocks:
            blocks[number] = chunk
    return blocks


def map_ocr_text_to_questions(submission: Submission) -> MappingOutcome:
    texts, incomplete = collect_completed_ocr(submission)
    if not texts:
        raise NoExtractedTextError(NO_EXTRACTED_TEXT)
    combined = "\n\n".join(texts)
    blocks = split_answers_by_markers(combined)
    questions = list(submission.assessment.questions.order_by("order"))
    candidates: list[OcrAnswerCandidate] = []
    with transaction.atomic():
        for question in questions:
            extracted = blocks.get(question.order, "")
            candidate, created = OcrAnswerCandidate.objects.get_or_create(
                submission=submission,
                question=question,
                defaults={
                    "extracted_text": extracted,
                    "source": "ocr",
                    "status": OcrAnswerCandidate.Status.SUGGESTED,
                },
            )
            if not created:
                candidate.extracted_text = extracted
                if candidate.status != OcrAnswerCandidate.Status.CONFIRMED:
                    candidate.status = OcrAnswerCandidate.Status.SUGGESTED
                candidate.save(
                    update_fields=["extracted_text", "status", "updated_at"]
                )
            candidates.append(candidate)
    return MappingOutcome(candidates=candidates, incomplete_ocr=incomplete)
