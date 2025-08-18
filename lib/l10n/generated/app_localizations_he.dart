// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hebrew (`he`).
class AppLocalizationsHe extends AppLocalizations {
  AppLocalizationsHe([String locale = 'he']) : super(locale);

  @override
  String get appTitle => 'צ\'ורביד';

  @override
  String get tabActive => 'פעיל';

  @override
  String get tabHistory => 'היסטוריה';

  @override
  String get availableChores => 'משימות זמינות';

  @override
  String get myWork => 'המשימות שלי';

  @override
  String get claimed => 'שלי';

  @override
  String get waitingReview => 'ממתין לאישור';

  @override
  String get waitingPayment => 'ממתין לתשלום';

  @override
  String get paid => 'שולם';

  @override
  String get paidThisMonth => 'שולם החודש';

  @override
  String get expiredMissed => 'פג תוקף — הוחמץ';

  @override
  String get noChoresNow => 'אין משימות זמינות כרגע.';

  @override
  String get noHistory => 'אין היסטוריה עדיין.';

  @override
  String get acceptChoreQ => 'לקחת את המשימה?';

  @override
  String get choreOptions => 'אפשרויות משימה';

  @override
  String get yes => 'כן';

  @override
  String get no => 'לא';

  @override
  String get done => 'סיימתי';

  @override
  String get unclaim => 'ביטול מטלה';

  @override
  String deadlineShort(String time) {
    return 'לפני $time';
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
