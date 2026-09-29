/// `Drill.task` for the Gabor patch discrimination game. Named once so tasks
/// 2-8, which add more task ids to the same table (exercises, measured
/// psychophysical drills), never risk a typo'd literal silently falling out
/// of a filter.
const String taskGaborGrid = 'gabor_grid';

/// One recorded unit of training: a Gabor game, an eye exercise, or — once the
/// psychophysical engine lands — a measured drill. Replaces VisionSession.
class Drill {
  final int id;
  final DateTime startedAt;
  final String task;
  final int durationS;
  final bool completed;
  final int trials;
  final int correct;
  final double? threshold;
  final String? thresholdUnit;
  final String? reversals;
  final int? geometryId;
  final double? score;
  final int? templateId;
  final String? params;

  const Drill({
    this.id = 0,
    required this.startedAt,
    required this.task,
    required this.durationS,
    this.completed = true,
    this.trials = 0,
    this.correct = 0,
    this.threshold,
    this.thresholdUnit,
    this.reversals,
    this.geometryId,
    this.score,
    this.templateId,
    this.params,
  });

  Map<String, Object?> toMap() => {
        'started_at': startedAt.millisecondsSinceEpoch,
        'task': task,
        'duration_s': durationS,
        'completed': completed ? 1 : 0,
        'trials': trials,
        'correct': correct,
        'threshold': threshold,
        'threshold_unit': thresholdUnit,
        'reversals': reversals,
        'geometry_id': geometryId,
        'score': score,
        'template_id': templateId,
        'params': params,
      };

  factory Drill.fromMap(Map<String, Object?> m) => Drill(
        id: m['id'] as int,
        startedAt:
            DateTime.fromMillisecondsSinceEpoch(m['started_at'] as int),
        task: m['task'] as String,
        durationS: m['duration_s'] as int,
        completed: (m['completed'] as int) == 1,
        trials: m['trials'] as int,
        correct: m['correct'] as int,
        threshold: (m['threshold'] as num?)?.toDouble(),
        thresholdUnit: m['threshold_unit'] as String?,
        reversals: m['reversals'] as String?,
        geometryId: m['geometry_id'] as int?,
        score: (m['score'] as num?)?.toDouble(),
        templateId: m['template_id'] as int?,
        params: m['params'] as String?,
      );
}
