import 'dart:async';
import 'package:flutter/material.dart';
import 'supabase.dart';
import 'models.dart';
import 'main.dart';

/// 投票列表。
class VoteScreen extends StatefulWidget {
  final SBClient? client;
  final String nickname;
  final VoidCallback onGoSettings;
  const VoteScreen({super.key, required this.client, required this.nickname, required this.onGoSettings});

  @override
  State<VoteScreen> createState() => _VoteScreenState();
}

class _VoteScreenState extends State<VoteScreen> {
  List<Poll> _polls = [];
  Map<String, List<Vote>> _votesByPoll = {};
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
      final pollRows = await client.query('Poll', order: '-createdAt', limit: 50);
      final voteRows = await client.query('Vote', order: '-createdAt', limit: 500);
      if (!mounted) return;
      final votes = voteRows.map(Vote.fromJson).toList();
      final map = <String, List<Vote>>{};
      for (final v in votes) {
        map.putIfAbsent(v.pollId, () => []).add(v);
      }
      setState(() {
        _polls = pollRows.map(Poll.fromJson).toList();
        _votesByPoll = map;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载失败：$e')));
    }
  }

  String _summary(Poll p) {
    final votes = _votesByPoll[p.objectId] ?? [];
    if (votes.isEmpty) return '暂无投票';
    final counts = List.filled(p.options.length, 0);
    for (final v in votes) {
      if (v.optionIndex >= 0 && v.optionIndex < counts.length) counts[v.optionIndex]++;
    }
    final parts = <String>[];
    for (var i = 0; i < p.options.length; i++) {
      parts.add('${p.options[i]} ${counts[i]}票');
    }
    return parts.join(' · ');
  }

  Future<void> _createPoll() async {
    final titleCtrl = TextEditingController();
    final optsCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('发起投票'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: '议题，如：周末要不要大扫除', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(
              controller: optsCtrl,
              decoration: const InputDecoration(
                labelText: '选项（用逗号隔开，2~4个）',
                hintText: '要，不用，再说',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kNavy, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('发起'),
          ),
        ],
      ),
    );
    final title = titleCtrl.text.trim();
    final options = optsCtrl.text.split(RegExp(r'[,，]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (ok != true || title.isEmpty || options.length < 2 || options.length > 4) {
      if (ok == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('标题必填，选项 2~4 个')));
      }
      return;
    }
    try {
      await widget.client!.create('Poll', {
        'title': title,
        'type': 'general',
        'options': options,
        'status': 'open',
        'created_by': widget.nickname,
      });
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('发起失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    if (client == null) return NotConfiguredCard(onGoSettings: widget.onGoSettings);
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: _polls.isEmpty
            ? ListView(
                padding: const EdgeInsets.all(16),
                children: const [Card(child: ListTile(title: Text('暂无投票，点右下角发起一个。')))],
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _polls.length,
                itemBuilder: (ctx, i) {
                  final p = _polls[i];
                  return Card(
                    child: ListTile(
                      leading: Icon(
                        p.isAppointment ? Icons.badge : Icons.how_to_vote,
                        color: p.isOpen ? kNavy : Colors.grey,
                      ),
                      title: Text(p.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        '${p.isAppointment ? '任命投票' : '一般投票'} · ${p.isOpen ? '进行中' : '已截止'} · ${_summary(p)}\n${p.createdBy} · ${p.timeText}',
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PollDetailScreen(client: client, poll: p, nickname: widget.nickname),
                        ),
                      ).then((_) => _load()),
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createPoll,
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// 投票详情：投票、看结果、截止、执行任命。
class PollDetailScreen extends StatefulWidget {
  final SBClient client;
  final Poll poll;
  final String nickname;
  const PollDetailScreen({super.key, required this.client, required this.poll, required this.nickname});

  @override
  State<PollDetailScreen> createState() => _PollDetailScreenState();
}

class _PollDetailScreenState extends State<PollDetailScreen> {
  List<Vote> _votes = [];
  bool _loading = true;
  int? _selected;
  late Poll _poll;

  @override
  void initState() {
    super.initState();
    _poll = widget.poll;
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await widget.client.query(
        'Vote',
        where: {'poll_id': _poll.objectId},
        order: '-createdAt',
        limit: 200,
      );
      if (!mounted) return;
      setState(() {
        _votes = rows.map(Vote.fromJson).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载失败：$e')));
    }
  }

  List<int> get _counts {
    final c = List.filled(_poll.options.length, 0);
    for (final v in _votes) {
      if (v.optionIndex >= 0 && v.optionIndex < c.length) c[v.optionIndex]++;
    }
    return c;
  }

  bool get _iVoted => _votes.any((v) => v.voter == widget.nickname);

  Future<void> _vote() async {
    if (_selected == null) return;
    if (_iVoted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('你已经投过票了')));
      return;
    }
    try {
      await widget.client.create('Vote', {
        'poll_id': _poll.objectId,
        'voter': widget.nickname,
        'option': _selected,
      });
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('投票失败：$e')));
    }
  }

  Future<void> _closePoll() async {
    try {
      await widget.client.update('Poll', _poll.objectId!, {'status': 'closed'});
      setState(() {
        _poll = Poll(
          objectId: _poll.objectId,
          title: _poll.title,
          type: _poll.type,
          options: _poll.options,
          status: 'closed',
          officeId: _poll.officeId,
          createdBy: _poll.createdBy,
          createdAt: _poll.createdAt,
        );
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('投票已截止')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('截止失败：$e')));
    }
  }

  Future<void> _executeAppointment() async {
    if (!_poll.isAppointment || _poll.officeId == null) return;
    final counts = _counts;
    var winner = 0;
    for (var i = 1; i < counts.length; i++) {
      if (counts[i] > counts[winner]) winner = i;
    }
    // 选项 0 是候选人，选项 1 是“维持现状”。
    if (winner != 0 || counts[0] == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('当选的不是候选人，不执行任命')));
      return;
    }
    final candidate = _poll.options[0];
    final now = DateTime.now();
    final since = '${now.year}-${now.month}-${now.day}';
    try {
      await widget.client.update('Office', _poll.officeId!, {'holder': candidate, 'since': since});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已任命 $candidate，任职已更新')));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('任命失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final counts = _counts;
    final total = counts.fold(0, (a, b) => a + b);
    return Scaffold(
      appBar: AppBar(title: Text(_poll.isAppointment ? '任命投票' : '投票详情')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(_poll.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('${_poll.createdBy} 发起 · ${_poll.timeText} · ${_poll.isOpen ? '进行中' : '已截止'} · 共 $total 票',
                      style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 16),
                  ...List.generate(_poll.options.length, (i) {
                    final pct = total == 0 ? 0.0 : counts[i] / total;
                    final mine = _votes.any((v) => v.voter == widget.nickname && v.optionIndex == i);
                    return Card(
                      child: ListTile(
                        leading: Radio<int>(
                          value: i,
                          groupValue: _selected,
                          onChanged: _poll.isOpen && !_iVoted ? (v) => setState(() => _selected = v) : null,
                        ),
                        title: Text('${_poll.options[i]}${mine ? '（你的选择）' : ''}'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            LinearProgressIndicator(
                              value: pct,
                              backgroundColor: Colors.grey[200],
                              color: kNavy,
                            ),
                            const SizedBox(height: 4),
                            Text('${counts[i]} 票 · ${(pct * 100).toStringAsFixed(0)}%'),
                          ],
                        ),
                        onTap: _poll.isOpen && !_iVoted ? () => setState(() => _selected = i) : null,
                      ),
                    );
                  }),
                  const SizedBox(height: 16),
                  if (_poll.isOpen && !_iVoted)
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: kNavy, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                      onPressed: _selected == null ? null : _vote,
                      child: const Text('投出这一票', style: TextStyle(fontSize: 16)),
                    ),
                  if (_poll.isOpen && _iVoted)
                    const Text('你已经投过票了，结果实时更新。', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                  if (_poll.isOpen) ...[
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _closePoll,
                      child: const Text('截止投票'),
                    ),
                  ],
                  if (!_poll.isOpen && _poll.isAppointment) ...[
                    const SizedBox(height: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: kGold, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                      onPressed: _executeAppointment,
                      child: const Text('执行任命：得票最高者上任', style: TextStyle(fontSize: 16)),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

/// 宿舍群聊：5 秒轮询 + 下拉刷新。
class ChatScreen extends StatefulWidget {
  final SBClient? client;
  final String nickname;
  final VoidCallback onGoSettings;
  const ChatScreen({super.key, required this.client, required this.nickname, required this.onGoSettings});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  List<ChatMessage> _messages = [];
  bool _loading = true;
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  Timer? _timer;
  bool _firstLoad = true;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && widget.client != null) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final client = widget.client;
    if (client == null) return;
    try {
      final rows = await client.query('ChatMessage', order: 'createdAt', limit: 100);
      if (!mounted) return;
      setState(() {
        _messages = rows.map(ChatMessage.fromJson).toList();
        _loading = false;
      });
      if (_firstLoad || silent) {
        _firstLoad = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollCtrl.hasClients) {
            _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载失败：$e')));
      }
    }
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    _inputCtrl.clear();
    try {
      await widget.client!.create('ChatMessage', {'sender': widget.nickname, 'content': text});
      await _load();
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('发送失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    if (client == null) return NotConfiguredCard(onGoSettings: widget.onGoSettings);
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _load(),
            child: _messages.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(16),
                    children: const [Card(child: ListTile(title: Text('宿舍群还没人说话，你先开个头。')))],
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (ctx, i) {
                      final m = _messages[i];
                      final mine = m.sender == widget.nickname;
                      return Align(
                        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                          decoration: BoxDecoration(
                            color: mine ? kNavy : Colors.grey[200],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${m.sender} · ${m.timeText}',
                                style: TextStyle(fontSize: 11, color: mine ? Colors.white70 : Colors.grey),
                              ),
                              Text(
                                m.text,
                                style: TextStyle(fontSize: 15, color: mine ? Colors.white : Colors.black),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey[300]!)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inputCtrl,
                  decoration: const InputDecoration(
                    hintText: '在宿舍群里说点什么…',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.send, color: kNavy),
                onPressed: _send,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
