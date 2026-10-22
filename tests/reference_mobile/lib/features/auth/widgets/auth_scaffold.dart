import 'package:flutter/material.dart';

import '../../../shared/constants/app_dimensions.dart';
import '../../../shared/widgets/theme_toggle_button.dart';

class AuthScaffold extends StatelessWidget {
  final String title;
  final Widget child;
  final bool resizeToAvoidBottomInset;
  final bool showThemeToggle;
  final bool showBackButton;

  const AuthScaffold({
    super.key,
    required this.title,
    required this.child,
    this.resizeToAvoidBottomInset = true,
    this.showThemeToggle = true,
    this.showBackButton = true,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,

      appBar: AppBar(
        title: Text(title),
        centerTitle: true,
        automaticallyImplyLeading: showBackButton,
        actions: showThemeToggle
            ? const [ThemeToggleButton(), SizedBox(width: 4)]
            : null,
      ),

      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            keyboardDismissBehavior:
            ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.screenPadding,
              vertical: AppDimensions.screenPadding,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppDimensions.authContentMaxWidth,
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
