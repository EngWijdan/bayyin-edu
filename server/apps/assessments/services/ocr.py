"""Turn a stored student paper into plain text.

Views and models talk only to `run_ocr` / `extract_text`. The Tesseract
engine lives behind that boundary so a later swap (or a Celery job wrapping
the same call) does not leak into the API.
"""

from __future__ import annotations

import logging
import re
from collections import defaultdict
from io import BytesIO

import pytesseract
from django.conf import settings
from django.utils import timezone
from pdf2image import convert_from_bytes
from PIL import Image
from pypdf import PdfReader

from apps.assessments.models import AttachmentOcrResult, SubmissionAttachment

logger = logging.getLogger(__name__)

_GENERIC_FAILURE = "تعذر استخراج النص."
_LETTERS = re.compile(r"[A-Za-z0-9\u0600-\u06FF]")


class OcrError(Exception):
    """Raised when the file cannot be turned into text. The API maps this
    to a failed result rather than a 500, so a bad paper does not look like
    a server crash."""


def read_file_field(file_field) -> bytes:
    """Read through Django storage so OCR never depends on a public URL."""
    file_field.open("rb")
    try:
        return file_field.read()
    finally:
        file_field.close()


def read_attachment_bytes(attachment: SubmissionAttachment) -> bytes:
    return read_file_field(attachment.file)


def extract_from_bytes(data: bytes, content_type: str) -> str:
    """Exam papers keep default pypdf order so question extraction stays stable."""
    return TesseractExtractor().extract_from_bytes(data, content_type)


def extract_stored_file(file_field, content_type: str) -> str:
    return extract_from_bytes(read_file_field(file_field), content_type)


def extract_text(attachment: SubmissionAttachment) -> str:
    """Student-paper entry point. Rebuilds RTL PDF layout before OCR fallback."""
    return TesseractExtractor().extract(attachment)


def run_ocr(attachment: SubmissionAttachment) -> AttachmentOcrResult:
    """Create or reuse the single result row, then fill it in place.

    Synchronous for the MVP. Status is written before and after the engine
    so the same row can later be updated by a background worker without
    changing the model or the API shape.
    """
    result, _ = AttachmentOcrResult.objects.get_or_create(attachment=attachment)
    result.status = AttachmentOcrResult.Status.PROCESSING
    result.error_message = ""
    result.save(update_fields=["status", "error_message", "updated_at"])
    try:
        text = extract_text(attachment)
    except Exception:
        logger.exception("OCR failed for attachment %s", attachment.id)
        result.status = AttachmentOcrResult.Status.FAILED
        result.extracted_text = ""
        result.error_message = _GENERIC_FAILURE
        result.processed_at = timezone.now()
        result.save(
            update_fields=[
                "status",
                "extracted_text",
                "error_message",
                "processed_at",
                "updated_at",
            ]
        )
        return result
    result.status = AttachmentOcrResult.Status.COMPLETED
    result.extracted_text = text
    result.error_message = ""
    result.processed_at = timezone.now()
    result.save(
        update_fields=[
            "status",
            "extracted_text",
            "error_message",
            "processed_at",
            "updated_at",
        ]
    )
    return result


class TesseractExtractor:
    """Local Tesseract + pypdf. Arabic and English in one pass (`ara+eng`)."""

    def extract(self, attachment: SubmissionAttachment) -> str:
        return self.extract_from_bytes(
            read_attachment_bytes(attachment),
            attachment.content_type,
            rebuild_layout=True,
        )

    def extract_from_bytes(
        self, data: bytes, content_type: str, *, rebuild_layout: bool = False
    ) -> str:
        if content_type == "application/pdf":
            return self._extract_pdf(data, rebuild_layout=rebuild_layout)
        return self._ocr_image(data)

    def _extract_pdf(self, data: bytes, *, rebuild_layout: bool = False) -> str:
        page_count = _pdf_page_count(data)
        if page_count > settings.OCR_PDF_MAX_PAGES:
            raise OcrError(_GENERIC_FAILURE)
        layer = _pdf_layout_text(data) if rebuild_layout else _pdf_text_layer(data)
        if rebuild_layout and not _has_useful_text(layer):
            layer = _pdf_text_layer(data)
        if _has_useful_text(layer):
            return layer.strip()
        return self._ocr_pdf_pages(data)

    def _ocr_pdf_pages(self, data: bytes) -> str:
        images = convert_from_bytes(
            data,
            dpi=settings.OCR_PDF_DPI,
            first_page=1,
            last_page=settings.OCR_PDF_MAX_PAGES,
        )
        pages = [self._ocr_pil(image) for image in images]
        return "\n\n".join(page for page in pages if page)

    def _ocr_image(self, data: bytes) -> str:
        try:
            image = Image.open(BytesIO(data))
        except Exception as exc:
            raise OcrError(_GENERIC_FAILURE) from exc
        return self._ocr_pil(image)

    def _ocr_pil(self, image: Image.Image) -> str:
        if image.mode not in ("RGB", "L"):
            image = image.convert("RGB")
        return pytesseract.image_to_string(
            image, lang=settings.OCR_LANGUAGES
        ).strip()


def _pdf_page_count(data: bytes) -> int:
    return len(PdfReader(BytesIO(data)).pages)


def _pdf_text_layer(data: bytes) -> str:
    reader = PdfReader(BytesIO(data))
    return "\n".join((page.extract_text() or "") for page in reader.pages)


_ARABIC = re.compile(r"[\u0600-\u06FF]")
_LETTER_DIGIT = re.compile(r"([\u0600-\u06FF])(\d)")
_DIGIT_LETTER = re.compile(r"(\d)([\u0600-\u06FF])")


def _pdf_layout_text(data: bytes) -> str:
    """Rebuild visual order from PDF operators.

    Default ``extract_text()`` drops question numbers and answer fragments on
    Arabic RTL papers because glyphs are stored out of reading order.
    """
    reader = PdfReader(BytesIO(data))
    pages = []
    for page in reader.pages:
        rebuilt = _rebuild_page_text(page)
        pages.append(rebuilt if rebuilt.strip() else (page.extract_text() or ""))
    return "\n\n".join(pages)


def _rebuild_page_text(page) -> str:
    fragments: list[tuple[float, float, float, str]] = []

    def visitor(text, cm, tm, font_dict, font_size):
        cleaned = str(text).replace("\n", "")
        if not cleaned.strip():
            return
        matrix = tm or (1, 0, 0, 1, 0, 0)
        fragments.append(
            (
                round(float(matrix[5]), 1),
                round(float(matrix[4]), 1),
                float(matrix[3]),
                cleaned,
            )
        )

    page.extract_text(visitor_text=visitor)
    if not fragments:
        return ""
    flipped = sum(1 for *_, scale, _text in fragments if scale < 0) * 2 >= len(
        fragments
    )
    lines: dict[float, list[tuple[float, str]]] = defaultdict(list)
    for y, x, _scale, text in fragments:
        lines[y].append((x, text))
    y_keys = sorted(lines) if flipped else sorted(lines, reverse=True)
    return _normalize_layout_spacing(
        "\n".join(_join_line(lines[y]) for y in y_keys)
    )


def _join_line(items: list[tuple[float, str]]) -> str:
    by_x: dict[float, list[str]] = defaultdict(list)
    for x, text in items:
        by_x[x].append(text)
    rtl = bool(_ARABIC.search("".join(text for _x, text in items)))
    parts = []
    for x in sorted(by_x, reverse=rtl):
        parts.append("".join(reversed(by_x[x])))
    return " ".join(parts)


def _normalize_layout_spacing(text: str) -> str:
    text = _LETTER_DIGIT.sub(r"\1 \2", text)
    text = _DIGIT_LETTER.sub(r"\1 \2", text)
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r" *\n *", "\n", text)
    return text.strip()


def _has_useful_text(text: str) -> bool:
    """A scanned PDF still has a text layer of page numbers and junk; this
    asks whether there are enough real characters to skip OCR."""
    return len(_LETTERS.findall(text)) >= settings.OCR_PDF_TEXT_MIN_CHARS
