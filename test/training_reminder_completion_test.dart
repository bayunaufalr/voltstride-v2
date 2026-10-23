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
