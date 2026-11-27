import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'supabase.dart';
import 'screens_home.dart';
import 'screens_vote_chat.dart';
import 'screens_maintain.dart';

void main() {
  runApp(const Dorm511App());
}

const kNavy = Color(0xFF1B2A4A);
const kGold = Color(0xFFC9A227);

class Dorm511App extends StatelessWidget {
  const Dorm511App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '511宿舍公务系统',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: kNavy, primary: kNavy),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: kNavy,
          foregroundColor: Colors.white,
          centerTitle: true,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: kNavy,
          foregroundColor: Colors.white,
        ),
      ),
      home: const AppShell(),
    );
  }
}

/// 应用外壳：管昵称、后端配置、底部导航。
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0;
  String _nickname = '';
  String _bed = '';
  SBConfig _config = SBConfig.empty;
  bool _loading = true;

  SBClient? get _client => _config.isConfigured ? SBClient(_config) : null;

  @override
  void initState() {
    super.initState();
    _loadLocal();
  }

  Future<void> _loadLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final cfgRaw = prefs.getString('sb_config');
    setState(() {
      _nickname = prefs.getString('nickname') ?? '';
      _bed = prefs.getString('bed') ?? '';
      _config = cfgRaw == null
          ? SBConfig.empty
          : SBConfig.fromJson(jsonDecode(cfgRaw) as Map<String, dynamic>);
      _loading = false;
    });
  }

  Future<void> _saveNickname(String name, String bed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nickname', name);
    await prefs.setString('bed', bed);
    setState(() {
      _nickname = name;
      _bed = bed;
    });
    // 同步成员到后端（失败也不阻塞）。
    final client = _client;
    if (client != null) {
      try {
        final found = await client.query('Member', where: {'name': name});
        if (found.isEmpty) {
          await client.create('Member', {'name': name, 'bed': bed});
        }
      } catch (_) {}
    }
  }

  Future<void> _saveConfig(SBConfig cfg) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sb_config', jsonEncode(cfg.toJson()));
    setState(() => _config = cfg);
  }

  void _goTab(int i) => setState(() => _tab = i);

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_nickname.isEmpty) {
      return NicknameSetup(onSave: _saveNickname);
    }

    final client = _client;
    final pages = [
      HomeScreen(client: client, nickname: _nickname, onGoSettings: () => _goTab(4)),
      VoteScreen(client: client, nickname: _nickname, onGoSettings: () => _goTab(4)),
      ChatScreen(client: client, nickname: _nickname, onGoSettings: () => _goTab(4)),
      MaintainGate(client: client, nickname: _nickname, onGoSettings: () => _goTab(4)),
      SettingsScreen(
        nickname: _nickname,
        bed: _bed,
        config: _config,
        onSaveNickname: _saveNickname,
        onSaveConfig: _saveConfig,
      ),
    ];
    const titles = ['511宿舍公务系统', '投票', '宿舍聊天', '维护', '我的'];
    return Scaffold(
      appBar: AppBar(title: Text(titles[_tab])),
      body: pages[_tab],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        onTap: _goTab,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: kNavy,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: '首页'),
          BottomNavigationBarItem(icon: Icon(Icons.how_to_vote), label: '投票'),
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: '聊天'),
          BottomNavigationBarItem(icon: Icon(Icons.admin_panel_settings), label: '维护'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: '我的'),
        ],
      ),
    );
  }
}

/// 首次打开：输入昵称和床位。
class NicknameSetup extends StatefulWidget {
  final Future<void> Function(String name, String bed) onSave;
  const NicknameSetup({super.key, required this.onSave});

  @override
  State<NicknameSetup> createState() => _NicknameSetupState();
}

class _NicknameSetupState extends State<NicknameSetup> {
  final _nameCtrl = TextEditingController();
  final _bedCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bedCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('511宿舍公务系统')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 32),
            const Icon(Icons.meeting_room, size: 72, color: kNavy),
            const SizedBox(height: 16),
            const Text(
              '欢迎入住 511 宿舍',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '先报个名字，宿舍里投票、聊天、任命都用这个身份。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: '昵称（宿舍里大家叫你的名字）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _bedCtrl,
              decoration: const InputDecoration(
                labelText: '床位（如：2号床）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: kNavy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _saving
                  ? null
                  : () async {
                      final name = _nameCtrl.text.trim();
                      if (name.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('先填个昵称')),
                        );
                        return;
                      }
                      setState(() => _saving = true);
                      await widget.onSave(name, _bedCtrl.text.trim());
                      if (mounted) setState(() => _saving = false);
                    },
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('进入宿舍', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}

/// 未配置后端的提示卡（各页共用）。
class NotConfiguredCard extends StatelessWidget {
  final VoidCallback onGoSettings;
  const NotConfiguredCard({super.key, required this.onGoSettings});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 56, color: Colors.grey),
            const SizedBox(height: 12),
            const Text(
              '还没连上宿舍后端',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '去 supabase.com 免费注册、建个项目，把 Project URL、anon key 填到「我的 → 后端配置」里，苹果安卓就能互通了。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: kNavy, foregroundColor: Colors.white),
              onPressed: onGoSettings,
              child: const Text('去配置'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 我的页：昵称、后端配置、关于。
class SettingsScreen extends StatefulWidget {
  final String nickname;
  final String bed;
  final SBConfig config;
  final Future<void> Function(String name, String bed) onSaveNickname;
  final Future<void> Function(SBConfig cfg) onSaveConfig;

  const SettingsScreen({
    super.key,
    required this.nickname,
    required this.bed,
    required this.config,
    required this.onSaveNickname,
    required this.onSaveConfig,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _nameCtrl = TextEditingController(text: widget.nickname);
  late final _bedCtrl = TextEditingController(text: widget.bed);
  late final _urlCtrl = TextEditingController(text: widget.config.url);
  late final _keyCtrl = TextEditingController(text: widget.config.anonKey);
  bool _testing = false;
  String _testResult = '';

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bedCtrl.dispose();
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    final cfg = SBConfig(
      url: _urlCtrl.text.trim(),
      anonKey: _keyCtrl.text.trim(),
    );
    if (!cfg.isConfigured) {
      setState(() => _testResult = '两项都要填。');
      return;
    }
    setState(() {
      _testing = true;
      _testResult = '';
    });
    try {
      final client = SBClient(cfg);
      await client.query('Member', limit: 1);
      await widget.onSaveConfig(cfg);
      setState(() => _testResult = '连接成功，已保存。苹果安卓现在用的是同一份数据。');
    } catch (e) {
      setState(() => _testResult = '连不上：$e\n检查 Project URL / anon key 有没有填错。');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('我的身份', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(labelText: '昵称', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _bedCtrl,
          decoration: const InputDecoration(labelText: '床位', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: kNavy, foregroundColor: Colors.white),
          onPressed: () async {
            final name = _nameCtrl.text.trim();
            if (name.isEmpty) return;
            await widget.onSaveNickname(name, _bedCtrl.text.trim());
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('身份已保存')));
            }
          },
          child: const Text('保存身份'),
        ),
        const SizedBox(height: 24),
        const Text('后端配置（Supabase 免费版）', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text(
          '在 supabase.com 注册并创建项目，在「Project Settings → API」里找到这两项。只填 anon key，不要填 service_role key。',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _urlCtrl,
          decoration: const InputDecoration(
            labelText: 'Project URL',
            hintText: '如 https://abcdefghijklm.supabase.co',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _keyCtrl,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'anon key', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: kNavy, foregroundColor: Colors.white),
          onPressed: _testing ? null : _testConnection,
          child: _testing
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('测试连接并保存'),
        ),
        if (_testResult.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(_testResult, style: const TextStyle(fontSize: 13)),
        ],
        const SizedBox(height: 24),
        const Text('关于', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text(
          '511宿舍公务系统 v1.0\n数据存在你自己的 Supabase 项目里，只有你们宿舍的人能看到。App 不收集聊天内容以外的任何数据，不读取通讯录，不后台运行。',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
      ],
    );
  }
}
