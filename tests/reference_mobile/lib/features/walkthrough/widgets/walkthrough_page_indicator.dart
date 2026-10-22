import 'package:flutter/material.dart';

import '../../../shared/constants/app_dimensions.dart';

/// Animated "worm" page-indicator dot row - the active dot widens instead of
/// just changing color, using the same [AnimatedContainer] technique
/// `PinDotsIndicator` already uses for PIN entry progress.
class WalkthroughPageIndicator extends StatelessWidget {
  final int pageCount;
  final int currentPage;
  final Color activeColor;

  const WalkthroughPageIndicator({
    super.key,
    required this.pageCount,
    required this.currentPage,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final inactiveColor = Theme.of(context).colorScheme.outlineVariant;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(pageCount, (index) {
        final isActive = index == currentPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          margin: EdgeInsets.symmetric(
            horizontal: AppDimensions.walkthroughIndicatorDotSpacing / 2,
          ),
          width: isActive
              ? AppDimensions.walkthroughIndicatorActiveDotWidth
              : AppDimensions.walkthroughIndicatorDotSize,
          height: AppDimensions.walkthroughIndicatorDotSize,
          decoration: BoxDecoration(
            color: isActive ? activeColor : inactiveColor,
            borderRadius:
                BorderRadius.circular(AppDimensions.walkthroughIndicatorDotSize / 2),
          ),
        );
      }),
    );
  }
}
