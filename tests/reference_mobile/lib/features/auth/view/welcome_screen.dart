import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/navigation_guard.dart';
import '../../../shared/constants/app_dimensions.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/theme_toggle_button.dart';
import 'login_screen.dart';
import 'activate_account_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(AppDimensions.screenPadding),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppDimensions.authContentMaxWidth,
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 60),

                      Image.asset('assets/images/AppIcon.png', height: 140),

                      const SizedBox(height: AppDimensions.sectionSpacing),

                      Text(
                        'Welcome to Comten',
                        style: AppTextStyles.heading.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),

                      const SizedBox(height: 10),

                      Text(
                        'Employee Management Portal',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textSecondaryFor(context),
                          fontSize: 16,
                        ),
                      ),

                      const SizedBox(height: 50),

                      AppButton(
                        text: 'Login',
                        onPressed: () {
                          if (!context.canPushRoute) return;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LoginScreen(),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 15),

                      AppButton(
                        text: 'Activate Account',
                        outlined: true,
                        onPressed: () {
                          if (!context.canPushRoute) return;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ActivateAccountScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Positioned(top: 4, right: 4, child: ThemeToggleButton()),
          ],
        ),
      ),
    );
  }
}
