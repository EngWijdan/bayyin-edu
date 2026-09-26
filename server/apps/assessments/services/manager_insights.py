"""School-wide manager overview, computed on request.

No derived model: counts and averages are read from classrooms, teachers,
assessments, submissions, and AnswerEvaluation. Incomplete results are never
treated as zeros. Student identity is not included.
"""

from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass
from decimal import Decimal

from django.db.models import Count, Prefetch

from apps.accounts.models import UserProfile
from apps.assessments.models import Assessment, Submission
from apps.assessments.services.class_insights import _misconceptions, _question_gaps
from apps.assessments.services.results import ZERO, build_submission_result
from apps.classrooms.models import Classroom, Student


TOP_GAPS = 10


@dataclass
class ManagerSummary:
    total_teachers: int
    total_classrooms: int
    total_students: int
    total_assessments: int
    assessments_with_complete_results: int
    assessments_with_incomplete_results: int
    overall_average_percentage: Decimal | None


@dataclass
class ManagerClassroomRow:
    classroom_id: object
    classroom_name: str
    grade: str
    subject: str
    teacher_name: str
    student_count: int
    assessment_count: int
    completed_results_count: int
    incomplete_results_count: int
    average_percentage: Decimal | None


@dataclass
class ManagerTeacherRow:
    teacher_id: object
    display_name: str
    classrooms_count: int = 0
    students_count: int = 0
    assessments_count: int = 0
    complete_results_count: int = 0
    incomplete_results_count: int = 0
    average_percentage: Decimal | None = None


@dataclass
class ManagerAssessmentRow:
    assessment_id: object
    title: str
    classroom: str
    teacher: str
    students_with_submission: int
    complete_results: int
    incomplete_results: int
    average_percentage: Decimal | None
    created_at: object = None


@dataclass
class ManagerGapQuestion:
    assessment_title: str
    classroom: str
    question_order: int
    question_text: str
    evaluated_students: int
    gap_count: int
    gap_percentage: Decimal | None


@dataclass
class ManagerMisconception:
    text: str
    count: int


@dataclass
class ManagerInsights:
    summary: ManagerSummary
    classrooms: tuple[ManagerClassroomRow, ...]
    teachers: tuple[ManagerTeacherRow, ...]
    assessments: tuple[ManagerAssessmentRow, ...]
    highest_gap_questions: tuple[ManagerGapQuestion, ...]
    misconceptions: tuple[ManagerMisconception, ...]


def _average(percentages: list[Decimal]) -> Decimal | None:
    if not percentages:
        return None
    return (sum(percentages, ZERO) / Decimal(len(percentages))).quantize(
        Decimal("0.01")
    )


def _prefetched_classrooms():
    return (
        Classroom.objects.select_related("teacher", "teacher__user")
        .annotate(annotated_student_count=Count("students", distinct=True))
        .prefetch_related(
            Prefetch(
                "assessments",
                queryset=Assessment.objects.prefetch_related(
                    "questions",
                    Prefetch(
                        "submissions",
                        queryset=Submission.objects.prefetch_related(
                            "answers__evaluation"
                        ),
                    ),
                ),
            )
        )
        .order_by("name")
    )


def build_manager_insights() -> ManagerInsights:
    classrooms = list(_prefetched_classrooms())
    teachers = list(
        UserProfile.objects.filter(role=UserProfile.Role.TEACHER)
        .select_related("user")
        .order_by("user__first_name", "user__last_name", "user__username")
    )
    teacher_rows = {
        teacher.id: ManagerTeacherRow(
            teacher_id=teacher.id, display_name=teacher.display_name
        )
        for teacher in teachers
    }
    classroom_rows: list[ManagerClassroomRow] = []
    assessment_rows: list[ManagerAssessmentRow] = []
    all_complete: list[Decimal] = []
    assessments_with_complete = 0
    assessments_with_incomplete = 0
    gap_items: list[ManagerGapQuestion] = []
    misconception_subs: list = []
    teacher_complete: dict[object, list[Decimal]] = defaultdict(list)
    teacher_students: dict[object, int] = defaultdict(int)

    for classroom in classrooms:
        teacher = classroom.teacher
        student_count = classroom.annotated_student_count
        assessments = list(classroom.assessments.all())
        completed = 0
        incomplete = 0
        classroom_complete: list[Decimal] = []
        teacher_students[teacher.id] += student_count
        if teacher.id in teacher_rows:
            teacher_rows[teacher.id].classrooms_count += 1
            teacher_rows[teacher.id].assessments_count += len(assessments)

        for assessment in assessments:
            submissions = list(assessment.submissions.all())
            misconception_subs.extend(submissions)
            complete_here: list[Decimal] = []
            incomplete_here = 0
            for submission in submissions:
                result = build_submission_result(submission)
                if result.is_complete:
                    complete_here.append(result.percentage)
                else:
                    incomplete_here += 1
            complete_count = len(complete_here)
            completed += complete_count
            incomplete += incomplete_here
            classroom_complete.extend(complete_here)
            all_complete.extend(complete_here)
            if complete_count:
                assessments_with_complete += 1
            if incomplete_here:
                assessments_with_incomplete += 1
            if teacher.id in teacher_rows:
                teacher_rows[teacher.id].complete_results_count += complete_count
                teacher_rows[teacher.id].incomplete_results_count += incomplete_here
                teacher_complete[teacher.id].extend(complete_here)
            assessment_rows.append(
                ManagerAssessmentRow(
                    assessment_id=assessment.id,
                    title=assessment.title,
                    classroom=classroom.name,
                    teacher=teacher.display_name,
                    students_with_submission=len(submissions),
                    complete_results=complete_count,
                    incomplete_results=incomplete_here,
                    average_percentage=_average(complete_here),
                    created_at=assessment.created_at,
                )
            )
            for gap in _question_gaps(list(assessment.questions.all()), submissions):
                if gap.gap_count <= 0 or gap.gap_percentage is None:
                    continue
                gap_items.append(
                    ManagerGapQuestion(
                        assessment_title=assessment.title,
                        classroom=classroom.name,
                        question_order=gap.question_order,
                        question_text=gap.question_text,
                        evaluated_students=gap.evaluated_students,
                        gap_count=gap.gap_count,
                        gap_percentage=gap.gap_percentage,
                    )
                )

        classroom_rows.append(
            ManagerClassroomRow(
                classroom_id=classroom.id,
                classroom_name=classroom.name,
                grade=classroom.grade,
                subject=classroom.subject,
                teacher_name=teacher.display_name,
                student_count=student_count,
                assessment_count=len(assessments),
                completed_results_count=completed,
                incomplete_results_count=incomplete,
                average_percentage=_average(classroom_complete),
            )
        )

    for teacher_id, row in teacher_rows.items():
        row.students_count = teacher_students[teacher_id]
        row.average_percentage = _average(teacher_complete[teacher_id])

    gap_items.sort(
        key=lambda item: (
            item.gap_percentage is None,
            -(item.gap_percentage or ZERO),
            item.assessment_title,
            item.question_order,
        )
    )
    misconceptions = tuple(
        ManagerMisconception(text=item.text, count=item.count)
        for item in _misconceptions(misconception_subs)
    )
    assessment_rows.sort(key=lambda item: item.created_at, reverse=True)
    teacher_list = sorted(
        teacher_rows.values(), key=lambda item: item.display_name
    )
    return ManagerInsights(
        summary=ManagerSummary(
            total_teachers=len(teachers),
            total_classrooms=len(classrooms),
            total_students=Student.objects.count(),
            total_assessments=sum(row.assessment_count for row in classroom_rows),
            assessments_with_complete_results=assessments_with_complete,
            assessments_with_incomplete_results=assessments_with_incomplete,
            overall_average_percentage=_average(all_complete),
        ),
        classrooms=tuple(classroom_rows),
        teachers=tuple(teacher_list),
        assessments=tuple(assessment_rows),
        highest_gap_questions=tuple(gap_items[:TOP_GAPS]),
        misconceptions=misconceptions,
    )
