import 'package:flutter/services.dart';

/// Data sensor langkah Android tanpa plugin tambahan yang menerapkan KGP lama.
class StepCounterEvent {
  const StepCounterEvent({required this.steps, required this.timeStamp});

  final int steps;
  final DateTime timeStamp;
}

class StepCounterService {
  StepCounterService._();

  static const EventChannel _events =
      EventChannel('voltstride/step_count_events');

  static Stream<StepCounterEvent> get stepCountStream =>
      _events.receiveBroadcastStream().map((dynamic value) {
        if (value is! Map) {
          throw const FormatException('Format data sensor langkah tidak valid.');
        }
        final int steps = (value['steps'] as num).toInt();
        final int timestampMillis = (value['timestampMillis'] as num).toInt();
        return StepCounterEvent(
          steps: steps,
          timeStamp: DateTime.fromMillisecondsSinceEpoch(timestampMillis),
        );
      });
}
