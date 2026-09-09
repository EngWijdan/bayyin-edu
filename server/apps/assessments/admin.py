from django.contrib import admin

from .models import Assessment, Question


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
