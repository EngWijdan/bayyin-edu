import uuid

from django.conf import settings
from django.db import models


class UserProfile(models.Model):
    class Role(models.TextChoices):
        MANAGER = "MANAGER", "مدير"
        TEACHER = "TEACHER", "معلم"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="profile",
        verbose_name="المستخدم",
    )
    role = models.CharField("الدور", max_length=16, choices=Role.choices)
    is_active = models.BooleanField("نشط", default=True)
    created_at = models.DateTimeField("تاريخ الإنشاء", auto_now_add=True)
    updated_at = models.DateTimeField("آخر تحديث", auto_now=True)

    class Meta:
        verbose_name = "ملف مستخدم"
        verbose_name_plural = "ملفات المستخدمين"

    def __str__(self) -> str:
        return self.display_name

    @property
    def display_name(self) -> str:
        """Authoritative name to show in the UI: real name first, username as last resort."""
        return self.user.get_full_name().strip() or self.user.username

    @property
    def is_manager(self) -> bool:
        return self.role == self.Role.MANAGER
