import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:smsforward/main.dart' as app;
import 'package:smsforward/main.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Full app walkthrough with SMS demo', (tester) async {
    // Launch the app
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // ═══════════════════════════════════════════════
    // PART 1: App Tour — Every Page
    // ═══════════════════════════════════════════════

    // ── Page 1: Providers Tab (empty state) ──
    await binding.takeScreenshot('01_providers_empty');

    // ── Page 2: Tap "Add Provider" FAB ──
    await tester.tap(find.text('Add Provider'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await binding.takeScreenshot('02_add_provider_slack');

    // ── Page 3: Select Discord ──
    await tester.tap(find.text('Discord'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('03_add_provider_discord');

    // ── Page 4: Select Telegram (shows Chat ID field) ──
    await tester.tap(find.text('Telegram'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('04_add_provider_telegram');

    // ── Page 5: Select Webhook ──
    await tester.tap(find.text('Webhook'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('05_add_provider_webhook');

    // ── Page 6: Fill Slack form and save ──
    final slackChips = find.text('Slack');
    await tester.tap(slackChips.last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Display Name'),
      'Team Slack',
    );

    final urlField = find.widgetWithText(TextField, 'Webhook URL');
    if (urlField.evaluate().isNotEmpty) {
      await tester.enterText(urlField, 'https://hooks.slack.com/services/test');
    }

    final filterField = find.widgetWithText(TextField, 'Keyword Filter (optional)');
    if (filterField.evaluate().isNotEmpty) {
      await tester.enterText(filterField, 'OTP');
    }
    await tester.pumpAndSettle();
    await binding.takeScreenshot('06_slack_form_filled');

    // Save
    await tester.tap(find.text('Save Provider'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await binding.takeScreenshot('07_provider_saved');

    // ── Page 8: Activity Tab ──
    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await binding.takeScreenshot('08_activity_empty');

    // ── Page 9: Setup Tab ──
    await tester.tap(find.text('Setup'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await binding.takeScreenshot('09_setup_tab');

    // ── Page 10: Scroll down on Setup ──
    final scrollable = find.byType(SingleChildScrollView);
    if (scrollable.evaluate().isNotEmpty) {
      await tester.drag(scrollable, const Offset(0, -300));
      await tester.pumpAndSettle();
    }
    await binding.takeScreenshot('10_setup_url_scheme');

    // ═══════════════════════════════════════════════
    // PART 2: SMS Demo — Simulate incoming messages
    // ═══════════════════════════════════════════════

    // Go back to Providers
    await tester.tap(find.text('Providers'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await binding.takeScreenshot('11_providers_before_sms');

    // Get the HomeScreenState to simulate incoming SMS
    final homeState = HomeScreen.globalKey.currentState;
    if (homeState != null) {
      // ── SMS 1: OTP message (matches "OTP" filter) ──
      await homeState.simulateIncomingSMS(
        '+91 98765 43210',
        'Your OTP is 482910. Valid for 5 minutes. Do not share with anyone. -HDFC Bank',
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // ── SMS 2: Another OTP (matches filter) ──
      await homeState.simulateIncomingSMS(
        'AMAZON',
        'Your OTP for order #12345 is 739201. Enter this to confirm your purchase.',
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // ── SMS 3: Non-OTP message (should be filtered out) ──
      await homeState.simulateIncomingSMS(
        'Mom',
        'Come home for dinner, food is ready!',
      );
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    // Switch to Activity tab to show forwarded messages
    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await binding.takeScreenshot('12_activity_with_messages');

    // Back to Providers to show final state
    await tester.tap(find.text('Providers'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await binding.takeScreenshot('13_providers_final');
  });
}
