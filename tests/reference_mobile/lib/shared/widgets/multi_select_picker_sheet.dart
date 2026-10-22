import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/navigation_guard.dart';
import '../constants/app_dimensions.dart';
import 'app_loader.dart';

/// Generic searchable multi-select bottom sheet with checkboxes - the same
/// shape as `UserPickerSheet` (see `features/projects/widgets/`), but
/// parameterized over any item type [T] rather than hardcoded to a project
/// member, so it can be reused for pickers like Billable/Non-Billable
/// Activities. Selection state is owned by the caller (via [onSelect] +
/// [initiallySelectedIds]); this widget only tracks local checkbox state
/// for instant visual feedback while it's open.
class MultiSelectPickerSheet<T> extends StatefulWidget {
  final String title;
  final List<T> items;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final Set<int> initiallySelectedIds;
  final int Function(T item) itemId;
  final String Function(T item) itemLabel;
  final void Function(T item) onSelect;
  final String searchHint;
  final String emptyMessage;

  const MultiSelectPickerSheet({
    super.key,
    required this.title,
    required this.items,
    required this.isLoading,
    required this.errorMessage,
    required this.onRetry,
    required this.initiallySelectedIds,
    required this.itemId,
    required this.itemLabel,
    required this.onSelect,
    this.searchHint = 'Search',
    this.emptyMessage = 'No options available',
  });

  static Future<void> show<T>(
    BuildContext context, {
    required String title,
    required List<T> items,
    required bool isLoading,
    required String? errorMessage,
    required VoidCallback? onRetry,
    required Set<int> initiallySelectedIds,
    required int Function(T item) itemId,
    required String Function(T item) itemLabel,
    required void Function(T item) onSelect,
    String searchHint = 'Search',
    String emptyMessage = 'No options available',
  }) {
    if (!context.canPushRoute) return Future.value();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => MultiSelectPickerSheet<T>(
        title: title,
        items: items,
        isLoading: isLoading,
        errorMessage: errorMessage,
        onRetry: onRetry,
        initiallySelectedIds: initiallySelectedIds,
        itemId: itemId,
        itemLabel: itemLabel,
        onSelect: onSelect,
        searchHint: searchHint,
        emptyMessage: emptyMessage,
      ),
    );
  }

  @override
  State<MultiSelectPickerSheet<T>> createState() =>
      _MultiSelectPickerSheetState<T>();
}

class _MultiSelectPickerSheetState<T> extends State<MultiSelectPickerSheet<T>> {
  final TextEditingController _searchController = TextEditingController();
  final Set<int> _selectedIds = {};
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selectedIds.addAll(widget.initiallySelectedIds);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<T> get _filteredItems {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.items;
    return widget.items
        .where((item) => widget.itemLabel(item).toLowerCase().contains(query))
        .toList();
  }

  void _handleTap(T item) {
    widget.onSelect(item);
    setState(() {
      final id = widget.itemId(item);
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: widget.searchHint,
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppDimensions.inputRadius),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(child: _buildContent(scrollController)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildContent(ScrollController scrollController) {
    if (widget.isLoading) {
      return const AppLoader();
    }

    if (widget.errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined,
                  size: 48, color: AppColors.textSecondaryFor(context)),
              const SizedBox(height: 12),
              Text(
                widget.errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondaryFor(context)),
              ),
              if (widget.onRetry != null) ...[
                const SizedBox(height: 16),
                OutlinedButton(onPressed: widget.onRetry, child: const Text('Retry')),
              ],
            ],
          ),
        ),
      );
    }

    final items = _filteredItems;
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            widget.emptyMessage,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondaryFor(context)),
          ),
        ),
      );
    }

    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = items[index];
        final selected = _selectedIds.contains(widget.itemId(item));
        return CheckboxListTile(
          value: selected,
          onChanged: (_) => _handleTap(item),
          title: Text(widget.itemLabel(item)),
          controlAffinity: ListTileControlAffinity.trailing,
        );
      },
    );
  }
}
