import 'package:flutter/material.dart';

/// A single icon+label row shown on the "Your Dashboard" / "What You Can
/// Do" walkthrough pages.
class WalkthroughHighlight {
  final IconData icon;
  final String label;

  const WalkthroughHighlight({required this.icon, required this.label});
}

/// One page of the walkthrough. [highlights] is empty for the bookend
/// Welcome/Get Started pages, and populated for the two middle pages.
class WalkthroughStep {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accentColor;
  final List<WalkthroughHighlight> highlights;

  const WalkthroughStep({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    this.highlights = const [],
  });
}
