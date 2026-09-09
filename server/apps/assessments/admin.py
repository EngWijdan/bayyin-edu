from django.contrib import admin

from .models import Assessment, Question, Submission, SubmissionAnswer


class QuestionInline(admin.TabularInline):
    model = Question
    extra = 0
    fields = ("order", "text", "max_score", "model_answer")
    ordering = ("order",)


@admin.register(Assessment)
class AssessmentAdmin(admin.ModelAdmin):
    list_display = ("title", "classroom", "created_by", "created_at")
    list_filter = ("classroom__academic_year", "classroom__subject")
    search_fields = ("title", "classroom__name")
    readonly_fields = ("created_at", "updated_at")
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
    inlines = (SubmissionAnswerInline,)


@admin.register(SubmissionAnswer)
class SubmissionAnswerAdmin(admin.ModelAdmin):
    list_display = ("submission", "question", "answer_text")
    search_fields = ("answer_text", "submission__student__internal_code")
    readonly_fields = ("created_at", "updated_at")
