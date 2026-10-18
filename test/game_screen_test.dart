import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visor/core/gabor/gabor_patch.dart';
import 'package:visor/core/models/session_setup.dart';
import 'package:visor/screens/game_screen.dart';
import 'package:visor/widgets/gabor_view.dart';

import 'wakelock_mock.dart';

/// Exit-guard coverage for the Gabor game: a session with answered trials
/// must confirm before it is discarded, a fresh one must not.
///
/// Timing note: GaborView decodes its image on the real event loop, which
/// never runs inside the fake-async pump zone. Undecoded cells show an
/// indeterminate spinner, and an indeterminate spinner animates forever —
/// so a bare `pumpAndSettle` would pump the whole 60 s session to its end
/// before returning. Every section that must settle therefore first yields
/// to the real loop inside `tester.runAsync` so the decodes land.
void main() {
  Widget harness(GameScreen game) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => game),
              ),
              child: const Text('start'),
            ),
          ),
        ),
      ),
    );
  }

  /// Installs the wakelock mock before the screen mounts (a GameScreen
  /// takes the wakelock in initState) and returns the toggle log.
  Future<List<bool>> startGame(WidgetTester tester) async {
    final calls = mockWakelock(tester);
    await tester.runAsync(() async {
      await tester.pumpWidget(harness(GameScreen(
        setup: const SessionSetup(
          durationS: 60,
          difficulty: Difficulty.easy,
          curved: false,
        ),
      )));
      await tester.tap(find.text('start'));
      // Build the game screen so its GaborViews start decoding — the
      // decode must be in flight before the real-time wait below, because
      // the engine's callback is only delivered while the test yields to
      // the real event loop (runAsync), never from the fake pump zone.
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await tester.pump();
    });
    await tester.pumpAndSettle(); // the route transition
    expect(find.byType(GameScreen), findsOneWidget);
    return calls;
  }

  testWidgets('a fresh session exits without confirmation', (tester) async {
    await startGame(tester);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byType(GameScreen), findsNothing,
        reason: 'no trials answered, nothing to lose — just go back');
  });

  testWidgets('a session with progress confirms before exiting',
      (tester) async {
    await startGame(tester);
    // Answer one trial so the session carries progress. The answer index is
    // random, so the score line reads either ✓ 1 / ✗ 0 or ✓ 0 / ✗ 1.
    await tester.tap(find.descendant(
      of: find.byType(GridView),
      matching: find.byType(GaborView),
    ).first);
    await tester.pump();
    expect(
      find.text('✓ 1   ✗ 0').evaluate().isNotEmpty ||
          find.text('✓ 0   ✗ 1').evaluate().isNotEmpty,
      isTrue,
      reason: 'the top bar must show the answered trial',
    );
    // The tap scheduled a prewarm (post-frame) and the 650 ms trial swap
    // (fake clock). Run the prewarm, let its decodes land in real time,
    // then advance the fake clock past the swap so the new trial renders
    // from the cache — no spinners left to break the settles below.
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump(const Duration(milliseconds: 700));
    // Closing now must ask first.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('End session?'), findsOneWidget);
    // Cancel keeps the session running.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(GameScreen), findsOneWidget);
    // End leaves it.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    await tester.tap(find.text('End'));
    await tester.pumpAndSettle();
    expect(find.byType(GameScreen), findsNothing);
  });

  testWidgets('the session holds the wakelock and releases it on exit',
      (tester) async {
    final calls = await startGame(tester);
    expect(calls, [true],
        reason: 'the session takes the wakelock on start — studying a grid '
            'can outlast the device screen timeout');
    // A fresh session exits without confirmation; the dispose path must
    // release the wakelock.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byType(GameScreen), findsNothing);
    expect(calls, [true, false],
        reason: 'exiting the session releases the wakelock');
  });
}
