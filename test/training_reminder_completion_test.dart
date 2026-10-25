import 'package:flutter_test/flutter_test.dart';
import 'package:voltstride/features/reminders/reminder_service.dart';

void main() {
  test('status selesai tetap tersimpan saat jadwal dibuka ulang', () {
    final TrainingReminder reminder = TrainingReminder(
      id: 7,
      activity: 'Lari',
      weekdays: const <int>[DateTime.monday, DateTime.friday],
      hour: 7,
      minute: 30,
      durationMinutes: 40,
      style: ReminderStyle.notificationOnly,
      sound: 'lembut',
      completedDates: const <String>['2026-10-19'],
    );

    final TrainingReminder decoded = TrainingReminder.fromJson(
      Map<String, dynamic>.from(reminder.toJson()),
    );

    expect(decoded.completedDates, contains('2026-10-19'));
    expect(decoded.weekdays, <int>[DateTime.monday, DateTime.friday]);
    expect(decoded.style, ReminderStyle.notificationOnly);
  });

  test('status tidak terlaksana dan alasan tersimpan setelah JSON dibuka ulang', () {
    final TrainingReminder reminder = TrainingReminder(
      id: 11,
      activity: 'Lari',
      weekdays: const <int>[DateTime.tuesday],
      hour: 7,
      minute: 0,
      durationMinutes: 30,
      style: ReminderStyle.notificationOnly,
      sound: 'lembut',
    );

    final TrainingReminder missed = reminder.copyWith(
      notCompletedDates: const <String>['2026-10-27'],
      notCompletedReasons: const <String, String>{
        '2026-10-27': 'Cuaca tidak mendukung',
      },
    );
    final TrainingReminder decoded = TrainingReminder.fromJson(
      Map<String, dynamic>.from(missed.toJson()),
    );

    expect(decoded.notCompletedDates, contains('2026-10-27'));
    expect(
      decoded.notCompletedReasons['2026-10-27'],
      'Cuaca tidak mendukung',
    );
    expect(decoded.completedDates, isEmpty);
  });

  test('jadwal per tanggal menyimpan tanggal dan tidak memerlukan hari rutin', () {
    final TrainingReminder reminder = TrainingReminder(
      id: 15,
      activity: 'Jalan',
      weekdays: const <int>[],
      scheduleType: ReminderScheduleType.specificDate,
      specificDate: DateTime(2026, 11, 14),
      hour: 9,
      minute: 45,
      durationMinutes: 25,
      style: ReminderStyle.notificationOnly,
      sound: 'lembut',
    );

    final TrainingReminder decoded = TrainingReminder.fromJson(
      Map<String, dynamic>.from(reminder.toJson()),
    );

    expect(decoded.scheduleType, ReminderScheduleType.specificDate);
    expect(decoded.specificDate, DateTime(2026, 11, 14));
    expect(decoded.weekdays, isEmpty);
    expect(decoded.timeText, '09:45');
  });

  test('jadwal per tanggal cocok berdasarkan tanggal, bukan jam', () {
    final TrainingReminder reminder = TrainingReminder(
      id: 21,
      activity: 'Lari',
      weekdays: const <int>[],
      scheduleType: ReminderScheduleType.specificDate,
      specificDate: DateTime(2026, 11, 14),
      hour: 7,
      minute: 0,
      durationMinutes: 30,
      style: ReminderStyle.notificationOnly,
      sound: 'lembut',
    );

    expect(
      ReminderService.matchesScheduledDate(
        reminder,
        DateTime(2026, 11, 14, 22, 45),
      ),
      isTrue,
    );
    expect(
      ReminderService.matchesScheduledDate(reminder, DateTime(2026, 11, 15)),
      isFalse,
    );
    expect(ReminderService.matchesActivityCategory(reminder, 'run'), isTrue);
    expect(ReminderService.matchesActivityCategory(reminder, 'walk'), isFalse);
  });

  test('jadwal rutin cocok pada hari yang dipilih tanpa membatasi jam', () {
    const TrainingReminder reminder = TrainingReminder(
      id: 22,
      activity: 'Jalan',
      weekdays: <int>[DateTime.saturday],
      hour: 6,
      minute: 30,
      durationMinutes: 20,
      style: ReminderStyle.notificationOnly,
      sound: 'lembut',
    );

    expect(
      ReminderService.matchesScheduledDate(
        reminder,
        DateTime(2026, 10, 31, 19, 10),
      ),
      isTrue,
    );
    expect(ReminderService.matchesActivityCategory(reminder, 'walk'), isTrue);
  });

  test('menandai satu kejadian tidak mengubah jadwal berulangnya', () {
    const TrainingReminder reminder = TrainingReminder(
      id: 9,
      activity: 'Lari interval',
      weekdays: <int>[DateTime.tuesday, DateTime.thursday],
      hour: 18,
      minute: 15,
      durationMinutes: 35,
      style: ReminderStyle.notificationOnly,
      sound: 'lembut',
    );

    final TrainingReminder completed = reminder.copyWith(
      completedDates: const <String>['2026-10-20'],
    );

    expect(completed.weekdays, reminder.weekdays);
    expect(completed.timeText, reminder.timeText);
    expect(completed.completedDates, <String>['2026-10-20']);
    expect(reminder.completedDates, isEmpty);
  });
}
