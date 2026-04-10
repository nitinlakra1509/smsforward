import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:smsforward/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Full app walkthrough with screenshots', (tester) async {
    // Launch the app
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // ── Page 1: Providers Tab (empty state) ──
    await tester.pumpAndSettle();
    await binding.takeScreenshot('01_providers_empty');

    // ── Page 2: Tap "Add Provider" FAB ──
    final addBtn = find.text('Add Provider');
    expect(addBtn, findsOneWidget);
    await tester.tap(addBtn);
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
    // Go back to Slack
    final slackChips = find.text('Slack');
    await tester.tap(slackChips.last);
    await tester.pumpAndSettle();

    // Fill name
    await tester.enterText(
      find.widgetWithText(TextField, 'Display Name'),
      'Team Slack',
    );
    await tester.pumpAndSettle();

    // Fill URL
    final urlLabel = find.widgetWithText(TextField, 'Webhook URL');
    if (urlLabel.evaluate().isNotEmpty) {
      await tester.enterText(urlLabel, 'https://hooks.slack.com/services/xxx');
    }
    await tester.pumpAndSettle();

    // Fill filter
    final filterField = find.widgetWithText(TextField, 'Keyword Filter (optional)');
    if (filterField.evaluate().isNotEmpty) {
      await tester.enterText(filterField, 'OTP');
    }
    await tester.pumpAndSettle();
    await binding.takeScreenshot('06_slack_form_filled');

    // Save
    await tester.tap(find.text('Save Provider'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // ── Page 7: Provider added ──
    await binding.takeScreenshot('07_provider_saved');

    // ── Page 8: Activity Tab ──
    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await binding.takeScreenshot('08_activity_tab');

    // ── Page 9: Setup Tab ──
    await tester.tap(find.text('Setup'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await binding.takeScreenshot('09_setup_tab_top');

    // ── Page 10: Scroll down on Setup ──
    final scrollable = find.byType(SingleChildScrollView);
    if (scrollable.evaluate().isNotEmpty) {
      await tester.drag(scrollable, const Offset(0, -300));
      await tester.pumpAndSettle();
    }
    await binding.takeScreenshot('10_setup_tab_url');

    // ── Page 11: Back to Providers ──
    await tester.tap(find.text('Providers'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await binding.takeScreenshot('11_providers_with_config');
  });
}
