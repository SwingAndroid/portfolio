import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:crypto_portfolio/core/constants/app_constants.dart';

void main() {
  test('the version shown in the app matches pubspec.yaml', () {
    // The label exists so a deployment can be confirmed at a glance. If it can
    // drift from the real version it is worse than useless, so this fails the
    // build rather than relying on anyone remembering to update both.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final declared =
        RegExp(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)', multiLine: true)
            .firstMatch(pubspec);

    expect(declared, isNotNull, reason: 'pubspec.yaml must declare a version');
    expect(
      AppConstants.appVersion,
      declared!.group(1),
      reason: 'bump AppConstants.appVersion together with pubspec.yaml',
    );
  });

  test('the version is a plain semantic triple', () {
    expect(AppConstants.appVersion, matches(RegExp(r'^\d+\.\d+\.\d+$')),
        reason: 'no build metadata in the user-facing label');
  });
}
