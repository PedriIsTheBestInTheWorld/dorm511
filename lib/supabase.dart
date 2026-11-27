import 'dart:convert';
import 'package:http/http.dart' as http;

/// Supabase 配置（用户在 supabase.com 免费建项目后填入）。
/// 注意：这里只用 anon key（公开密钥），绝不用 service_role key
///（那是管理员密钥，一旦泄露等于把数据库完全公开）。
class SBConfig {
  final String url; // 如 https://abcdefghijklm.supabase.co
  final String anonKey;

  const SBConfig({required this.url, required this.anonKey});

  bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;

  Map<String, dynamic> toJson() => {'url': url, 'anonKey': anonKey};

  factory SBConfig.fromJson(Map<String, dynamic> j) => SBConfig(
        url: j['url'] ?? '',
        anonKey: j['anonKey'] ?? '',
      );

  static const empty = SBConfig(url: '', anonKey: '');
}

/// Supabase PostgREST 客户端（只用 http 包，不依赖 supabase-flutter SDK）。
///
/// 公开方法刻意和原来的 LCClient 保持一致（query/create/update/delete），
/// 各 screen 基本不用改，只改字段名。
/// 内部做两层翻译，让调用处能沿用 LeanCloud 时期的写法：
/// - 表名：'Member' → 'members'、'ChatMessage' → 'chat_messages'……
/// - where/order 的键：camelCase → snake_case（'pollId' → 'poll_id'，
///   '-createdAt' → 'created_at.desc'）。
/// 行数据的字段名不在这里翻译，models.dart 直接按 Supabase 列名读写。
class SBClient {
  final SBConfig config;
  SBClient(this.config);

  Map<String, String> get _headers => {
        'apikey': config.anonKey,
        'Authorization': 'Bearer ${config.anonKey}',
        'Content-Type': 'application/json',
      };

  String get _base => config.url.replaceAll(RegExp(r'/$'), '');

  /// 旧 LeanCloud 类名 → Supabase 表名。
  static const _tables = {
    'Member': 'members',
    'Notice': 'notices',
    'Office': 'offices',
    'Poll': 'polls',
    'Vote': 'votes',
    'ChatMessage': 'chat_messages',
    'Ledger': 'ledger',
    'Meta': 'meta',
  };

  String _table(String name) => _tables[name] ?? name;

  /// camelCase → snake_case，如 pollId → poll_id、createdAt → created_at。
  static String _snake(String s) =>
      s.replaceAllMapped(RegExp(r'[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');

  /// '-createdAt' → 'created_at.desc'，'createdAt' → 'created_at.asc'。
  static String? _orderParam(String? order) {
    if (order == null) return null;
    final desc = order.startsWith('-');
    final col = _snake(desc ? order.substring(1) : order);
    return '$col.${desc ? 'desc' : 'asc'}';
  }

  String _errorMessage(String body) {
    try {
      final data = jsonDecode(body) as Map<String, dynamic>;
      final msg = data['message'];
      if (msg is String && msg.isNotEmpty) return msg;
    } catch (_) {}
    return body.length > 120 ? '${body.substring(0, 120)}…' : body;
  }

  Future<List<Map<String, dynamic>>> query(
    String className, {
    Map<String, dynamic>? where,
    String? order,
    int limit = 100,
  }) async {
    final params = <String, String>{'select': '*', 'limit': '$limit'};
    where?.forEach((k, v) {
      params[_snake(k)] = 'eq.${v.toString()}';
    });
    final orderParam = _orderParam(order);
    if (orderParam != null) params['order'] = orderParam;
    final uri = Uri.parse('$_base/rest/v1/${_table(className)}')
        .replace(queryParameters: params);
    final resp = await http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw Exception('查询失败 ${resp.statusCode}：${_errorMessage(resp.body)}');
    }
    final data = jsonDecode(resp.body) as List;
    return data.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> create(
      String className, Map<String, dynamic> fields) async {
    final uri = Uri.parse('$_base/rest/v1/${_table(className)}');
    final resp = await http
        .post(uri,
            headers: {..._headers, 'Prefer': 'return=representation'},
            body: jsonEncode(fields))
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 201) {
      throw Exception('保存失败 ${resp.statusCode}：${_errorMessage(resp.body)}');
    }
    final data = jsonDecode(resp.body) as List;
    if (data.isEmpty) return <String, dynamic>{};
    return data.first as Map<String, dynamic>;
  }

  Future<void> update(
      String className, String objectId, Map<String, dynamic> fields) async {
    final uri = Uri.parse('$_base/rest/v1/${_table(className)}')
        .replace(queryParameters: {'id': 'eq.$objectId'});
    final resp = await http
        .patch(uri, headers: _headers, body: jsonEncode(fields))
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200 && resp.statusCode != 204) {
      throw Exception('更新失败 ${resp.statusCode}：${_errorMessage(resp.body)}');
    }
  }

  Future<void> delete(String className, String objectId) async {
    final uri = Uri.parse('$_base/rest/v1/${_table(className)}')
        .replace(queryParameters: {'id': 'eq.$objectId'});
    final resp = await http
        .delete(uri, headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200 && resp.statusCode != 204) {
      throw Exception('删除失败 ${resp.statusCode}：${_errorMessage(resp.body)}');
    }
  }
}
