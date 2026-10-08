import 'package:flutter/material.dart';

import '../core/db/vision_db.dart';
import '../core/reminder/reminder_service.dart';
import '../core/theme/visor_theme.dart';
import '../core/training/template_repo.dart';
import '../core/training/training_step.dart';
import 'session_runner.dart';
import 'template_editor_screen.dart';

/// List of saved routines, each launchable in one tap.
///
/// A routine's steps are fixed once it starts (see `SessionRunner`), so the
/// only decisions this screen makes are: which routine, and whether it is
/// even worth starting.
class TemplatesScreen extends StatefulWidget {
  const TemplatesScreen({super.key});

  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  TemplateRepo? _repo;
  List<Template> _templates = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final db = await VisionDb.instance.db;
    if (!mounted) return;
    _repo = TemplateRepo(db);
    await _load();
  }

  /// Seeds the four presets on first run — idempotent, so calling it on
  /// every load is cheap and keeps the list from ever being an empty page.
  Future<void> _load() async {
    final repo = _repo;
    if (repo == null) return;
    await repo.seedPresets();
    final all = await repo.all();
    if (!mounted) return;
    setState(() {
      _templates = all;
      _loading = false;
    });
  }

  Future<void> _duplicate(Template t) async {
    final repo = _repo;
    if (repo == null) return;
    await repo.save(Template(
      id: 0,
      name: '${t.name} copy',
      builtin: false,
      steps: t.steps,
    ));
    await _load();
  }

  Future<void> _confirmDelete(Template t) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: VisorTheme.surface,
        title: const Text('Delete routine?',
            style: TextStyle(color: VisorTheme.text)),
        content: Text('"${t.name}" will be removed permanently.',
            style: const TextStyle(color: VisorTheme.textDim)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(color: VisorTheme.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final repo = _repo;
    if (repo == null) return;
    await repo.delete(t.id);
    // The native week labels still carry the deleted routine's name, so the
    // next reminder would name a routine that no longer exists. Republish
    // with the post-delete state. Best effort: a failed channel call must
    // not break the delete.
    try {
      await ReminderService.publishWeekLabels(await weekLabels(repo));
    } catch (_) {}
    await _load();
  }

  /// Builtins can be run, copied and edited, but never deleted — offer
  /// Duplicate in their place rather than a Delete action that would only
  /// silently fail.
  void _showActionSheet(Template t) {
    showModalBottomSheet(
      context: context,
      backgroundColor: VisorTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (t.builtin)
              ListTile(
                leading:
                    const Icon(Icons.copy_outlined, color: VisorTheme.text),
                title: const Text('Duplicate',
                    style: TextStyle(color: VisorTheme.text)),
                onTap: () {
                  Navigator.pop(ctx);
                  _duplicate(t);
                },
              )
            else
              ListTile(
                leading: const Icon(Icons.delete_outline,
                    color: VisorTheme.danger),
                title: const Text('Delete',
                    style: TextStyle(color: VisorTheme.danger)),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDelete(t);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VisorTheme.bg,
      appBar: AppBar(
        backgroundColor: VisorTheme.bg,
        foregroundColor: VisorTheme.text,
        title: const Text('Routines'),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: VisorTheme.primary))
          : _templates.isEmpty
              ? const Center(
                  child: Text('No routines yet',
                      style: TextStyle(color: VisorTheme.textDim)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _templates.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (ctx, i) => _row(_templates[i]),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const TemplateEditorScreen(template: null)),
        ).then((_) => _load()),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _row(Template t) {
    final runnable = isRunnable(t.steps);
    final mins = (t.totalSeconds / 60).round();
    return Material(
      color: VisorTheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        // Review Focus 1: a routine with nothing but rest has nothing to run.
        onTap: runnable
            ? () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => SessionRunner(template: t)),
                ).then((_) => _load())
            : null,
        onLongPress: () => _showActionSheet(t),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.name,
                      style: const TextStyle(
                          color: VisorTheme.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(
                    runnable
                        ? '${t.steps.length} steps · ~$mins min'
                        : 'Add an exercise to run this routine',
                    style: TextStyle(
                        color: runnable
                            ? VisorTheme.textDim
                            : VisorTheme.accent,
                        fontSize: 12),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined,
                  color: VisorTheme.textDim, size: 20),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => TemplateEditorScreen(template: t)),
              ).then((_) => _load()),
            ),
            Icon(Icons.play_circle_outline,
                color: runnable
                    ? VisorTheme.primary
                    : VisorTheme.textDim.withValues(alpha: 0.4),
                size: 26),
          ]),
        ),
      ),
    );
  }
}
