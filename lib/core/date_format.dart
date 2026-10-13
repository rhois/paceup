import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Pemformatan tanggal yang aman.
///
/// `DateFormat` dengan locale `id_ID` akan melempar `LocaleDataException`
/// bila data locale belum dimuat. Memanggil `initializeDateFormatting()` setiap
/// saat mahal, jadi hasilnya di-cache di sini. Bila inisialisasi gagal (mis. di
/// lingkungan tanpa data locale), fungsi di bawah otomatis jatuh ke pola tanpa
/// locale sehingga UI tidak pernah crash.
class AppDate {
  const AppDate._();

  static const locale = 'id_ID';

  static bool _ready = false;
  static bool _attempted = false;

  /// Muat data locale sekali. Aman dipanggil berkali-kali.
  static Future<void> ensureLoaded() async {
    if (_ready || _attempted) return;
    _attempted = true;
    try {
      await initializeDateFormatting(locale, null);
      _ready = true;
    } catch (_) {
      // Biarkan _ready = false; formatter akan memakai pola default.
      _ready = false;
    }
  }

  static String _format(DateTime date, String localizedPattern, String fallbackPattern) {
    try {
      return DateFormat(localizedPattern, _ready ? locale : null).format(date);
    } catch (_) {
      try {
        return DateFormat(fallbackPattern).format(date);
      } catch (_) {
        return date.toIso8601String().split('T').first;
      }
    }
  }

  /// "3 Mar 2026"
  static String short(DateTime d) => _format(d, 'd MMM yyyy', 'd MMM yyyy');

  /// "3 Maret 2026"
  static String medium(DateTime d) => _format(d, 'd MMMM yyyy', 'd MMM yyyy');

  /// "Senin, 3 Maret 2026 · 06:30"
  static String full(DateTime d) =>
      _format(d, 'EEEE, d MMMM yyyy · HH:mm', 'EEE, d MMM yyyy · HH:mm');

  /// "3 Mar"
  static String dayMonth(DateTime d) => _format(d, 'd MMM', 'd MMM');

  /// "Senin, 3 Maret 2026"
  static String weekdayDate(DateTime d) =>
      _format(d, 'EEEE, d MMMM yyyy', 'EEE, d MMM yyyy');

  /// "06:30"
  static String time(DateTime d) => DateFormat('HH:mm').format(d);
}
