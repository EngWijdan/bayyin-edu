from rest_framework import status
from rest_framework.authtoken.models import Token
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import UserProfile
from .permissions import IsActiveManager
from .serializers import (
    CurrentUserSerializer,
    LoginSerializer,
    TeacherCreateSerializer,
    TeacherSerializer,
)


class LoginView(APIView):
    permission_classes = (AllowAny,)
    authentication_classes = ()

    def post(self, request):
        serializer = LoginSerializer(data=request.data, context={"request": request})
        serializer.is_valid(raise_exception=True)
        user = serializer.validated_data["user"]
        token, _ = Token.objects.get_or_create(user=user)
        return Response({"token": token.key, "user": CurrentUserSerializer(user).data})


class LogoutView(APIView):
    permission_classes = (IsAuthenticated,)

    def post(self, request):
        if request.auth:
            request.auth.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


class MeView(APIView):
    permission_classes = (IsAuthenticated,)

    def get(self, request):
        return Response(CurrentUserSerializer(request.user).data)


class TeacherListCreateView(APIView):
    permission_classes = (IsActiveManager,)

    def get(self, request):
        users = (
            UserProfile.objects.filter(
                role=UserProfile.Role.TEACHER,
            )
            .select_related("user")
            .order_by("user__first_name", "user__username")
        )
        return Response(TeacherSerializer([profile.user for profile in users], many=True).data)

    def post(self, request):
        serializer = TeacherCreateSerializer(data=request.data, context={"request": request})
        serializer.is_valid(raise_exception=True)
        teacher = serializer.save()
        return Response(TeacherSerializer(teacher).data, status=status.HTTP_201_CREATED)
