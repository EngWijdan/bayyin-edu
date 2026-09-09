from getpass import getpass

from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from apps.accounts.models import UserProfile


class Command(BaseCommand):
    help = "إنشاء المدرسة وحساب المدير الأول مرة واحدة"

    def add_arguments(self, parser):
        parser.add_argument("--username", required=True)
        parser.add_argument("--email", default="")

    @transaction.atomic
    def handle(self, *args, **options):
        user_model = get_user_model()
        username = options["username"].strip()
        user = user_model.objects.filter(username=username).first()
        if user and hasattr(user, "profile"):
            raise CommandError("هذا المستخدم مرتبط بمدرسة مسبقًا.")
        if not user:
            password = getpass("كلمة المرور: ")
            confirmation = getpass("تأكيد كلمة المرور: ")
            if password != confirmation:
                raise CommandError("كلمتا المرور غير متطابقتين.")
            if len(password) < 8:
                raise CommandError("كلمة المرور يجب ألا تقل عن 8 أحرف.")
            user = user_model.objects.create_user(
                username=username,
                email=options["email"],
                password=password,
            )
        UserProfile.objects.create(user=user, role=UserProfile.Role.MANAGER)
        self.stdout.write(self.style.SUCCESS("تم إنشاء مدير نظام بيّن."))
