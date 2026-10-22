import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../../../shared/constants/app_dimensions.dart';
import '../../../shared/constants/app_strings.dart';
import '../../../shared/enums/user_role.dart';
import '../../../shared/widgets/app_button.dart';
import '../../auth/viewmodel/auth_viewmodel.dart';
import '../model/walkthrough_page.dart';

/// Role-based first-login tour. Pushed in place of the dashboard by
/// [RoleDashboardNavigator.navigate] the first time a given employee lands
/// there - every other auth entry point (login, PIN, biometric, account
/// activation) already funnels through that one navigator, so no other
/// screen needs to know this exists. Suppressed entirely for App Lock
/// unlocks (see `RoleDashboardNavigator`'s `isAppUnlock` parameter).
///
/// Both "Skip" and finishing the last page mark the walkthrough seen via
/// [AuthViewModel.saveWalkthroughSeen] and then replace this screen with
/// [next] - the same dashboard (optionally behind the unread-notifications
/// gate) [RoleDashboardNavigator] would otherwise have shown directly.
class WalkthroughScreen extends StatefulWidget {
  final UserRole role;
  final String employeeCode;
  final Widget next;

  const WalkthroughScreen({
    super.key,
    required this.role,
    required this.employeeCode,
    required this.next,
  });

  @override
  State<WalkthroughScreen> createState() => _WalkthroughScreenState();
}

class _WalkthroughScreenState extends State<WalkthroughScreen> {
  final _pageController = PageController();
  late final List<WalkthroughPage> _pages = widget.role.walkthroughPages;
  int _currentPage = 0;
  bool _finishing = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;

    if (widget.employeeCode.isNotEmpty) {
      await context.read<AuthViewModel>().saveWalkthroughSeen(
        widget.employeeCode,
      );
    }
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => widget.next),
    );
  }

  void _next() {
    final isLastPage = _currentPage == _pages.length - 1;
    if (isLastPage) {
      _finish();
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isLastPage = _currentPage == _pages.length - 1;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: colorScheme.primary,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.screenPadding,
            ),
            child: Column(
              children: [
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _pages.length,
                    onPageChanged: (index) =>
                        setState(() => _currentPage = index),
                    itemBuilder: (context, index) =>
                        _WalkthroughPageContent(page: _pages[index]),
                  ),
                ),
                _PageIndicator(count: _pages.length, currentPage: _currentPage),
                const SizedBox(height: AppDimensions.sectionSpacing),
                AppButton(
                  text: isLastPage
                      ? AppStrings.walkthroughGetStartedButton
                      : AppStrings.walkthroughNextButton,
                  onPressed: _next,
                  backgroundColor: colorScheme.onPrimary,
                  foregroundColor: colorScheme.primary,
                ),
                SizedBox(
                  height: 44,
                  child: isLastPage
                      ? null
                      : Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _finish,
                            style: TextButton.styleFrom(
                              foregroundColor: colorScheme.onPrimary,
                            ),
                            child: Text(
                              AppStrings.walkthroughSkipButton,
                              style: TextStyle(
                                color: colorScheme.onPrimary.withValues(
                                  alpha: 0.85,
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One walkthrough page: title + accent underline + 2 highlight bullets in
/// the top half, the module's SVG illustration filling the bottom half.
class _WalkthroughPageContent extends StatelessWidget {
  final WalkthroughPage page;

  const _WalkthroughPageContent({required this.page});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onPrimary = theme.colorScheme.onPrimary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                page.title,
                textAlign: TextAlign.left,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: AppDimensions.walkthroughTitleUnderlineSpacing),
              Container(
                width: AppDimensions.walkthroughTitleUnderlineWidth,
                height: AppDimensions.walkthroughTitleUnderlineHeight,
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondary,
                  borderRadius: BorderRadius.circular(
                    AppDimensions.walkthroughTitleUnderlineHeight / 2,
                  ),
                ),
              ),
              const SizedBox(height: AppDimensions.sectionSpacing),
              for (var i = 0; i < page.highlights.length; i++) ...[
                if (i > 0)
                  const SizedBox(height: AppDimensions.walkthroughHighlightSpacing),
                _HighlightRow(highlight: page.highlights[i], onPrimary: onPrimary),
              ],
            ],
          ),
        ),
        Expanded(
          flex: 6,
          child: Padding(
            padding: const EdgeInsets.all(AppDimensions.walkthroughIllustrationPadding),
            child: Center(
              child: SvgPicture.asset(page.illustrationAsset, fit: BoxFit.contain),
            ),
          ),
        ),
      ],
    );
  }
}

class _HighlightRow extends StatelessWidget {
  final WalkthroughHighlight highlight;
  final Color onPrimary;

  const _HighlightRow({required this.highlight, required this.onPrimary});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: AppDimensions.walkthroughHighlightIconBoxSize,
          height: AppDimensions.walkthroughHighlightIconBoxSize,
          decoration: BoxDecoration(
            color: onPrimary.withValues(alpha: 0.16),
            shape: BoxShape.circle,
          ),
          child: Icon(
            highlight.icon,
            size: AppDimensions.walkthroughHighlightIconSize,
            color: onPrimary,
          ),
        ),
        const SizedBox(width: AppDimensions.walkthroughHighlightTextSpacing),
        Expanded(
          child: Text(
            highlight.text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: onPrimary.withValues(alpha: 0.92),
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _PageIndicator extends StatelessWidget {
  final int count;
  final int currentPage;

  const _PageIndicator({required this.count, required this.currentPage});

  @override
  Widget build(BuildContext context) {
    final onPrimary = Theme.of(context).colorScheme.onPrimary;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (index) {
        final isActive = index == currentPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(
            horizontal: AppDimensions.walkthroughIndicatorDotSpacing,
          ),
          width: isActive
              ? AppDimensions.walkthroughIndicatorActiveDotWidth
              : AppDimensions.walkthroughIndicatorDotSize,
          height: AppDimensions.walkthroughIndicatorDotSize,
          decoration: BoxDecoration(
            color: isActive ? onPrimary : onPrimary.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(
              AppDimensions.walkthroughIndicatorDotSize / 2,
            ),
          ),
        );
      }),
    );
  }
}
