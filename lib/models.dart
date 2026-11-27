/// 511宿舍公务系统的数据模型（与 LeanCloud 类一一对应）。

DateTime? _parseDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  return DateTime.tryParse(v.toString());
}

String _fmtTime(DateTime? t) {
  if (t == null) return '';
  final d = t.toLocal();
  final m = d.minute.toString().padLeft(2, '0');
  final h = d.hour.toString().padLeft(2, '0');
  return '${d.month}/${d.day} $h:$m';
}

class Member {
  final String? objectId;
  final String name;
  final String bed;
  final int merit; // 功德
  final int coins; // 哈夫币
  final DateTime? createdAt;

  Member({
    this.objectId,
    required this.name,
    required this.bed,
    this.merit = 0,
    this.coins = 0,
    this.createdAt,
  });

  factory Member.fromJson(Map<String, dynamic> j) => Member(
        objectId: j['objectId'],
        name: j['name'] ?? '',
        bed: j['bed'] ?? '',
        merit: (j['merit'] as num?)?.toInt() ?? 0,
        coins: (j['coins'] as num?)?.toInt() ?? 0,
        createdAt: _parseDate(j['createdAt']),
      );

  Map<String, dynamic> toJson() =>
      {'name': name, 'bed': bed, 'merit': merit, 'coins': coins};
}

class Notice {
  final String? objectId;
  final String title;
  final String body;
  final String author;
  final DateTime? createdAt;

  Notice({this.objectId, required this.title, required this.body, required this.author, this.createdAt});

  factory Notice.fromJson(Map<String, dynamic> j) => Notice(
        objectId: j['objectId'],
        title: j['title'] ?? '',
        body: j['body'] ?? '',
        author: j['author'] ?? '',
        createdAt: _parseDate(j['createdAt']),
      );

  Map<String, dynamic> toJson() =>
      {'title': title, 'body': body, 'author': author};

  String get timeText => _fmtTime(createdAt);
}

class Office {
  final String? objectId;
  final String title;
  final String holder;
  final String since;

  Office({this.objectId, required this.title, required this.holder, required this.since});

  factory Office.fromJson(Map<String, dynamic> j) => Office(
        objectId: j['objectId'],
        title: j['title'] ?? '',
        holder: j['holder'] ?? '空缺',
        since: j['since'] ?? '',
      );

  Map<String, dynamic> toJson() =>
      {'title': title, 'holder': holder, 'since': since};
}

class Poll {
  final String? objectId;
  final String title;
  final String type; // general 或 appointment
  final List<String> options;
  final String status; // open 或 closed
  final String? officeId;
  final String createdBy;
  final DateTime? createdAt;

  Poll({
    this.objectId,
    required this.title,
    required this.type,
    required this.options,
    required this.status,
    this.officeId,
    required this.createdBy,
    this.createdAt,
  });

  factory Poll.fromJson(Map<String, dynamic> j) => Poll(
        objectId: j['objectId'],
        title: j['title'] ?? '',
        type: j['type'] ?? 'general',
        options: (j['options'] as List? ?? []).map((e) => e.toString()).toList(),
        status: j['status'] ?? 'open',
        officeId: j['officeId'],
        createdBy: j['createdBy'] ?? '',
        createdAt: _parseDate(j['createdAt']),
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'type': type,
        'options': options,
        'status': status,
        if (officeId != null) 'officeId': officeId,
        'createdBy': createdBy,
      };

  bool get isOpen => status == 'open';
  bool get isAppointment => type == 'appointment';
  String get timeText => _fmtTime(createdAt);
}

class Vote {
  final String? objectId;
  final String pollId;
  final String voter;
  final int optionIndex;

  Vote({this.objectId, required this.pollId, required this.voter, required this.optionIndex});

  factory Vote.fromJson(Map<String, dynamic> j) => Vote(
        objectId: j['objectId'],
        pollId: j['pollId'] ?? '',
        voter: j['voter'] ?? '',
        optionIndex: (j['optionIndex'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() =>
      {'pollId': pollId, 'voter': voter, 'optionIndex': optionIndex};
}

class ChatMessage {
  final String? objectId;
  final String sender;
  final String text;
  final DateTime? createdAt;

  ChatMessage({this.objectId, required this.sender, required this.text, this.createdAt});

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        objectId: j['objectId'],
        sender: j['sender'] ?? '',
        text: j['text'] ?? '',
        createdAt: _parseDate(j['createdAt']),
      );

  Map<String, dynamic> toJson() => {'sender': sender, 'text': text};

  String get timeText => _fmtTime(createdAt);
}

/// 维护记录：功德/哈夫币变动、任命、改名都记一笔，宿舍里有据可查。
class Ledger {
  final String? objectId;
  final String kind; // merit / coins / appoint / rename
  final String member;
  final int amount;
  final String note;
  final String by;
  final DateTime? createdAt;

  Ledger({
    this.objectId,
    required this.kind,
    required this.member,
    required this.amount,
    required this.note,
    required this.by,
    this.createdAt,
  });

  factory Ledger.fromJson(Map<String, dynamic> j) => Ledger(
        objectId: j['objectId'],
        kind: j['kind'] ?? '',
        member: j['member'] ?? '',
        amount: (j['amount'] as num?)?.toInt() ?? 0,
        note: j['note'] ?? '',
        by: j['by'] ?? '',
        createdAt: _parseDate(j['createdAt']),
      );

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'member': member,
        'amount': amount,
        'note': note,
        'by': by,
      };

  String get timeText => _fmtTime(createdAt);

  String get display {
    final sign = amount >= 0 ? '+' : '';
    switch (kind) {
      case 'merit':
        return '$member 功德 $sign$amount';
      case 'coins':
        return '$member 哈夫币 $sign$amount';
      case 'appoint':
        return '$member 被任命为 $note';
      case 'rename':
        return '职务改名：$note';
      default:
        return '$member $note';
    }
  }
}

/// 默认职位（首次打开、职位表为空时自动创建）。
const defaultOffices = ['舍长', '副舍长', '卫生委员', '纪律委员', '生活委员', '学习委员'];
