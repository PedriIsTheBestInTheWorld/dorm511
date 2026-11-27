import 'package:flutter/material.dart';
import 'supabase.dart';
import 'models.dart';
import 'main.dart';

/// 维护页入口：密码门。
/// 密码存在共用的 Supabase 后端（meta 表），不在任何一台手机本地，
/// 所以不管在哪台手机上打开维护页，都得输同一个密码 —— 别人进不去。
/// 第一次打开由维护者本人设一个 4 位数字密码。
class MaintainGate extends StatefulWidget {
  final SBClient? client;
  final String nickname;
  final VoidCallback onGoSettings;
  const MaintainGate({
    super.key,
    required this.client,
    required this.nickname,
    required this.onGoSettings,
  });

  @override
  State<MaintainGate> createState() => _MaintainGateState();
}

class _MaintainGateState extends State<MaintainGate> {
  bool _checking = true;
  bool _pinSet = false;
  bool _unlocked = false;
  String? _savedPin;
  final _pinCtrl = TextEditingController();
  final _setupCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  String _error = '';

  @override
  void initState() {
    super.initState();
    _checkPin();
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    _setupCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkPin() async {
    final client = widget.client;
    if (client == null) {
      setState(() => _checking = false);
      return;
    }
    try {
      final rows =
          await client.query('Meta', where: {'key': 'maintainer_pin'});
      if (!mounted) return;
      setState(() {
        _pinSet = rows.isNotEmpty;
        _savedPin = rows.isEmpty ? null : rows.first['value']?.toString();
        _checking = false;
      });
    } catch (_) {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _setupPin() async {
    final pin = _setupCtrl.text.trim();
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      setState(() => _error = '密码要是 4 位数字。');
      return;
    }
    if (pin != _confirmCtrl.text.trim()) {
      setState(() => _error = '两次输入的不一样。');
      return;
    }
    final client = widget.client;
    if (client == null) return;
    try {
      await client
          .create('Meta', {'key': 'maintainer_pin', 'value': pin});
      if (!mounted) return;
      setState(() {
        _savedPin = pin;
        _pinSet = true;
        _unlocked = true;
        _error = '';
      });
    } catch (e) {
      setState(() => _error = '保存失败：$e');
    }
  }

  void _enter() {
    if (_pinCtrl.text.trim() == _savedPin) {
      setState(() {
        _unlocked = true;
        _error = '';
      });
    } else {
      setState(() => _error = '密码不对，进不去。');
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    if (client == null) {
      return NotConfiguredCard(onGoSettings: widget.onGoSettings);
    }
    if (_checking) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_unlocked) {
      return MaintainScreen(client: client, nickname: widget.nickname);
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.admin_panel_settings, size: 56, color: kNavy),
            const SizedBox(height: 12),
            Text(
              _pinSet ? '维护页 · 请输入维护密码' : '维护页 · 第一次打开请设密码',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '密码存在宿舍共用的后端里，设好后不管在哪台手机上打开维护页都要输这个密码，别人进不去。4 位数字，防宿舍里其他人随手点进来，不是银行级加密。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            if (!_pinSet) ...[
              TextField(
                controller: _setupCtrl,
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '设一个 4 位维护密码',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _confirmCtrl,
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '再输一遍',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: kNavy, foregroundColor: Colors.white),
                onPressed: _setupPin,
                child: const Text('设为维护密码并进入'),
              ),
            ] else ...[
              TextField(
                controller: _pinCtrl,
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '4 位维护密码',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
                onSubmitted: (_) => _enter(),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: kNavy, foregroundColor: Colors.white),
                onPressed: _enter,
                child: const Text('进入维护页'),
              ),
            ],
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_error,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}

/// 维护页：功德 / 哈夫币 / 职务任命 / 记录。
class MaintainScreen extends StatefulWidget {
  final SBClient client;
  final String nickname;
  const MaintainScreen(
      {super.key, required this.client, required this.nickname});

  @override
  State<MaintainScreen> createState() => _MaintainScreenState();
}

class _MaintainScreenState extends State<MaintainScreen> {
  List<Member> _members = [];
  List<Office> _offices = [];
  List<Ledger> _ledger = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        widget.client.query('Member', limit: 100),
        widget.client.query('Office', limit: 100),
        widget.client.query('Ledger', order: '-createdAt', limit: 20),
      ]);
      if (!mounted) return;
      setState(() {
        _members =
            results[0].map((e) => Member.fromJson(e)).toList();
        _offices =
            results[1].map((e) => Office.fromJson(e)).toList();
        _ledger =
            results[2].map((e) => Ledger.fromJson(e)).toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  String _today() {
    final d = DateTime.now();
    return '${d.year}-${d.month}-${d.day}';
  }

  /// 给成员调功德 / 哈夫币。
  Future<void> _adjustMember(Member m) async {
    int meritDelta = 0;
    int coinsDelta = 0;
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text('${m.name}（${m.bed}）'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _stepperRow('功德', meritDelta, (v) => setDlg(() => meritDelta = v)),
              const SizedBox(height: 8),
              _stepperRow('哈夫币', coinsDelta, (v) => setDlg(() => coinsDelta = v)),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                  labelText: '理由（记到记录里，如：打扫卫生）',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: kNavy, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    final note = noteCtrl.text.trim();
    noteCtrl.dispose();
    if (ok != true || m.objectId == null) return;
    if (meritDelta == 0 && coinsDelta == 0) return;
    try {
      await widget.client.update('Member', m.objectId!, {
        'merit': m.merit + meritDelta,
        'coins': m.coins + coinsDelta,
      });
      if (meritDelta != 0) {
        await widget.client.create('Ledger', {
          'kind': 'merit',
          'member': m.name,
          'amount': meritDelta,
          'note': note,
          'by': widget.nickname,
        });
      }
      if (coinsDelta != 0) {
        await widget.client.create('Ledger', {
          'kind': 'coins',
          'member': m.name,
          'amount': coinsDelta,
          'note': note,
          'by': widget.nickname,
        });
      }
      _snack('已保存');
      _load();
    } catch (e) {
      _snack('保存失败：$e');
    }
  }

  Widget _stepperRow(String label, int value, ValueChanged<int> onChange) {
    return Row(
      children: [
        SizedBox(width: 48, child: Text(label)),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: () => onChange(value - 5),
        ),
        IconButton(
          icon: const Icon(Icons.remove),
          onPressed: () => onChange(value - 1),
        ),
        Expanded(
          child: Text(
            value >= 0 ? '+$value' : '$value',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add),
          onPressed: () => onChange(value + 1),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () => onChange(value + 5),
        ),
      ],
    );
  }

  /// 职务改名。
  Future<void> _renameOffice(Office o) async {
    final ctrl = TextEditingController(text: o.title);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('职务改名'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: '新的职务名字',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: kNavy, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    final newTitle = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true || o.objectId == null) return;
    if (newTitle.isEmpty || newTitle == o.title) return;
    try {
      await widget.client
          .update('Office', o.objectId!, {'name': newTitle});
      await widget.client.create('Ledger', {
        'kind': 'rename',
        'member': o.holder,
        'amount': 0,
        'note': '${o.title} → $newTitle',
        'by': widget.nickname,
      });
      _snack('已改名');
      _load();
    } catch (e) {
      _snack('保存失败：$e');
    }
  }

  /// 任命某人担任某职务。
  Future<void> _appoint(Office o) async {
    String? picked = o.holder;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('任命${o.title}'),
        content: DropdownButtonFormField<String>(
          value: _members.any((m) => m.name == picked) ? picked : null,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          items: [
            const DropdownMenuItem(value: '空缺', child: Text('空缺')),
            ..._members.map((m) => DropdownMenuItem(
                value: m.name, child: Text('${m.name}（${m.bed}）'))),
          ],
          onChanged: (v) => picked = v,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: kNavy, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('任命'),
          ),
        ],
      ),
    );
    if (ok != true || o.objectId == null) return;
    final holder = picked ?? '空缺';
    try {
      await widget.client.update(
          'Office', o.objectId!, {'holder': holder, 'since': _today()});
      await widget.client.create('Ledger', {
        'kind': 'appoint',
        'member': holder,
        'amount': 0,
        'note': o.title,
        'by': widget.nickname,
      });
      _snack('已任命');
      _load();
    } catch (e) {
      _snack('保存失败：$e');
    }
  }

  /// 新增职务。
  Future<void> _addOffice() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新增职务'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: '职务名字（如：夜宵委员）',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: kNavy, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    final title = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true || title.isEmpty) return;
    try {
      await widget.client.create(
          'Office', {'name': title, 'holder': '空缺', 'since': ''});
      _snack('已添加');
      _load();
    } catch (e) {
      _snack('保存失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('成员功德 · 哈夫币',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('点一个人就能加减功德、发哈夫币，每一笔都记在下面的记录里。',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 8),
          if (_members.isEmpty)
            const Card(child: ListTile(title: Text('还没有成员，先让大家在首页登记昵称。'))),
          for (final m in _members)
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: kNavy,
                  foregroundColor: Colors.white,
                  child: Text(m.name.isEmpty ? '?' : m.name[0]),
                ),
                title: Text('${m.name}（${m.bed}）'),
                subtitle: Text('功德 ${m.merit} · 哈夫币 ${m.coins}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _adjustMember(m),
              ),
            ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('职务任命',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('新增职务'),
                onPressed: _addOffice,
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text('改职务名字、直接任命某人上任，不用走投票。',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 8),
          if (_offices.isEmpty)
            const Card(child: ListTile(title: Text('还没有职务。'))),
          for (final o in _offices)
            Card(
              child: ListTile(
                title: Text(o.title),
                subtitle: Text(
                    '现任：${o.holder}${o.since.isEmpty ? '' : ' · 自 ${o.since}'}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                        onPressed: () => _renameOffice(o),
                        child: const Text('改名')),
                    TextButton(
                        onPressed: () => _appoint(o),
                        child: const Text('任命')),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 24),
          const Text('最近记录',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (_ledger.isEmpty)
            const Card(child: ListTile(title: Text('暂无记录。'))),
          for (final r in _ledger)
            Card(
              child: ListTile(
                title: Text(r.display),
                subtitle: Text('${r.by} 操作 · ${r.timeText}'
                    '${r.note.isEmpty ? '' : ' · ${r.note}'}'),
              ),
            ),
        ],
      ),
    );
  }
}
