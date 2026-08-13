import 'package:depools/app/support/scan_presence.dart';
import 'package:flutter_test/flutter_test.dart';

/// When a code in front of the camera is a new carton.
///
/// The defect these tests pin was reported from a real scan: one carton, held steady, counted twice.
/// `detectionTimeoutMs` is a timer, and on a screen whose camera never closes a held label is the
/// ordinary case, so the timer fires again and again over one presentation.
void main() {
  final DateTime t0 = DateTime.utc(2026, 8, 13, 12);

  test('the first sighting counts', () {
    expect(ScanPresence().shouldCount('869', t0), isTrue);
  });

  test('a label held in view counts once, however long it is held', () {
    // The reported bug, as a test. Frames arrive every ~100ms for three seconds; without edge
    // detection a 1.2s timer would have counted this three times.
    final ScanPresence gate = ScanPresence();
    int counted = 0;

    for (int ms = 0; ms <= 3000; ms += 100) {
      if (gate.shouldCount('869', t0.add(Duration(milliseconds: ms)))) counted++;
    }

    expect(counted, 1);
  });

  test('a second carton counts once the first has left the frame', () {
    // The other half, and the reason `noDuplicates` is the wrong answer: two cartons of the same
    // milk are two units, and a rule that cannot see the gap cannot see the second one.
    final ScanPresence gate = ScanPresence();

    expect(gate.shouldCount('869', t0), isTrue);
    // Out of frame for a second: longer than the grace, so this is a new presentation.
    expect(gate.shouldCount('869', t0.add(const Duration(milliseconds: 1000))), isTrue);
  });

  test('a decode dropout of a few frames is not a new carton', () {
    // A hand passing over the label, a glare or a focus hunt drops the code for a frame or two.
    // Without the grace period that flicker is the double-count arriving by the other road.
    final ScanPresence gate = ScanPresence();

    expect(gate.shouldCount('869', t0), isTrue);
    expect(gate.shouldCount('869', t0.add(const Duration(milliseconds: 300))), isFalse);
  });

  test('two different codes in one frame both count', () {
    // A shelf can show two labels at once, and neither suppresses the other: the gate is per code.
    final ScanPresence gate = ScanPresence();

    expect(gate.shouldCount('869', t0), isTrue);
    expect(gate.shouldCount('870', t0), isTrue);
  });

  test('a code held in view keeps its sighting recorded even while it does not count', () {
    // The subtle one. If a non-counting sighting were not recorded, a held label would look absent
    // as soon as its own gap elapsed and would count again: the bug, with extra steps.
    final ScanPresence gate = ScanPresence();

    gate.shouldCount('869', t0);

    for (int ms = 100; ms <= 2000; ms += 100) {
      expect(
        gate.shouldCount('869', t0.add(Duration(milliseconds: ms))),
        isFalse,
        reason: 'at ${ms}ms',
      );
    }
  });

  test('codes long gone are forgotten', () {
    final ScanPresence gate = ScanPresence();

    gate.shouldCount('869', t0);
    expect(gate.trackedCount, 1);

    gate.prune(t0.add(const Duration(minutes: 1)));
    expect(gate.trackedCount, 0);
  });
}
