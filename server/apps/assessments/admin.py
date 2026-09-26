from django.contrib import admin

from .models import (
    AnswerEvaluation,
    Assessment,
    AssessmentQuestionCandidate,
    AssessmentSourceAttachment,
    AttachmentOcrResult,
    OcrAnswerCandidate,
    Question,
    RemediationPlan,
    Submission,
    SubmissionAnswer,
    SubmissionAttachment,
)


class QuestionInline(admin.TabularInline):
    model = Question
    extra = 0
    fields = ("order", "text", "max_score", "model_answer")
    ordering = ("order",)


@admin.register(Assessment)
class AssessmentAdmin(admin.ModelAdmin):
    list_display = ("title", "classroom", "created_by", "created_at", "archived_at")
    list_filter = ("classroom__academic_year", "classroom__subject", "archived_at")
    search_fields = ("title", "classroom__name")
    readonly_fields = ("created_at", "updated_at", "archived_at")
    inlines = (QuestionInline,)


@admin.register(Question)
class QuestionAdmin(admin.ModelAdmin):
    list_display = ("order", "text", "max_score", "assessment")
    list_filter = ("assessment__classroom__subject",)
    search_fields = ("text", "assessment__title")
    readonly_fields = ("created_at", "updated_at")


class SubmissionAnswerInline(admin.TabularInline):
    model = SubmissionAnswer
    extra = 0
    fields = ("question", "answer_text")


class SubmissionAttachmentInline(admin.TabularInline):
    model = SubmissionAttachment
    extra = 0
    fields = ("original_filename", "content_type", "file_size", "created_at")
    readonly_fields = fields


@admin.register(Submission)
class SubmissionAdmin(admin.ModelAdmin):
    list_display = ("student", "assessment", "created_by", "created_at")
    list_filter = ("assessment__classroom__subject",)
    search_fields = (
        "student__internal_code",
        "student__display_name",
        "assessment__title",
    )
    readonly_fields = ("created_at", "updated_at")
    inlines = (SubmissionAnswerInline, SubmissionAttachmentInline)


@admin.register(SubmissionAnswer)
class SubmissionAnswerAdmin(admin.ModelAdmin):
    list_display = ("submission", "question", "answer_text")
    search_fields = ("answer_text", "submission__student__internal_code")
    readonly_fields = ("created_at", "updated_at")


@admin.register(SubmissionAttachment)
class SubmissionAttachmentAdmin(admin.ModelAdmin):
    list_display = ("original_filename", "content_type", "file_size", "submission")
    list_filter = ("content_type",)
    search_fields = ("original_filename", "submission__student__internal_code")
    readonly_fields = ("created_at",)


@admin.register(AttachmentOcrResult)
class AttachmentOcrResultAdmin(admin.ModelAdmin):
    list_display = ("attachment", "status", "processed_at")
    list_filter = ("status",)
    search_fields = ("attachment__original_filename", "extracted_text")
    readonly_fields = ("created_at", "updated_at", "processed_at")


@admin.register(OcrAnswerCandidate)
class OcrAnswerCandidateAdmin(admin.ModelAdmin):
    list_display = ("submission", "question", "status", "extracted_text")
    list_filter = ("status",)
    search_fields = ("extracted_text", "submission__student__internal_code")
    readonly_fields = ("created_at", "updated_at")


@admin.register(AnswerEvaluation)
class AnswerEvaluationAdmin(admin.ModelAdmin):
    list_display = ("answer", "status", "awarded_score", "model_name", "evaluated_at")
    list_filter = ("status",)
    search_fields = ("feedback", "misconception")
    readonly_fields = ("created_at", "updated_at", "evaluated_at")


@admin.register(RemediationPlan)
class RemediationPlanAdmin(admin.ModelAdmin):
    list_display = ("assessment", "group", "status", "title", "generated_at")
    list_filter = ("group", "status")
    search_fields = ("title", "summary", "assessment__title")
    readonly_fields = ("created_at", "updated_at", "generated_at")


@admin.register(AssessmentSourceAttachment)
class AssessmentSourceAttachmentAdmin(admin.ModelAdmin):
    list_display = ("original_filename", "content_type", "file_size", "assessment")
    list_filter = ("content_type",)
    search_fields = ("original_filename", "assessment__title")
    readonly_fields = ("created_at",)


@admin.register(AssessmentQuestionCandidate)
class AssessmentQuestionCandidateAdmin(admin.ModelAdmin):
    list_display = ("order", "extracted_text", "status", "assessment")
    list_filter = ("status",)
    search_fields = ("extracted_text", "assessment__title")
    readonly_fields = ("created_at", "updated_at")

