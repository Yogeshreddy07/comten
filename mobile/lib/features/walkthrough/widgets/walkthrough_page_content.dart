import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/constants/app_dimensions.dart';
import '../model/walkthrough_step.dart';

/// A single walkthrough page's content: an animated icon circle, title,
/// subtitle, and (when present) a short staggered-fade-in list of
/// icon+label highlights. Purely presentational.
class WalkthroughPageContent extends StatelessWidget {
  final WalkthroughStep step;

  const WalkthroughPageContent({super.key, required this.step});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.screenPadding),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutBack,
            builder: (context, value, child) {
              final clamped = value.clamp(0.0, 1.0);
              return Transform.scale(
                scale: value,
                child: Opacity(opacity: clamped, child: child),
              );
            },
            child: Container(
              width: AppDimensions.walkthroughIconCircleSize,
              height: AppDimensions.walkthroughIconCircleSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: step.accentColor.withValues(alpha: 0.14),
              ),
              child: Icon(
                step.icon,
                size: AppDimensions.walkthroughIconGlyphSize,
                color: step.accentColor,
              ),
            ),
          ),
          const SizedBox(height: AppDimensions.walkthroughContentSpacing),
          Text(
            step.title,
            textAlign: TextAlign.center,
            style: AppTextStyles.heading.copyWith(fontSize: 24),
          ),
          const SizedBox(height: 10),
          Text(
            step.subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondaryFor(context), fontSize: 15),
          ),
          if (step.highlights.isNotEmpty) ...[
            const SizedBox(height: AppDimensions.walkthroughContentSpacing),
            ...List.generate(step.highlights.length, (index) {
              final highlight = step.highlights[index];
              return TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: Duration(milliseconds: 350 + index * 100),
                curve: Curves.easeOut,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, (1 - value) * 12),
                      child: child,
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.only(
                    bottom: AppDimensions.walkthroughHighlightSpacing,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        highlight.icon,
                        size: AppDimensions.walkthroughHighlightIconSize,
                        color: step.accentColor,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(highlight.label, style: AppTextStyles.body),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
