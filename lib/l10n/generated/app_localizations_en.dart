// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Chorebid';

  @override
  String get tabActive => 'Active';

  @override
  String get tabHistory => 'History';

  @override
  String get availableChores => 'Available Chores';

  @override
  String get myWork => 'My Work';

  @override
  String get claimed => 'Claimed';

  @override
  String get waitingReview => 'Waiting Review';

  @override
  String get waitingPayment => 'Waiting Payment';

  @override
  String get paid => 'Paid';

  @override
  String get paidThisMonth => 'Paid this month';

  @override
  String get expiredMissed => 'Expired — Missed';

  @override
  String get noChoresNow => 'No chores available right now.';

  @override
  String get noHistory => 'No history yet.';

  @override
  String get acceptChoreQ => 'Do you want to accept this chore?';

  @override
  String get choreOptions => 'Chore Options';

  @override
  String get yes => 'Yes';

  @override
  String get no => 'No';

  @override
  String get done => 'Done';

  @override
  String get unclaim => 'Unclaim';

  @override
  String deadlineShort(String time) {
    return 'Before $time';
  }

  @override
  String countLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count',
      one: '1',
      zero: '0',
    );
    return '$_temp0';
  }
}
