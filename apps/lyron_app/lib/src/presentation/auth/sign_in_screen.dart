import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/auth/app_auth_status.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _emailController = TextEditingController(text: 'demo@lyron.local');
  final _passwordController = TextEditingController(text: 'LyricaDemo123!');

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(appAuthControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.appName)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, child) {
                final state = controller.state;
                final isBusy = state.status == AppAuthStatus.initializing;

                return Column(
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
                    const SizedBox(height: 12),
                    const Text(AppStrings.signInSummary),
                    if (state.status == AppAuthStatus.sessionExpired) ...[
                      const SizedBox(height: 12),
                      const Text(AppStrings.sessionExpiredMessage),
                    ],
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: AppStrings.emailLabel,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: AppStrings.passwordLabel,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: isBusy
                          ? null
                          : () async {
                              await controller.signIn(
                                email: _emailController.text.trim(),
                                password: _passwordController.text,
                              );
                              ref.invalidate(songCatalogControllerProvider);
                            },
                      child: const Text(AppStrings.signInAction),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
