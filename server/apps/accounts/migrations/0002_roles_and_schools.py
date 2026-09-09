import django.db.models.deletion
import uuid
from django.db import migrations, models


def connect_existing_profiles(apps, schema_editor):
    School = apps.get_model("accounts", "School")
    UserProfile = apps.get_model("accounts", "UserProfile")

    for profile in UserProfile.objects.select_related("user"):
        school_name = profile.school_name.strip() or "مدرسة بيّن"
        school, _ = School.objects.get_or_create(name=school_name)
        profile.school = school
        profile.role = "MANAGER" if profile.user.is_superuser else "TEACHER"
        profile.save(update_fields=("school", "role"))


class Migration(migrations.Migration):
    dependencies = [
        ("accounts", "0001_initial"),
        ("classrooms", "0001_initial"),
    ]

    operations = [
        migrations.CreateModel(
            name="School",
            fields=[
                ("id", models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ("name", models.CharField(max_length=160, verbose_name="اسم المدرسة")),
                ("is_active", models.BooleanField(default=True, verbose_name="نشطة")),
                ("created_at", models.DateTimeField(auto_now_add=True, verbose_name="تاريخ الإنشاء")),
                ("updated_at", models.DateTimeField(auto_now=True, verbose_name="آخر تحديث")),
            ],
            options={"verbose_name": "مدرسة", "verbose_name_plural": "المدارس", "ordering": ("name",)},
        ),
        migrations.RenameModel(old_name="TeacherProfile", new_name="UserProfile"),
        migrations.AddField(
            model_name="userprofile",
            name="school",
            field=models.ForeignKey(
                null=True,
                on_delete=django.db.models.deletion.PROTECT,
                related_name="members",
                to="accounts.school",
                verbose_name="المدرسة",
            ),
        ),
        migrations.AddField(
            model_name="userprofile",
            name="role",
            field=models.CharField(
                choices=[("MANAGER", "مدير"), ("TEACHER", "معلم")],
                default="TEACHER",
                max_length=16,
                verbose_name="الدور",
            ),
            preserve_default=False,
        ),
        migrations.AddField(
            model_name="userprofile",
            name="is_active",
            field=models.BooleanField(default=True, verbose_name="نشط"),
        ),
        migrations.AlterField(
            model_name="userprofile",
            name="user",
            field=models.OneToOneField(
                on_delete=django.db.models.deletion.CASCADE,
                related_name="profile",
                to="auth.user",
                verbose_name="المستخدم",
            ),
        ),
        migrations.RunPython(connect_existing_profiles, migrations.RunPython.noop),
        migrations.AlterField(
            model_name="userprofile",
            name="school",
            field=models.ForeignKey(
                on_delete=django.db.models.deletion.PROTECT,
                related_name="members",
                to="accounts.school",
                verbose_name="المدرسة",
            ),
        ),
        migrations.RemoveField(model_name="userprofile", name="school_name"),
        migrations.AlterModelOptions(
            name="userprofile",
            options={"verbose_name": "ملف مستخدم", "verbose_name_plural": "ملفات المستخدمين"},
        ),
    ]
