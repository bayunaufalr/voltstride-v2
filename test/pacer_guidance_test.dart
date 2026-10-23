import 'package:flutter_test/flutter_test.dart';
import 'package:voltstride/features/running/services/pacer_guidance.dart';

void main() {
  group('PacerGuidance', () {
    test('calculates required remaining pace for target average', () {
      final PacerGuidance result = PacerGuidance.calculate(
        targetDistanceKm: 5,
        targetAveragePaceSecondsPerKm: 300,
        currentDistanceKm: 1,
        elapsed: const Duration(minutes: 6),
      );

      expect(result.targetAchievable, isTrue);
      expect(result.remainingDistanceKm, 4);
      expect(result.requiredRemainingPaceSecondsPerKm, closeTo(285, 0.01));
    });

    test('marks a target unreachable after its total time budget is spent', () {
      final PacerGuidance result = PacerGuidance.calculate(
        targetDistanceKm: 5,
        targetAveragePaceSecondsPerKm: 300,
        currentDistanceKm: 1,
        elapsed: const Duration(minutes: 26),
      );

      expect(result.targetAchievable, isFalse);
      expect(result.requiredRemainingPaceSecondsPerKm, isNull);
    });

    test('marks a target distance already reached', () {
      final PacerGuidance result = PacerGuidance.calculate(
        targetDistanceKm: 5,
        targetAveragePaceSecondsPerKm: 300,
        currentDistanceKm: 5,
        elapsed: const Duration(minutes: 24),
      );

      expect(result.targetReached, isTrue);
      expect(result.targetAchievable, isFalse);
    });
  });
}
