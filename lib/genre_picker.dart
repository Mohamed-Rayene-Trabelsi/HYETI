import 'package:material_ui/material_ui.dart';

import 'theme.dart';
import 'ui.dart';

/// The sheet that picks a genre to filter by; null is all of them.
void openGenrePicker(
  BuildContext context, {
  required List<String> options,
  required String? value,
  required ValueChanged<String?> onChanged,
}) {
  showSheet(
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
  );
}

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
      onPressed: () => openGenrePicker(context, options: options, value: value, onChanged: onChanged),
    );
  }
}

/// A square filter button the height of a search field, to sit beside one. Tinted while a genre is chosen.
class GenreButton extends StatelessWidget {
  const GenreButton({super.key, required this.options, required this.value, required this.onChanged});

  final List<String> options;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final on = value != null;
    return Semantics(
      button: true,
      label: on ? 'Genre: $value. Change genre' : 'Filter by genre',
      excludeSemantics: true,
      child: Tooltip(
        message: 'Filter by genre',
        child: Material(
          color: on ? c.accent.withValues(alpha: 0.16) : c.surfaceAlt,
          shape: buttonShape.copyWith(
            side: BorderSide(color: on ? c.accent : c.border, width: on ? 1.5 : 0.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              tick();
              openGenrePicker(context, options: options, value: value, onChanged: onChanged);
            },
            child: SizedBox(width: 48, height: 48, child: Icon(Icons.tune, size: 20, color: on ? c.accent : c.text)),
          ),
        ),
      ),
    );
  }
}
