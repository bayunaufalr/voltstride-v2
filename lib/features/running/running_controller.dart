import 'package:flutter/foundation.dart';

import 'models/run_session.dart';
import 'services/running_engine.dart';

/// Controller tipis untuk menjembatani engine dan UI.
///
/// UI tidak perlu tahu detail Geolocator. Semua aksi yang relevan cukup
/// lewat controller ini, sehingga nanti API/storage dapat diganti tanpa
/// membongkar halaman lari.
class RunningController extends ChangeNotifier {
  RunningController({RunningEngine? engine})
      : _engine = engine ?? RunningEngine() {
    _engine.addListener(_forwardChanges);
  }

  final RunningEngine _engine;

  RunStatus get status => _engine.status;
  String? get errorMessage => _engine.errorMessage;
  bool get isActive => _engine.isActive;
  double get distanceKm => _engine.distanceKm;
  Duration get elapsed => _engine.elapsed;
  Duration get movingTime => _engine.movingTime;
  double? get currentPaceSecondsPerKm =>
      _engine.currentPaceSecondsPerKm;
  double? get averagePaceSecondsPerKm =>
      _engine.averagePaceSecondsPerKm;
  double? get gpsAccuracyMeters => _engine.gpsAccuracyMeters;
  double get gpsCleanRatio => _engine.gpsCleanRatio;
  int get acceptedPoints => _engine.acceptedPoints;
  int get rejectedPoints => _engine.rejectedPoints;
  List<RunSplit> get splits => _engine.splits;
  List<RunPoint> get route => _engine.route;
  List<RunLap100m> get hundredMeterLaps => _engine.hundredMeterLaps;
  IntervalRunPlan? get intervalPlan => _engine.intervalPlan;
  RunSession? get lastFinishedSession =>
      _engine.lastFinishedSession;

  Future<void> startRun({
    IntervalRunPlan? intervalPlan,
    bool useGps = true,
    RunActivityType activityType = RunActivityType.run,
    RunEnvironment environment = RunEnvironment.outdoor,
  }) => _engine.start(
        intervalPlan: intervalPlan,
        useGps: useGps,
        activityType: activityType,
        environment: environment,
      );

  void pauseRun() => _engine.pause();

  void resumeRun() => _engine.resume();

  RunSession? finishRun({double? indoorDistanceMeters}) =>
      _engine.finish(indoorDistanceMeters: indoorDistanceMeters);

  void resetRun() => _engine.reset();

  @override
  void dispose() {
    _engine.removeListener(_forwardChanges);
    _engine.dispose();
    super.dispose();
  }

  void _forwardChanges() {
    notifyListeners();
  }
}
