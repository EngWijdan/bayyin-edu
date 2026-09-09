from rest_framework.permissions import BasePermission


def active_profile(request):
    """Return the caller's profile when both the user and the profile are active."""
    profile = getattr(request.user, "profile", None)
    if request.user.is_authenticated and request.user.is_active and profile and profile.is_active:
        return profile
    return None


class IsActiveSchoolMember(BasePermission):
    """Any active manager or teacher. Row-level scoping is done by the queryset."""

    message = "هذه العملية تتطلب حسابًا نشطًا."

    def has_permission(self, request, view):
        return active_profile(request) is not None


class IsActiveManager(BasePermission):
    message = "هذه العملية متاحة لمدير المدرسة فقط."

    def has_permission(self, request, view):
        profile = active_profile(request)
        return bool(profile and profile.is_manager)
