import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/app_language.dart';
import 'screens/manager_dashboard.dart';
import 'screens/teacher_dashboard.dart';
import 'services/attachment_picker.dart';
import 'services/bayyin_api.dart';
import 'widgets/language_switcher.dart';

void main() => runApp(const BayyinApp());

class BayyinApp extends StatefulWidget {
  const BayyinApp({super.key, this.gateway, this.picker, this.initialLocale});

  final BayyinGateway? gateway;
  final AttachmentPicker? picker;
  final AppLocale? initialLocale;

  @override
  State<BayyinApp> createState() => _BayyinAppState();
}

class _BayyinAppState extends State<BayyinApp> {
  late AppLocale appLocale = widget.initialLocale ?? AppLocale.arabic;

  void changeLanguage(AppLocale value) {
    if (value == appLocale) return;
    setState(() => appLocale = value);
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF176B5B);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => context.strings.appTitle,
      locale: appLocale.locale,
      supportedLocales: supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          surface: const Color(0xFFF7F7F2),
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F7F2),
        cardTheme: const CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: Colors.white,
        ),
      ),
      home: AuthGate(
        gateway: widget.gateway ?? BayyinApi(),
        picker: widget.picker ?? const PlatformAttachmentPicker(),
        onLocaleChanged: changeLanguage,
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.gateway,
    required this.picker,
    required this.onLocaleChanged,
  });

  final BayyinGateway gateway;
  final AttachmentPicker picker;
  final ValueChanged<AppLocale> onLocaleChanged;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  UserSession? session;

  @override
  Widget build(BuildContext context) {
    final currentSession = session;
    if (currentSession == null) {
      return LoginPage(
        gateway: widget.gateway,
        onLocaleChanged: widget.onLocaleChanged,
        onLoggedIn: (value) => setState(() => session = value),
      );
    }
    if (currentSession.isManager) {
      return ManagerDashboard(
        gateway: widget.gateway,
        session: currentSession,
        onLogout: _logout,
        onLocaleChanged: widget.onLocaleChanged,
      );
    }
    return TeacherDashboard(
      gateway: widget.gateway,
      picker: widget.picker,
      session: currentSession,
      onLogout: _logout,
      onLocaleChanged: widget.onLocaleChanged,
    );
  }

  Future<void> _logout() async {
    final token = session?.token;
    setState(() => session = null);
    if (token != null) await widget.gateway.logout(token);
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.gateway,
    required this.onLoggedIn,
    required this.onLocaleChanged,
  });

  final BayyinGateway gateway;
  final ValueChanged<UserSession> onLoggedIn;
  final ValueChanged<AppLocale> onLocaleChanged;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final formKey = GlobalKey<FormState>();
  final username = TextEditingController();
  final password = TextEditingController();
  bool loading = false;
  Object? error;

  @override
  void dispose() {
    username.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Scaffold(
      appBar: AppBar(
        actions: [
          LanguageSwitcher(
            onLocaleChanged: widget.onLocaleChanged,
            showLabel: true,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Form(
                    key: formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const CircleAvatar(
                          radius: 32,
                          child: Icon(Icons.visibility_outlined, size: 34),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          strings.loginTitle,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          strings.loginSubtitle,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: username,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: strings.username,
                            prefixIcon: const Icon(Icons.person_outline),
                            border: const OutlineInputBorder(),
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? strings.usernameRequired
                              : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: password,
                          obscureText: true,
                          onFieldSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            labelText: strings.password,
                            prefixIcon: const Icon(Icons.lock_outline),
                            border: const OutlineInputBorder(),
                          ),
                          validator: (value) => value == null || value.isEmpty
                              ? strings.passwordRequired
                              : null,
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            strings.describeError(
                              error,
                              fallback: strings.loginConnectionError,
                            ),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: loading ? null : _submit,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              loading ? strings.signingIn : strings.signIn,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!formKey.currentState!.validate()) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final session = await widget.gateway.login(
        username.text.trim(),
        password.text,
      );
      widget.onLoggedIn(session);
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = exception;
      });
    }
  }
}
