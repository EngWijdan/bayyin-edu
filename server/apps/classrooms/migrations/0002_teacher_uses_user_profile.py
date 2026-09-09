import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("accounts", "0002_roles_and_schools"),
        ("classrooms", "0001_initial"),
    ]

    operations = [
        migrations.AlterField(
            model_name="classroom",
            name="teacher",
            field=models.ForeignKey(
                on_delete=django.db.models.deletion.CASCADE,
                related_name="classrooms",
                to="accounts.userprofile",
                verbose_name="المعلم",
            ),
        )
    ]
