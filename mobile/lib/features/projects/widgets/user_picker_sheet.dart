import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/navigation_guard.dart';
import '../../../shared/constants/app_dimensions.dart';
import '../../../shared/constants/app_strings.dart';
import '../../../shared/widgets/app_loader.dart';
import '../model/project_member_option.dart';

/// Searchable single/multi-select sheet for choosing users (Team Leader,
/// Team Members) - shows each user as employee ID / name / email per the
/// required professional format. Purely presentational: selection state is
/// owned by the caller's ViewModel; this widget only reports taps back via
/// [onSelect] while tracking its own local highlight state for instant
/// visual feedback inside the sheet.
class UserPickerSheet extends StatefulWidget {
  final String title;
  final List<ProjectMemberOption> users;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final bool multiSelect;
  final Set<int> initiallySelectedIds;
  final void Function(ProjectMemberOption user) onSelect;

  const UserPickerSheet({
    super.key,
    required this.title,
    required this.users,
    required this.isLoading,
    required this.errorMessage,
    required this.onRetry,
    required this.multiSelect,
    required this.initiallySelectedIds,
    required this.onSelect,
  });

  static Future<void> show(
    BuildContext context, {
    required String title,
    required List<ProjectMemberOption> users,
    required bool isLoading,
    required String? errorMessage,
    required VoidCallback? onRetry,
    required bool multiSelect,
    required Set<int> initiallySelectedIds,
    required void Function(ProjectMemberOption user) onSelect,
  }) {
    if (!context.canPushRoute) return Future.value();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => UserPickerSheet(
        title: title,
        users: users,
        isLoading: isLoading,
        errorMessage: errorMessage,
        onRetry: onRetry,
        multiSelect: multiSelect,
        initiallySelectedIds: initiallySelectedIds,
        onSelect: onSelect,
      ),
    );
  }

  @override
  State<UserPickerSheet> createState() => _UserPickerSheetState();
}

class _UserPickerSheetState extends State<UserPickerSheet> {
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

  List<ProjectMemberOption> get _filteredUsers {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.users;
    return widget.users.where((user) {
      return user.name.toLowerCase().contains(query) ||
          user.employeeCode.toLowerCase().contains(query) ||
          user.email.toLowerCase().contains(query);
    }).toList();
  }

  void _handleTap(ProjectMemberOption user) {
    widget.onSelect(user);
    if (!widget.multiSelect) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      if (_selectedIds.contains(user.id)) {
        _selectedIds.remove(user.id);
      } else {
        _selectedIds.add(user.id);
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
                    if (widget.multiSelect)
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Done'),
                      )
                    else
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
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
                    hintText: AppStrings.userPickerSearchHint,
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

    final users = _filteredUsers;
    if (users.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_search_outlined,
                  size: 48, color: AppColors.textSecondaryFor(context)),
              const SizedBox(height: 12),
              Text(
                AppStrings.userPickerEmptyForRole(widget.title),
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondaryFor(context)),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
      itemCount: users.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final user = users[index];
        final selected = _selectedIds.contains(user.id);
        return ListTile(
          onTap: () => _handleTap(user),
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Text(
              user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          title: Text(user.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${user.employeeCode} · ${user.email}'),
          trailing: widget.multiSelect
              ? Checkbox(value: selected, onChanged: (_) => _handleTap(user))
              : (selected
                  ? Icon(Icons.check_circle,
                      color: Theme.of(context).colorScheme.primary)
                  : null),
        );
      },
    );
  }
}
