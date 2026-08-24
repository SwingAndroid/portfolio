import 'dart:math' as math;

import '../entities/crypto_entity.dart';
import '../entities/transaction_entity.dart';

/// A dated cash movement, from the investor's point of view.
/// Negative = money leaving your pocket, positive = money coming back.
class CashFlow {
  final DateTime date;
  final double amount;

  const CashFlow(this.date, this.amount);
}

/// Money-weighted annualised return (the XIRR spreadsheets compute).
///
/// The portfolio's headline figure is `(value − cost) / cost`, which treats a
/// euro invested four years ago and one invested last week as equivalent. Over
/// hundreds of transactions spread across years that is not a return at all.
/// XIRR is the rate that makes every dated flow discount back to zero, so the
/// timing of each contribution actually counts.
///
/// Returns null when the flows cannot define a rate — fewer than two flows, or
/// no sign change (all money in, or all money out).
/// Lower bound of the search. A rate of -1 is a mathematical singularity, so
/// the bracket stops just short of it — but close enough to express a
/// near-total loss rather than giving up and returning null.
const double _minRate = -0.999999;

double? computeXirr(
  List<CashFlow> flows, {
  double guess = 0.1,
  int maxIterations = 100,
  double tolerance = 1e-7,
}) {
  if (flows.length < 2) return null;

  final ordered = [...flows]..sort((a, b) => a.date.compareTo(b.date));
  final hasPositive = ordered.any((f) => f.amount > 0);
  final hasNegative = ordered.any((f) => f.amount < 0);
  if (!hasPositive || !hasNegative) return null;

  final start = ordered.first.date;
  // Year fractions, cached: the solver evaluates these thousands of times.
  // 365-day years, matching the XIRR convention used by Excel and Sheets so
  // the figure is directly comparable to a spreadsheet.
  const secondsPerYear = 365 * 24 * 60 * 60;
  final years = [
    for (final f in ordered) f.date.difference(start).inSeconds / secondsPerYear
  ];
  final amounts = [for (final f in ordered) f.amount];

  double npv(double rate) {
    final base = 1 + rate;
    var total = 0.0;
    for (var i = 0; i < amounts.length; i++) {
      total += amounts[i] / _pow(base, years[i]);
    }
    return total;
  }

  // ── Newton-Raphson ────────────────────────────────────────────────────────
  var rate = guess;
  for (var i = 0; i < maxIterations; i++) {
    final base = 1 + rate;
    if (base <= 0) break;

    var value = 0.0;
    var derivative = 0.0;
    for (var j = 0; j < amounts.length; j++) {
      final discount = _pow(base, years[j]);
      value += amounts[j] / discount;
      derivative -= amounts[j] * years[j] / (discount * base);
    }

    if (value.abs() < tolerance) return rate;
    if (derivative == 0 || !derivative.isFinite) break;

    final next = rate - value / derivative;
    if (!next.isFinite) break;
    if ((next - rate).abs() < tolerance) return next > -1 ? next : null;
    rate = next <= _minRate ? _minRate : next;
  }

  // ── Bisection fallback ────────────────────────────────────────────────────
  // Newton is fast but can wander off on irregular flows; bisection always
  // converges once a sign change is bracketed.
  var low = _minRate;
  var high = 100.0;
  var fLow = npv(low);
  var fHigh = npv(high);
  if (!fLow.isFinite || !fHigh.isFinite || fLow * fHigh > 0) return null;

  for (var i = 0; i < 200; i++) {
    final mid = (low + high) / 2;
    final fMid = npv(mid);
    if (!fMid.isFinite) return null;
    if (fMid.abs() < tolerance || (high - low).abs() < tolerance) return mid;
    if (fLow * fMid < 0) {
      high = mid;
      fHigh = fMid;
    } else {
      low = mid;
      fLow = fMid;
    }
  }
  return (low + high) / 2;
}

/// Discounting factor for a real (fractional) year exponent.
double _pow(double base, double exponent) =>
    exponent == 0 ? 1.0 : math.pow(base, exponent).toDouble();

/// Builds the cash flows for a set of coins, closed out at today's value.
///
/// Only movements that actually moved money count. A transfer recorded at a
/// price of zero — an airdrop or staking reward — is not a contribution, so it
/// correctly shows up as pure return rather than as capital deployed.
List<CashFlow> cashFlowsFor(
  List<CryptoEntity> cryptos, {
  DateTime? valuationDate,
  double? valuationOverride,
}) {
  final flows = <CashFlow>[];

  for (final crypto in cryptos) {
    for (final t in crypto.transactions) {
      if (t.pricePerCoin <= 0) continue;
      final amount = t.quantity * t.pricePerCoin;
      flows.add(CashFlow(t.date, t.type.addsHoldings ? -amount : amount));
    }
  }

  final value = valuationOverride ??
      cryptos.fold<double>(0, (sum, c) => sum + c.holdingsValue);
  if (value > 0) {
    flows.add(CashFlow(valuationDate ?? DateTime.now(), value));
  }

  return flows;
}
