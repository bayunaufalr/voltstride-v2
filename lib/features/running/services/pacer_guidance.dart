/// Calculations for a distance-and-average-pace running target.
/// The recommendation is mathematical pacing guidance, not a safety guarantee.
class PacerGuidance {
  const PacerGuidance({
    required this.targetDistanceKm,
    required this.targetAveragePaceSecondsPerKm,
    required this.currentDistanceKm,
    required this.remainingDistanceKm,
    required this.targetReached,
    required this.targetAchievable,
    required this.remainingTimeSeconds,
    required this.requiredRemainingPaceSecondsPerKm,
  });

  final double targetDistanceKm;
  final double targetAveragePaceSecondsPerKm;
  final double currentDistanceKm;
  final double remainingDistanceKm;
  final bool targetReached;
  final bool targetAchievable;
  final double remainingTimeSeconds;
  final double? requiredRemainingPaceSecondsPerKm;

  factory PacerGuidance.calculate({
    required double targetDistanceKm,
    required double targetAveragePaceSecondsPerKm,
    required double currentDistanceKm,
    required Duration elapsed,
  }) {
    final double safeTargetDistance =
        targetDistanceKm.isFinite && targetDistanceKm > 0
            ? targetDistanceKm
            : 0;
    final double safeTargetPace =
        targetAveragePaceSecondsPerKm.isFinite &&
                targetAveragePaceSecondsPerKm > 0
            ? targetAveragePaceSecondsPerKm
            : 0;
    final double safeCurrentDistance = currentDistanceKm.isFinite
        ? currentDistanceKm.clamp(0.0, safeTargetDistance).toDouble()
        : 0;
    final double remainingDistance = (safeTargetDistance - safeCurrentDistance)
        .clamp(0.0, safeTargetDistance)
        .toDouble();
    final double totalTimeBudget = safeTargetDistance * safeTargetPace;
    final double remainingTime = totalTimeBudget - elapsed.inSeconds;
    final bool reached = safeTargetDistance > 0 &&
        currentDistanceKm >= safeTargetDistance;
    final bool achievable = safeTargetDistance > 0 &&
        safeTargetPace > 0 &&
        remainingTime > 0 &&
        remainingDistance > 0;

    return PacerGuidance(
      targetDistanceKm: safeTargetDistance,
      targetAveragePaceSecondsPerKm: safeTargetPace,
      currentDistanceKm: safeCurrentDistance,
      remainingDistanceKm: remainingDistance,
      targetReached: reached,
      targetAchievable: achievable,
      remainingTimeSeconds: remainingTime > 0 ? remainingTime : 0,
      requiredRemainingPaceSecondsPerKm: achievable
          ? remainingTime / remainingDistance
          : null,
    );
  }
}
