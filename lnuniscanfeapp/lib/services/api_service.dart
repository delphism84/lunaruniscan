import 'dart:convert';
import 'package:http/http.dart' as http;
import 'storage_service.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  String _baseUrl = 'https://server.uniscan.kr';

  String get baseUrl => _baseUrl;
  Future<void> setBaseUrl(String url) async {
    _baseUrl = url;
    await StorageService().updateState({'apiBaseUrl': _baseUrl});
  }

  Future<void> loadBaseUrl() async {
    final state = await StorageService().readState();
    final saved = state['apiBaseUrl'];
    if (saved is String && saved.trim().isNotEmpty) {
      _baseUrl = saved.trim();
    }
  }

  Uri _u(String path, [Map<String, String>? q]) =>
      Uri.parse('$_baseUrl$path').replace(queryParameters: q);

  Future<Map<String, dynamic>?> initApp({String? eqid}) async {
    final resp = await http.post(
      _u('/api/app/init'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'eqid': eqid}),
    );
    if (resp.statusCode == 200) {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }
    return null;
  }

  Future<Map<String, dynamic>?> updateAlias(String eqid, String alias) async {
    final resp = await http.patch(
      _u('/api/app/alias'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'eqid': eqid, 'alias': alias}),
    );
    if (resp.statusCode == 200) {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> listDevices(String eqid) async {
    final resp = await http.get(_u('/api/app/devices', {'eqid': eqid}));
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      if (data is List) {
        return data.cast<Map<String, dynamic>>();
      }
    }
    return [];
  }

  Future<bool> unbindDevice(String deviceId, String eqid) async {
    final resp = await http.delete(_u('/api/agents/$deviceId/owner', {'eqid': eqid}));
    return resp.statusCode == 200;
  }

  Future<bool> sendScan({
    required String data,
    required String eqid,
    List<String>? deviceIds,
  }) async {
    final resp = await http.post(
      _u('/api/scanner/scan'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'data': data,
        'eqid': eqid,
        if (deviceIds != null && deviceIds.isNotEmpty) 'deviceIds': deviceIds,
      }),
    );
    return resp.statusCode == 200;
  }
}


