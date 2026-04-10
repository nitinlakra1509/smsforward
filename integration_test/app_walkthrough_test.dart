import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:smsforward/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('App Walkthrough - All Pages', () {
    testWidgets('Navigate through all tabs and capture screenshots',
        (WidgetTester tester) async {
      // Launch the app
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // ── Screenshot 1: Providers Tab (Home) ──
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
      await binding.takeScreenshot('01_providers_tab');

      // ── Screenshot 2: Tap "Add Provider" FAB ──
      final addButton = find.text('Add Provider');
      if (addButton.evaluate().isNotEmpty) {
        await tester.tap(addButton);
        await tester.pumpAndSettle(const Duration(seconds: 1));
        await binding.takeScreenshot('02_add_provider_sheet');

        // ── Screenshot 3: Select Discord platform ──
        final discordChip = find.text('Discord');
        if (discordChip.evaluate().isNotEmpty) {
          await tester.tap(discordChip);
          await tester.pumpAndSettle();
          await binding.takeScreenshot('03_discord_selected');
        }

        // ── Screenshot 4: Select Telegram platform ──
        final telegramChip = find.text('Telegram');
        if (telegramChip.evaluate().isNotEmpty) {
          await tester.tap(telegramChip);
          await tester.pumpAndSettle();
          await binding.takeScreenshot('04_telegram_selected');
        }

        // ── Screenshot 5: Select Webhook platform ──
        final webhookChip = find.text('Webhook');
        if (webhookChip.evaluate().isNotEmpty) {
          await tester.tap(webhookChip);
          await tester.pumpAndSettle();
          await binding.takeScreenshot('05_webhook_selected');
        }

        // ── Screenshot 6: Select Slack and fill form ──
        final slackChip = find.text('Slack');
        if (slackChip.evaluate().isNotEmpty) {
          await tester.tap(slackChip);
          await tester.pumpAndSettle();
        }

        // Fill in the form
        final nameField = find.widgetWithText(TextField, 'Display Name');
        if (nameField.evaluate().isNotEmpty) {
          await tester.enterText(nameField, 'Team Slack');
          await tester.pumpAndSettle();
        }

        final urlField = find.widgetWithText(TextField, 'Webhook URL');
        if (urlField.evaluate().isNotEmpty) {
          await tester.enterText(urlField, 'https://hooks.slack.com/services/...');
          await tester.pumpAndSettle();
        }

        final filterField = find.widgetWithText(TextField, 'Keyword Filter (optional)');
        if (filterField.evaluate().isNotEmpty) {
          await tester.enterText(filterField, 'OTP');
          await tester.pumpAndSettle();
        }

        await binding.takeScreenshot('06_slack_form_filled');

        // Save the provider
        final saveButton = find.text('Save Provider');
        if (saveButton.evaluate().isNotEmpty) {
          await tester.tap(saveButton);
          await tester.pumpAndSettle(const Duration(seconds: 1));
        }
      }

      // ── Screenshot 7: Providers tab with a provider added ──
      await tester.pumpAndSettle();
      await binding.takeScreenshot('07_provider_added');

      // ── Screenshot 8: Navigate to Activity tab ──
      final activityTab = find.text('Activity');
      if (activityTab.evaluate().isNotEmpty) {
        await tester.tap(activityTab);
        await tester.pumpAndSettle(const Duration(seconds: 1));
        await binding.takeScreenshot('08_activity_tab');
      }

      // ── Screenshot 9: Navigate to Setup tab ──
      final setupTab = find.text('Setup');
      if (setupTab.evaluate().isNotEmpty) {
        await tester.tap(setupTab);
        await tester.pumpAndSettle(const Duration(seconds: 1));
        await binding.takeScreenshot('09_setup_tab');
      }

      // ── Screenshot 10: Scroll down on Setup tab ──
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();
      await binding.takeScreenshot('10_setup_url_scheme');

      // ── Screenshot 11: Go back to Providers and tap test button ──
      final providersTab = find.text('Providers');
      if (providersTab.evaluate().isNotEmpty) {
        await tester.tap(providersTab);
        await tester.pumpAndSettle(const Duration(seconds: 1));
        await binding.takeScreenshot('11_providers_final');
      }
    });
  });
}
