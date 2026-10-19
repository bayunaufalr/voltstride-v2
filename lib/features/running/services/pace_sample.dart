/// Sampel kumulatif internal untuk menghitung current pace dalam jendela waktu.
class PaceSample {
  const PaceSample({
    required this.timestamp,
    required this.distanceMeters,
  });

  final DateTime timestamp;
  final double distanceMeters;
}
