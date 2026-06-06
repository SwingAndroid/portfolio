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
}
