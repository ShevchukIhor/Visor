import 'package:flutter/material.dart';

import '../core/db/vision_db.dart';
import '../core/exercises/exercise_painter.dart';
import '../core/gabor/gabor_patch.dart';
import '../core/reminder/reminder_service.dart';
import '../core/theme/visor_theme.dart';
import '../core/training/template_repo.dart';
import '../core/training/training_step.dart';

/// Create or edit a routine: name, its steps, their order and durations.
///
/// `null` means a new routine. Editing a builtin keeps it builtin (only
/// `TemplateRepo.delete` treats builtins specially), so saving one in place
/// is an ordinary update, not a copy.
class TemplateEditorScreen extends StatefulWidget {
  const TemplateEditorScreen({super.key, required this.template});
  final Template? template;

  @override
  State<TemplateEditorScreen> createState() => _TemplateEditorScreenState();
}

class _TemplateEditorScreenState extends State<TemplateEditorScreen> {
  static const _durations = [15, 30, 45, 60, 90, 120, 180];

  late final TextEditingController _name;
  late List<TrainingStep> _steps;
  bool _saving = false;

  /// Set when the database write failed; drives the error line and the
  /// Retry save button. A failed save must re-enable Save instead of
  /// leaving it disabled forever with the edits silently lost.
  bool _saveError = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.template?.name ?? '');
    _steps = List.of(widget.template?.steps ?? const []);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _bumpDuration(int i, int delta) {
    final cur = _durations.indexOf(_steps[i].seconds);
    final next = (cur < 0 ? 3 : cur + delta).clamp(0, _durations.length - 1);
    setState(() => _steps[i] = _withSeconds(_steps[i], _durations[next]));
  }

  TrainingStep _withSeconds(TrainingStep s, int seconds) => switch (s) {
        ExerciseStep(:final type, :final gaborTarget) => ExerciseStep(
            type: type, seconds: seconds, gaborTarget: gaborTarget),
        GaborGameStep(:final difficulty, :final curved) => GaborGameStep(
            difficulty: difficulty, seconds: seconds, curved: curved),
        RestStep(:final cue) => RestStep(cue: cue, seconds: seconds),
        DrillStep(:final task) => DrillStep(task: task, seconds: seconds),
      };

  /// DrillStep is reserved for the (unimplemented) psychophysical engine and
  /// is never offered here — only the eight exercises, the Gabor game and
  /// rest are addable. It survives only if it was already in a loaded
  /// template's steps, and `_withSeconds` above must keep handling it so a
  /// duration bump on such a step doesn't crash.
  void _addStepSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: VisorTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final type in ExerciseType.values)
              ListTile(
                title: Text(type.title,
                    style: const TextStyle(color: VisorTheme.text)),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(
                      () => _steps.add(ExerciseStep(type: type, seconds: 60)));
                },
              ),
            ListTile(
              title: const Text('Gabor Game',
                  style: TextStyle(color: VisorTheme.text)),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _steps.add(
                    GaborGameStep(difficulty: Difficulty.medium, seconds: 60)));
              },
            ),
            ListTile(
              title: const Text('Rest',
                  style: TextStyle(color: VisorTheme.text)),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _steps
                    .add(RestStep(cue: 'Blink slowly', seconds: 15)));
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final db = await VisionDb.instance.db;
      final repo = TemplateRepo(db);
      final existing = widget.template;
      final name = _name.text.trim();
      await repo.save(Template(
        id: existing?.id ?? 0,
        name: name.isEmpty ? 'Untitled routine' : name,
        builtin: existing?.builtin ?? false,
        steps: _steps,
      ));
      // Renaming a routine or changing its length must update the
      // notification text too, so republish the labels with the just-saved
      // state.
      await _publishLabels(repo);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      // Losing edits silently while the screen looks saved is worse than an
      // ugly message: the user would keep editing a routine that was never
      // written, and lose the work again.
      debugPrint('Failed to save routine: $e');
      if (!mounted) return;
      setState(() => _saveError = true);
    } finally {
      // A failed save must re-enable the Save button; a successful one has
      // already popped the screen (and unmounts it, so the guard is a no-op).
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Publishes the plan to the notification labels. Best effort: a failed
  /// channel call (no plugin in widget tests) must not break the UI.
  Future<void> _publishLabels(TemplateRepo repo) async {
    try {
      await ReminderService.publishWeekLabels(await weekLabels(repo));
    } catch (_) {}
  }

  String _mmss(int s) {
    final m = s ~/ 60;
    final r = s % 60;
    return '$m:${r.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final warnings = templateWarnings(_steps);
    return Scaffold(
      backgroundColor: VisorTheme.bg,
      appBar: AppBar(
        backgroundColor: VisorTheme.bg,
        foregroundColor: VisorTheme.text,
        title: TextField(
          controller: _name,
          style: const TextStyle(color: VisorTheme.text, fontSize: 18),
          decoration: const InputDecoration(
            border: InputBorder.none,
            hintText: 'Routine name',
            hintStyle: TextStyle(color: VisorTheme.textDim),
          ),
        ),
        actions: [
          // Never disabled by warnings: they describe load, and the user is
          // allowed to disagree.
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: _steps.isEmpty
              ? const Center(
                  child: Text('Add a step to get started',
                      style: TextStyle(color: VisorTheme.textDim)),
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _steps.length,
                  // `onReorderItem` (not the deprecated `onReorder`) already
                  // hands back `to` adjusted for the removed item at `from`.
                  onReorderItem: (from, to) => setState(() {
                    _steps.insert(to, _steps.removeAt(from));
                  }),
                  itemBuilder: (ctx, i) => Padding(
                    key: ValueKey(i),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _stepTile(i),
                  ),
                ),
        ),
        if (_saveError) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Row(children: [
              const Icon(Icons.error_outline,
                  color: VisorTheme.danger, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                    'Could not save this routine — your changes are not '
                    'stored.',
                    style: const TextStyle(
                        color: VisorTheme.danger, fontSize: 11, height: 1.3)),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextButton(
              onPressed: _save,
              child: const Text('Retry save'),
            ),
          ),
        ],
        for (final w in warnings)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Row(children: [
              const Icon(Icons.info_outline,
                  color: VisorTheme.accent, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(w,
                    style: const TextStyle(
                        color: VisorTheme.accent, fontSize: 11, height: 1.3)),
              ),
            ]),
          ),
        const SizedBox(height: 8),
      ]),
      floatingActionButton: FloatingActionButton(
        onPressed: _addStepSheet,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _stepTile(int i) {
    final s = _steps[i];
    return Material(
      color: VisorTheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(children: [
          const Icon(Icons.drag_handle, color: VisorTheme.textDim, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(s.title,
                style: const TextStyle(
                    color: VisorTheme.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
          ),
          IconButton(
            icon: const Icon(Icons.remove, color: VisorTheme.textDim, size: 18),
            onPressed: () => _bumpDuration(i, -1),
          ),
          SizedBox(
            width: 44,
            child: Text(_mmss(s.seconds),
                textAlign: TextAlign.center,
                style: const TextStyle(color: VisorTheme.text, fontSize: 13)),
          ),
          IconButton(
            icon: const Icon(Icons.add, color: VisorTheme.textDim, size: 18),
            onPressed: () => _bumpDuration(i, 1),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: VisorTheme.danger, size: 18),
            onPressed: () => setState(() => _steps.removeAt(i)),
          ),
        ]),
      ),
    );
  }
}
