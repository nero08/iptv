import 'package:flutter/material.dart';

import '../iptv/models.dart';

/// In-tab header shown above a drilled-in grid: a back affordance + the
/// category name. Used by the Live / VOD / Series tabs so the grid renders
/// inside the tab (keeping the persistent bottom bar) instead of a pushed
/// route. Back is also handled centrally by the shell's PopScope (remote Back).
///
/// When [categories] + [onSelectCategory] are supplied the name becomes a
/// dropdown so the user can jump to another category without going back to the
/// list first.
class CategoryHeader extends StatelessWidget {
  const CategoryHeader({
    super.key,
    required this.title,
    required this.onBack,
    this.categories,
    this.currentId,
    this.onSelectCategory,
  });

  final String title;
  final VoidCallback onBack;
  final List<Category>? categories;
  final String? currentId;
  final void Function(Category)? onSelectCategory;

  bool get _hasPicker =>
      categories != null && categories!.isNotEmpty && onSelectCategory != null;

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleMedium;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Retour aux catégories',
            onPressed: onBack,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _hasPicker
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: PopupMenuButton<Category>(
                      tooltip: 'Changer de catégorie',
                      onSelected: onSelectCategory,
                      itemBuilder: (context) => [
                        for (final c in categories!)
                          PopupMenuItem<Category>(
                            value: c,
                            child: Row(
                              children: [
                                Icon(
                                  c.id == currentId
                                      ? Icons.check
                                      : Icons.folder_outlined,
                                  size: 18,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    c.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: titleStyle,
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down),
                        ],
                      ),
                    ),
                  )
                : Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
          ),
        ],
      ),
    );
  }
}
