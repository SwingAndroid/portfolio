import 'package:intl/intl.dart';

class Formatters {
  static final _currencyFormat = NumberFormat.currency(
    symbol: '\$',
    decimalDigits: 2,
  );

  static final _compactCurrencyFormat = NumberFormat.compactCurrency(
    symbol: '\$',
    decimalDigits: 2,
  );

  static final _percentFormat = NumberFormat('+0.00%;-0.00%');

  static final _dateFormat = DateFormat('MMMM d, yyyy');
  static final _shortDateFormat = DateFormat('MMM d, yyyy');

  static String formatCurrency(double value) {
    if (value.abs() >= 1000000) return _compactCurrencyFormat.format(value);
    return _currencyFormat.format(value);
  }

  static String formatCurrencyWithSign(double value) {
    final formatted = formatCurrency(value.abs());
    return value >= 0 ? '+$formatted' : '-$formatted';
  }

  static String formatPercent(double value) {
    return _percentFormat.format(value / 100);
  }

  static String formatCrypto(double value, String symbol) {
    final formatter = NumberFormat('0.########');
    return '${formatter.format(value)} $symbol';
  }

  static String formatCryptoAmount(double value) {
    if (value == value.roundToDouble()) {
      return NumberFormat('0').format(value);
    }
    return NumberFormat('0.########').format(value);
  }

  static String formatDate(DateTime date) => _dateFormat.format(date);
  static String formatShortDate(DateTime date) => _shortDateFormat.format(date);

  static String formatPrice(double price) {
    if (price < 0.01) return '\$${price.toStringAsFixed(6)}';
    if (price < 1) return '\$${price.toStringAsFixed(4)}';
    return _currencyFormat.format(price);
  }

  /// Locale-tolerant number parsing for user input.
  ///
  /// Accepts both `.` and `,` as the decimal separator (mobile numeric
  /// keyboards in many locales emit `,`, e.g. "16,0"). Also strips a
  /// thousands separator when both symbols are present (e.g. "1,234.56"
  /// or "1.234,56"). Returns null when the input is empty or not a number.
  static double? tryParseNum(String? input) {
    if (input == null) return null;
    var s = input.trim().replaceAll(' ', '').replaceAll(' ', '');
    if (s.isEmpty) return null;

    final hasComma = s.contains(',');
    final hasDot = s.contains('.');

    if (hasComma && hasDot) {
      // Whichever separator comes last is the decimal one; the other is
      // a thousands separator and gets removed.
      if (s.lastIndexOf(',') > s.lastIndexOf('.')) {
        s = s.replaceAll('.', '').replaceAll(',', '.');
      } else {
        s = s.replaceAll(',', '');
      }
    } else if (hasComma) {
      s = s.replaceAll(',', '.');
    }

    return double.tryParse(s);
  }
}
