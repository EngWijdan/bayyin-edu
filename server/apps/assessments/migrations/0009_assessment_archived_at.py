from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("assessments", "0008_assessment_source_and_question_candidates"),
    ]

    operations = [
        migrations.AddField(
            model_name="assessment",
            name="archived_at",
            field=models.DateTimeField(
                blank=True, null=True, verbose_name="تاريخ الأرشفة"
            ),
        ),
    ]
