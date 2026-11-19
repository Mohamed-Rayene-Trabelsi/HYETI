import 'package:material_ui/material_ui.dart';

import 'theme.dart';
import 'ui.dart';

/// A chip that shows the genre a list is filtered by and opens a sheet to pick another.
class GenreChip extends StatelessWidget {
  const GenreChip({super.key, required this.options, required this.value, required this.onChanged});

  /// The genres to offer, in display order.
  final List<String> options;

  /// The genre in use; null for all of them.
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppChip(
      value ?? 'All genres',
      icon: Icons.tune,
      selected: value != null,
      onPressed: () => showSheet(
        context,
        title: 'Filter by genre',
        builder: (sheet) {
          void pick(String? genre) {
            Navigator.pop(sheet);
            if (genre != value) onChanged(genre);
          }

          return Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              AppChip('All genres', selected: value == null, onPressed: () => pick(null)),
              for (final g in options) AppChip(g, selected: g == value, onPressed: () => pick(g)),
            ],
          );
        },
      ),
    );
  }
}
