import 'package:material_ui/material_ui.dart';

import '../date.dart';
import '../db.dart';
import '../sketch.dart';
import '../theme.dart';
import '../ui.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> with Live {
  final _search = TextEditingController();
  List<Rec> _notes = [];

  @override
  Future<void> load() async {
    final like = '%${_search.text.trim()}%';
    _notes = await appDb.query(
      'SELECT * FROM notes WHERE title LIKE ? OR body LIKE ? ORDER BY pinned DESC, updated_at DESC',
      [like, like],
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Opens a note in the editor for its kind; with no note, starts a new written one or a new [sketch].
  void _open(Rec? note, {bool sketch = false}) {
    final drawing = sketch || note?['sketch'] != null;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => drawing ? SketchEditor(note: note) : NoteEditor(note: note),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final searching = _search.text.trim().isNotEmpty;
    final pinned = _notes.where((n) => n['pinned'] == 1).toList();
    final rest = _notes.where((n) => n['pinned'] != 1).toList();

    return Screen(
      title: 'Notes',
      subtitle: '${_notes.length} ${_notes.length == 1 ? 'note' : 'notes'}',
      actions: [HeaderIcon(Icons.brush_outlined, label: 'New sketch', onPressed: () => _open(null, sketch: true))],
      fabLabel: 'New note',
      fabIcon: Icons.edit_outlined,
      onFab: () => _open(null),
      children: [
        if (_notes.isNotEmpty || searching)
          Field(
            controller: _search,
            icon: Icons.search,
            hint: 'Search notes',
            textInputAction: TextInputAction.search,
            onChanged: (_) => reload(),
          ),
        if (ready && _notes.isEmpty)
          Empty(
            icon: searching ? Icons.search_off : Icons.sticky_note_2_outlined,
            title: searching ? 'No matches' : 'No notes yet',
            hint: searching ? 'Try a different word.' : 'Tap “New note” to write one, or the brush to draw one.',
          ),
        if (pinned.isNotEmpty)
          Section(
            title: 'Pinned',
            children: [for (final n in pinned) _NoteCard(note: n, onTap: () => _open(n))],
          ),
        if (rest.isNotEmpty)
          Section(
            title: pinned.isNotEmpty ? 'Others' : 'All notes',
            children: [for (final n in rest) _NoteCard(note: n, onTap: () => _open(n))],
          ),
      ],
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note, required this.onTap});

  final Rec note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = note['title'] as String;
    final body = note['body'] as String;
    final firstLine = body.split('\n').first;
    final updated = DateTime.fromMillisecondsSinceEpoch(note['updated_at'] as int);
    final sketch = note['sketch'] as String?;
    if (sketch != null) {
      final c = context.colors;
      // A drawing shows as a small picture beside its title.
      return AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(Spacing.md),
        children: [
          Row(
            spacing: Spacing.md,
            children: [
              Container(
                width: 66,
                height: 66 / sketchAspect,
                decoration: BoxDecoration(
                  color: c.surfaceAlt,
                  borderRadius: BorderRadius.circular(Radii.sm),
                  border: Border.all(color: c.border, width: 0.5),
                ),
                child: CustomPaint(painter: SketchPainter(decodeSketch(sketch), ink: c.text)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: Spacing.xs,
                  children: [
                    T(title.isNotEmpty ? title : 'Sketch', variant: TextVariant.heading, maxLines: 2),
                    T('Sketch · ${relativeDay(toKey(updated))}', variant: TextVariant.small, dim: true),
                  ],
                ),
              ),
              if (note['pinned'] == 1) Icon(Icons.push_pin, size: 16, color: c.accent),
            ],
          ),
        ],
      );
    }
    return AppCard(
      onTap: onTap,
      spacing: Spacing.xs,
      children: [
        Row(
          spacing: Spacing.sm,
          children: [
            Expanded(
              child: T(
                title.isNotEmpty ? title : (firstLine.isNotEmpty ? firstLine : 'Untitled'),
                variant: TextVariant.heading,
                maxLines: 1,
              ),
            ),
            if (note['pinned'] == 1) Icon(Icons.push_pin, size: 16, color: context.colors.accent),
          ],
        ),
        if (title.isNotEmpty && body.trim().isNotEmpty) T(body.trim(), dim: true, maxLines: 3),
        T(relativeDay(toKey(updated)), variant: TextVariant.small, dim: true),
      ],
    );
  }
}

/// Full-screen editor. Saves when closed; an empty note is discarded.
class NoteEditor extends StatefulWidget {
  const NoteEditor({super.key, this.note});

  final Rec? note;

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late final _title = TextEditingController(text: widget.note?['title'] as String? ?? '');
  late final _body = TextEditingController(text: widget.note?['body'] as String? ?? '');
  late bool _pinned = widget.note?['pinned'] == 1;
  bool _closing = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _saveAndClose() async {
    if (_closing) return;
    _closing = true;
    final note = widget.note;
    final title = _title.text.trim();
    final body = _body.text;
    final empty = title.isEmpty && body.trim().isEmpty;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (note != null && empty) {
      await appDb.run('DELETE FROM notes WHERE id = ?', [note['id']]);
    } else if (note != null) {
      final changed = _title.text != note['title'] || body != note['body'];
      await appDb.run('UPDATE notes SET title = ?, body = ?, pinned = ?, updated_at = ? WHERE id = ?', [
        title,
        body,
        _pinned ? 1 : 0,
        changed ? now : note['updated_at'],
        note['id'],
      ]);
    } else if (!empty) {
      await appDb.insert('INSERT INTO notes (title, body, pinned, updated_at) VALUES (?, ?, ?, ?)', [
        title,
        body,
        _pinned ? 1 : 0,
        now,
      ]);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    if (_closing) return;
    _closing = true;
    await deleteWithUndo('notes', widget.note!, 'Note deleted');
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const bare = InputDecoration(border: InputBorder.none, isDense: true);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _saveAndClose();
      },
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
                  child: Row(
                    spacing: Spacing.sm,
                    children: [
                      AppButton('‹ Done', kind: ButtonKind.plain, small: true, onPressed: _saveAndClose),
                      const Spacer(),
                      AppButton(
                        _pinned ? 'Pinned ✓' : 'Pin',
                        kind: ButtonKind.soft,
                        small: true,
                        onPressed: () => setState(() => _pinned = !_pinned),
                      ),
                      if (widget.note != null)
                        AppButton('Delete', kind: ButtonKind.danger, small: true, onPressed: _delete),
                    ],
                  ),
                ),
                TextField(
                  controller: _title,
                  textCapitalization: TextCapitalization.sentences,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: c.text),
                  decoration: bare.copyWith(
                    hintText: 'Title',
                    hintStyle: TextStyle(color: c.textDim),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _body,
                    autofocus: widget.note == null,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    textCapitalization: TextCapitalization.sentences,
                    keyboardType: TextInputType.multiline,
                    style: TextStyle(fontSize: 16, height: 1.5, color: c.text),
                    decoration: bare.copyWith(
                      hintText: 'Start writing…',
                      hintStyle: TextStyle(color: c.textDim),
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
