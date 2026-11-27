import 'dart:convert';
import 'package:http/http.dart' as http;

/// LeanCloud 配置（用户在 leancloud.app 免费注册后填入）。
/// 注意：这里只用 App Key，绝不用 Master Key。
class LCConfig {
  final String appId;
  final String appKey;
  final String server; // 如 https://xxx.lc-cn-n1-shared.com

  const LCConfig({required this.appId, required this.appKey, required this.server});

  bool get isConfigured =>
      appId.isNotEmpty && appKey.isNotEmpty && server.isNotEmpty;

  Map<String, dynamic> toJson() =>
      {'appId': appId, 'appKey': appKey, 'server': server};

  factory LCConfig.fromJson(Map<String, dynamic> j) => LCConfig(
        appId: j['appId'] ?? '',
        appKey: j['appKey'] ?? '',
        server: j['server'] ?? '',
      );

  static const empty = LCConfig(appId: '', appKey: '', server: '');
}

/// LeanCloud REST API 客户端（只用 http 包，不依赖第三方 SDK）。
class LCClient {
  final LCConfig config;
  LCClient(this.config);

  Map<String, String> get _headers => {
        'X-LC-Id': config.appId,
        'X-LC-Key': config.appKey,
        'Content-Type': 'application/json',
      };

  String get _base => config.server.replaceAll(RegExp(r'/$'), '');

  Future<List<Map<String, dynamic>>> query(
    String className, {
    Map<String, dynamic>? where,
    String? order,
    int limit = 100,
  }) async {
    final params = <String, String>{'limit': '$limit'};
    if (where != null) params['where'] = jsonEncode(where);
    if (order != null) params['order'] = order;
    final uri =
        Uri.parse('$_base/1.1/classes/$className').replace(queryParameters: params);
    final resp =
        await http.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw Exception('查询失败 ${resp.statusCode}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return (data['results'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> create(
      String className, Map<String, dynamic> fields) async {
    final uri = Uri.parse('$_base/1.1/classes/$className');
    final resp = await http
        .post(uri, headers: _headers, body: jsonEncode(fields))
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 201) {
      throw Exception('保存失败 ${resp.statusCode}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<void> update(
      String className, String objectId, Map<String, dynamic> fields) async {
    final uri = Uri.parse('$_base/1.1/classes/$className/$objectId');
    final resp = await http
        .put(uri, headers: _headers, body: jsonEncode(fields))
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw Exception('更新失败 ${resp.statusCode}');
    }
  }

  Future<void> delete(String className, String objectId) async {
    final uri = Uri.parse('$_base/1.1/classes/$className/$objectId');
    final resp = await http
        .delete(uri, headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw Exception('删除失败 ${resp.statusCode}');
    }
  }
}
