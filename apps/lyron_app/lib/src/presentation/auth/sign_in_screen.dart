import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/auth/app_auth_status.dart';
import 'package:lyron_app/src/domain/auth/sign_in_method.dart';
import 'package:lyron_app/src/router/app_routes.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

// On web, Supabase PKCE requires an HTTP/HTTPS redirect URL so the browser can
// navigate back to the running app and exchange the code using the stored
// code_verifier. Custom URL schemes (io.lyron.app://) only work on mobile.
String get _kRedirectUrl =>
    kIsWeb ? Uri.base.origin : 'io.lyron.app://auth/callback';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _emailController = TextEditingController();
  bool _isSending = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(appAuthControllerProvider);
    final isSessionExpired =
        controller.state.status == AppAuthStatus.sessionExpired;

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.appName)),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          AppStrings.signInTitle,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (isSessionExpired) ...[
                          const SizedBox(height: 12),
                          const Text(AppStrings.sessionExpiredMessage),
                        ],
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: () => controller.signInWithOAuth(
                            SignInMethod.google,
                            redirectTo: _kRedirectUrl,
                          ),
                          child: const Text(AppStrings.continueWithGoogle),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () => controller.signInWithOAuth(
                            SignInMethod.apple,
                            redirectTo: _kRedirectUrl,
                          ),
                          child: const Text(AppStrings.continueWithApple),
                        ),
                        const SizedBox(height: 24),
                        const Divider(),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _emailController,
                          decoration: const InputDecoration(
                            labelText: AppStrings.magicLinkLabel,
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _isSending
                              ? null
                              : () async {
                                  final email = _emailController.text.trim();
                                  if (email.isEmpty) return;
                                  final messenger = ScaffoldMessenger.of(
                                    context,
                                  );
                                  setState(() => _isSending = true);
                                  try {
                                    await controller.sendMagicLink(
                                      email: email,
                                      redirectTo: _kRedirectUrl,
                                    );
                                    if (!mounted) return;
                                    // ignore: use_build_context_synchronously
                                    context.go(AppRoutes.magicLinkSent.path);
                                  } catch (_) {
                                    if (mounted) {
                                      setState(() => _isSending = false);
                                      messenger.showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            AppStrings
                                                .magicLinkSendFailureMessage,
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                },
                          child: const Text(AppStrings.sendMagicLinkAction),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
