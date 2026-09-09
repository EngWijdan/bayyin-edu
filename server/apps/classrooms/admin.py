from django.contrib import admin

from .models import Classroom, Student


class StudentInline(admin.TabularInline):
    model = Student
    extra = 0
    fields = ("internal_code", "display_name", "is_active")


@admin.register(Classroom)
class ClassroomAdmin(admin.ModelAdmin):
    list_display = ("name", "grade", "subject", "teacher", "academic_year", "is_active")
    list_filter = ("academic_year", "grade", "subject", "is_active")
    search_fields = ("name", "teacher__user__username", "teacher__user__first_name", "teacher__user__last_name")
    readonly_fields = ("created_at", "updated_at")
    inlines = (StudentInline,)


@admin.register(Student)
class StudentAdmin(admin.ModelAdmin):
    list_display = ("internal_code", "display_name", "classroom", "is_active")
    list_filter = ("is_active", "classroom__academic_year")
    search_fields = ("internal_code", "display_name", "classroom__name")
    readonly_fields = ("created_at", "updated_at")
