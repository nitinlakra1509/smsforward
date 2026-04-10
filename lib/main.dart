import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_links/app_links.dart';
import 'package:intl/intl.dart';

void main() {
  runApp(const SMSForwarderApp());
}

class SMSForwarderApp extends StatelessWidget {
  const SMSForwarderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SMS Forwarder',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF6366F1),
        scaffoldBackgroundColor: const Color(0xFF0F0F1A),
      ),
      home: HomeScreen(key: HomeScreen.globalKey),
    );
  }
}

// ─────────────────────────────────────────────────
// Data Models
// ─────────────────────────────────────────────────

enum Platform { slack, discord, telegram, webhook }

extension PlatformInfo on Platform {
  String get label => name[0].toUpperCase() + name.substring(1);

  IconData get icon {
    switch (this) {
      case Platform.slack:    return Icons.tag;
      case Platform.discord:  return Icons.discord;
      case Platform.telegram: return Icons.send;
      case Platform.webhook:  return Icons.api;
    }
  }

  Color get color {
    switch (this) {
      case Platform.slack:    return const Color(0xFF4A154B);
      case Platform.discord:  return const Color(0xFF5865F2);
      case Platform.telegram: return const Color(0xFF0088CC);
      case Platform.webhook:  return const Color(0xFFF97316);
    }
  }

  String get urlHint {
    switch (this) {
      case Platform.slack:    return 'https://hooks.slack.com/services/...';
      case Platform.discord:  return 'https://discord.com/api/webhooks/...';
      case Platform.telegram: return 'Bot Token (from @BotFather)';
      case Platform.webhook:  return 'https://your-server.com/webhook';
    }
  }
}

class WebhookConfig {
  final String id;
  final Platform platform;
  final String name;
  final String url;
  final String filter; // keyword filter — empty means all messages
  final String? telegramChatId;

  WebhookConfig({
    required this.id,
    required this.platform,
    required this.name,
    required this.url,
    this.filter = '',
    this.telegramChatId,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'platform': platform.name, 'name': name,
    'url': url, 'filter': filter, 'telegramChatId': telegramChatId,
  };

  factory WebhookConfig.fromJson(Map<String, dynamic> json) => WebhookConfig(
    id: json['id'], platform: Platform.values.byName(json['platform']),
    name: json['name'], url: json['url'], filter: json['filter'] ?? '',
    telegramChatId: json['telegramChatId'],
  );
}

class ForwardLog {
  final String sender;
  final String message;
  final String destination;
  final bool success;
  final DateTime time;

  ForwardLog({required this.sender, required this.message, required this.destination, required this.success, required this.time});

  Map<String, dynamic> toJson() => {
    'sender': sender, 'message': message, 'destination': destination,
    'success': success, 'time': time.toIso8601String(),
  };

  factory ForwardLog.fromJson(Map<String, dynamic> json) => ForwardLog(
    sender: json['sender'], message: json['message'], destination: json['destination'],
    success: json['success'], time: DateTime.parse(json['time']),
  );
}

// ─────────────────────────────────────────────────
// Home Screen
// ─────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  /// Global key for accessing state in integration tests
  static final globalKey = GlobalKey<HomeScreenState>();

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late AppLinks _appLinks;
  List<WebhookConfig> _configs = [];
  List<ForwardLog> _logs = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadConfigs();
    _loadLogs();
    _initDeepLinks();
  }

  // ── Persistence ──

  Future<void> _loadConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('webhooks') ?? [];
    setState(() {
      _configs = raw.map((e) => WebhookConfig.fromJson(json.decode(e))).toList();
    });
  }

  Future<void> _saveConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('webhooks', _configs.map((e) => json.encode(e.toJson())).toList());
  }

  Future<void> _loadLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('logs') ?? [];
    setState(() {
      _logs = raw.map((e) => ForwardLog.fromJson(json.decode(e))).toList();
    });
  }

  Future<void> _saveLogs() async {
    final prefs = await SharedPreferences.getInstance();
    // Keep last 100 logs only
    if (_logs.length > 100) _logs = _logs.sublist(0, 100);
    await prefs.setStringList('logs', _logs.map((e) => json.encode(e.toJson())).toList());
  }

  // ── Deep Link Handler ──

  void _initDeepLinks() {
    _appLinks = AppLinks();

    // Handle link when app is already running
    _appLinks.uriLinkStream.listen((uri) {
      _handleIncomingLink(uri);
    });

    // Handle link that launched the app
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) _handleIncomingLink(uri);
    });
  }

  Future<void> _handleIncomingLink(Uri uri) async {
    if (uri.host != 'forward') return;

    final sender = uri.queryParameters['sender'] ?? 'Unknown';
    final message = uri.queryParameters['message'] ?? '';

    if (message.isEmpty) return;

    await _processIncomingSMS(sender, message);
  }

  /// Public method for integration tests to simulate an incoming SMS.
  Future<void> simulateIncomingSMS(String sender, String message) async {
    await _processIncomingSMS(sender, message);
  }

  Future<void> _processIncomingSMS(String sender, String message) async {
    // Process against all webhook configs
    for (final config in _configs) {
      // Apply filter: if filter is set, only forward if message contains it
      if (config.filter.isNotEmpty &&
          !message.toLowerCase().contains(config.filter.toLowerCase())) {
        continue; // Skip — doesn't match filter
      }

      final success = await _forwardToWebhook(config, sender, message);

      setState(() {
        _logs.insert(0, ForwardLog(
          sender: sender,
          message: message,
          destination: config.name,
          success: success,
          time: DateTime.now(),
        ));
      });
    }

    await _saveLogs();
  }

  Future<bool> _forwardToWebhook(WebhookConfig config, String sender, String message) async {
    try {
      final formattedMsg = '📩 *SMS Received*\n*From:* $sender\n*Message:* $message';

      switch (config.platform) {
        case Platform.slack:
          await http.post(
            Uri.parse(config.url),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'text': formattedMsg}),
          );
          break;
        case Platform.discord:
          await http.post(
            Uri.parse(config.url),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'content': formattedMsg}),
          );
          break;
        case Platform.telegram:
          final tgUrl = 'https://api.telegram.org/bot${config.url}/sendMessage';
          await http.post(
            Uri.parse(tgUrl),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'chat_id': config.telegramChatId, 'text': formattedMsg}),
          );
          break;
        case Platform.webhook:
          await http.post(
            Uri.parse(config.url),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'sender': sender, 'message': message, 'timestamp': DateTime.now().toIso8601String()}),
          );
          break;
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  // ── CRUD ──

  Future<void> _addConfig(WebhookConfig config) async {
    setState(() => _configs.add(config));
    await _saveConfigs();
  }

  Future<void> _removeConfig(String id) async {
    setState(() => _configs.removeWhere((c) => c.id == id));
    await _saveConfigs();
  }

  Future<void> _testWebhook(WebhookConfig config) async {
    final success = await _forwardToWebhook(config, 'Test Sender', '✅ Test from SMS Forwarder!');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(success ? '✅ Webhook responded OK!' : '❌ Failed to reach webhook'),
        backgroundColor: success ? Colors.green.shade800 : Colors.red.shade800,
      ));
    }
  }

  // ── UI ──

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            TabBar(
              controller: _tabController,
              indicatorColor: const Color(0xFF6366F1),
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(text: 'Providers'),
                Tab(text: 'Activity'),
                Tab(text: 'Setup'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildProvidersTab(),
                  _buildActivityTab(),
                  _buildSetupTab(),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddSheet(),
        icon: const Icon(Icons.add),
        label: const Text('Add Provider'),
        backgroundColor: const Color(0xFF6366F1),
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('SMS Forwarder', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -1)),
                Text('${_configs.length} provider${_configs.length == 1 ? '' : 's'} active',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined, size: 22),
            tooltip: 'Clear Logs',
            onPressed: () async {
              setState(() => _logs.clear());
              await _saveLogs();
            },
          ),
        ],
      ),
    );
  }

  // ── Providers Tab ──

  Widget _buildProvidersTab() {
    if (_configs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.webhook_outlined, size: 56, color: Colors.white.withValues(alpha: 0.1)),
            const SizedBox(height: 12),
            const Text('No providers configured', style: TextStyle(color: Colors.white38)),
            const Text('Tap + to add Slack, Discord, or Telegram', style: TextStyle(color: Colors.white24, fontSize: 12)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _configs.length,
      itemBuilder: (context, index) {
        final c = _configs[index];
        return Dismissible(
          key: Key(c.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(color: Colors.red.shade900, borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          onDismissed: (_) => _removeConfig(c.id),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: c.platform.color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.platform.color.withValues(alpha: 0.2)),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              leading: CircleAvatar(
                backgroundColor: c.platform.color.withValues(alpha: 0.2),
                child: Icon(c.platform.icon, color: c.platform.color, size: 20),
              ),
              title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                c.filter.isEmpty ? 'All messages' : 'Filter: "${c.filter}"',
                style: TextStyle(color: const Color(0xFF6366F1).withValues(alpha: 0.7), fontSize: 12),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(icon: const Icon(Icons.play_arrow_rounded, size: 22), tooltip: 'Test', onPressed: () => _testWebhook(c)),
                  IconButton(icon: const Icon(Icons.copy_rounded, size: 18), tooltip: 'Copy Shortcut Config', onPressed: () => _showShortcutConfig(c)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Activity Tab ──

  Widget _buildActivityTab() {
    if (_logs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 56, color: Colors.white.withValues(alpha: 0.1)),
            const SizedBox(height: 12),
            const Text('No activity yet', style: TextStyle(color: Colors.white38)),
            const Text('Forwarded messages will appear here', style: TextStyle(color: Colors.white24, fontSize: 12)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _logs.length,
      itemBuilder: (context, index) {
        final log = _logs[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(log.success ? Icons.check_circle : Icons.error,
                size: 18, color: log.success ? Colors.greenAccent : Colors.redAccent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${log.sender} → ${log.destination}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    Text(log.message, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
                  ],
                ),
              ),
              Text(DateFormat('HH:mm').format(log.time), style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.3))),
            ],
          ),
        );
      },
    );
  }

  // ── Setup Tab ──

  Widget _buildSetupTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('iOS Shortcut Setup', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('The Shortcut opens this app via a URL scheme, passing the SMS data. The app then filters and forwards to your webhooks.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13)),
          const SizedBox(height: 24),

          _stepTile(1, 'Open Shortcuts App', 'Go to the Automation tab. Tap "+".'),
          _stepTile(2, 'Select "Message"', 'Leave sender blank for all. Set "Run Immediately" ON.'),
          _stepTile(3, 'Add "Open URLs"', 'This is the ONLY action you need.'),
          _stepTile(4, 'Set the URL', 'Use the URL below. Tap to copy.\nReplace variables with Shortcut Input fields.'),

          const SizedBox(height: 16),
          GestureDetector(
            onTap: () {
              Clipboard.setData(const ClipboardData(text: 'smsforward://forward?sender=SENDER_VARIABLE&message=MESSAGE_VARIABLE'));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('URL copied!')));
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.3)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('URL Scheme:', style: TextStyle(fontSize: 11, color: Colors.white38)),
                  SizedBox(height: 4),
                  Text('smsforward://forward?sender=\u00abSender\u00bb&message=\u00abMessage\u00bb',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: Color(0xFF6366F1))),
                  SizedBox(height: 8),
                  Text('Tap to copy  •  Replace «Sender» and «Message» with Shortcut Input variables',
                    style: TextStyle(fontSize: 11, color: Colors.white24)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 80), // FAB clearance
        ],
      ),
    );
  }

  Widget _stepTile(int num, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Center(child: Text('$num', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF6366F1)))),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(desc, style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13)),
            ],
          )),
        ],
      ),
    );
  }

  // ── Add Provider Bottom Sheet ──

  void _showAddSheet() {
    Platform selectedPlatform = Platform.slack;
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final chatIdCtrl = TextEditingController();
    final filterCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 20),
              const Text('New Provider', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),

              // Platform chips
              Wrap(
                spacing: 8,
                children: Platform.values.map((p) => ChoiceChip(
                  label: Text(p.label),
                  avatar: Icon(p.icon, size: 18, color: selectedPlatform == p ? Colors.white : p.color),
                  selected: selectedPlatform == p,
                  selectedColor: p.color,
                  onSelected: (_) => setState(() => selectedPlatform = p),
                )).toList(),
              ),
              const SizedBox(height: 16),

              TextField(controller: nameCtrl, decoration: _inputDecor('Display Name', 'e.g., Team Slack')),
              const SizedBox(height: 12),
              TextField(controller: urlCtrl, decoration: _inputDecor(
                selectedPlatform == Platform.telegram ? 'Bot Token' : 'Webhook URL',
                selectedPlatform.urlHint,
              )),

              if (selectedPlatform == Platform.telegram) ...[
                const SizedBox(height: 12),
                TextField(controller: chatIdCtrl, decoration: _inputDecor('Chat ID', '-1001234567890')),
              ],

              const SizedBox(height: 12),
              TextField(controller: filterCtrl, decoration: _inputDecor(
                'Keyword Filter (optional)', 'e.g., OTP — leave blank for all',
              ).copyWith(prefixIcon: const Icon(Icons.filter_alt_outlined, size: 20))),

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity, height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    _addConfig(WebhookConfig(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      platform: selectedPlatform,
                      name: nameCtrl.text.isEmpty ? selectedPlatform.label : nameCtrl.text,
                      url: urlCtrl.text,
                      filter: filterCtrl.text,
                      telegramChatId: chatIdCtrl.text.isEmpty ? null : chatIdCtrl.text,
                    ));
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: selectedPlatform.color,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Save Provider', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecor(String label, String hint) => InputDecoration(
    labelText: label,
    hintText: hint,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  );

  // ── Shortcut Config Sheet ──

  void _showShortcutConfig(WebhookConfig config) {
    // Since the app handles forwarding, the Shortcut only needs to open the URL scheme
    final shortcutUrl = 'smsforward://forward?sender=«Sender»&message=«Message Content»';

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Shortcut for ${config.name}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: config.platform.color)),
            const SizedBox(height: 8),
            const Text('Your iOS Shortcut only needs ONE action:', style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 16),
            _infoRow('Action', 'Open URLs'),
            _infoRow('URL', shortcutUrl),
            if (config.filter.isNotEmpty) _infoRow('Filter', 'App will only forward if message contains "${config.filter}"'),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: shortcutUrl));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('URL copied!')));
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copy URL'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.4))),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}
