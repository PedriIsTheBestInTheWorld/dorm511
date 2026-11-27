import 'package:flutter/material.dart';
import 'supabase.dart';
import 'models.dart';
import 'main.dart';

/// 首页：公告 + 本周值日 + 官员榜。
class HomeScreen extends StatefulWidget {
  final SBClient? client;
  final String nickname;
  final VoidCallback onGoSettings;
  const HomeScreen({super.key, required this.client, required this.nickname, required this.onGoSettings});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Notice> _notices = [];
  List<Member> _members = [];
  List<Office> _offices = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final client = widget.client;
    if (client == null) return;
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        client.query('Notice', order: '-createdAt', limit: 20),
        client.query('Member', order: 'createdAt', limit: 50),
        client.query('Office', order: 'createdAt', limit: 20),
      ]);
      var offices = results[2].map(Office.fromJson).toList();
      // 职位表为空时，自动创建默认职位。
      if (offices.isEmpty) {
        for (final t in defaultOffices) {
          await client.create('Office', {'name': t, 'holder': '空缺', 'since': ''});
        }
        final again = await client.query('Office', order: 'createdAt', limit: 20);
        offices = again.map(Office.fromJson).toList();
      }
      if (!mounted) return;
      setState(() {
        _notices = results[0].map(Notice.fromJson).toList();
        _members = results[1].map(Member.fromJson).toList();
        _offices = offices;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载失败：$e')));
    }
  }

  String _dutyText() {
    if (_members.isEmpty) return '还没有成员，先去「我的」完善身份，或等室友加入。';
    final now = DateTime.now();
    final dayOfYear = now.difference(DateTime(now.year, 1, 1)).inDays;
    final week = dayOfYear ~/ 7;
    final idx = week % _members.length;
    final sb = StringBuffer('本周值日：${_members[idx].name}');
    for (var i = 1; i <= 3; i++) {
      final m = _members[(week + i) % _members.length];
      sb.write('\n第 ${i + 1} 周：${m.name}');
    }
    return sb.toString();
  }

  Future<void> _addNotice() async {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('发公告'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: '标题', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: bodyCtrl, maxLines: 4, decoration: const InputDecoration(labelText: '内容', border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kNavy, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('发布'),
          ),
        ],
      ),
    );
    if (ok != true || titleCtrl.text.trim().isEmpty) return;
    try {
      await widget.client!.create('Notice', {
        'title': titleCtrl.text.trim(),
        'content': bodyCtrl.text.trim(),
        'author': widget.nickname,
      });
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('发布失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    if (client == null) return NotConfiguredCard(onGoSettings: widget.onGoSettings);
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _addNotice,
        child: const Icon(Icons.campaign),
      ),
      body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.cleaning_services, color: kNavy),
              title: const Text('值日表', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(_dutyText()),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('官员榜', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => OfficersScreen(client: client, nickname: widget.nickname)),
                ).then((_) => _load()),
                child: const Text('任命管理 >'),
              ),
            ],
          ),
          if (_offices.isEmpty)
            const Card(child: ListTile(title: Text('暂无职位')))
          else
            ..._offices.map((o) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.badge, color: kGold),
                    title: Text(o.title),
                    subtitle: Text('现任：${o.holder}${o.since.isEmpty ? '' : '（${o.since}上任）'}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => OfficersScreen(client: client, nickname: widget.nickname)),
                    ).then((_) => _load()),
                  ),
                )),
          const SizedBox(height: 12),
          const Text('宿舍公告', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (_notices.isEmpty)
            const Card(child: ListTile(title: Text('暂无公告，点右下角发一条。')))
          else
            ..._notices.map((n) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.campaign, color: kNavy),
                    title: Text(n.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${n.body}\n${n.author} · ${n.timeText}'),
                    isThreeLine: true,
                  ),
                )),
          const SizedBox(height: 72),
        ],
      ),
      ),
    );
  }
}

/// 官员任命管理：职位列表、添加职位、发起任命投票。
class OfficersScreen extends StatefulWidget {
  final SBClient client;
  final String nickname;
  const OfficersScreen({super.key, required this.client, required this.nickname});

  @override
  State<OfficersScreen> createState() => _OfficersScreenState();
}

class _OfficersScreenState extends State<OfficersScreen> {
  List<Office> _offices = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await widget.client.query('Office', order: 'createdAt', limit: 20);
      if (!mounted) return;
      setState(() {
        _offices = rows.map(Office.fromJson).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载失败：$e')));
    }
  }

  Future<void> _addOffice() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加职位'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: '职位名，如：熄灯监督员', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kNavy, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    try {
      await widget.client.create('Office', {'name': ctrl.text.trim(), 'holder': '空缺', 'since': ''});
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('添加失败：$e')));
    }
  }

  Future<void> _startAppointmentPoll(Office office) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('任命「${office.title}」'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('输入候选人昵称，发起任命投票。投票截止后，得票最高者当选，再点“执行任命”生效。'),
            const SizedBox(height: 12),
            TextField(controller: ctrl, decoration: const InputDecoration(labelText: '候选人昵称', border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kNavy, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('发起投票'),
          ),
        ],
      ),
    );
    final candidate = ctrl.text.trim();
    if (ok != true || candidate.isEmpty) return;
    try {
      await widget.client.create('Poll', {
        'title': '任命${office.title}：$candidate',
        'type': 'appointment',
        'options': [candidate, '维持现状'],
        'status': 'open',
        'office_id': office.objectId,
        'created_by': widget.nickname,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('任命投票已发起，去「投票」页查看。')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('发起失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('官员任命')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _offices.length,
                itemBuilder: (ctx, i) {
                  final o = _offices[i];
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.badge, color: kGold),
                      title: Text(o.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('现任：${o.holder}${o.since.isEmpty ? '' : '（${o.since}上任）'}'),
                      trailing: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: kNavy, foregroundColor: Colors.white),
                        onPressed: () => _startAppointmentPoll(o),
                        child: const Text('发起任命'),
                      ),
                    ),
                  );
                },
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addOffice,
        child: const Icon(Icons.add),
      ),
    );
  }
}
