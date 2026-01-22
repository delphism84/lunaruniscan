import 'dart:convert';
import 'package:http/http.dart' as http;
import 'storage_service.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  // 기본 BE 호스트(로컬/사내망 개발용)
  String _baseUrl = 'http://192.168.1.251:50100';

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
    try {
      final resp = await http.post(
        _u('/api/app/init'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'eqid': eqid}),
      ).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      } else {
        print('initApp failed: ${resp.statusCode} ${resp.body}');
      }
    } catch (e) {
      print('initApp error: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> updateAlias(String eqid, String alias) async {
    try {
      final resp = await http.patch(
        _u('/api/app/alias'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'eqid': eqid, 'alias': alias}),
      ).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      } else {
        print('updateAlias failed: ${resp.statusCode} ${resp.body}');
      }
    } catch (e) {
      print('updateAlias error: $e');
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> listDevices(String eqid) async {
    try {
      final resp = await http.get(_u('/api/app/devices', {'eqid': eqid})).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data is List) {
          return data.cast<Map<String, dynamic>>();
        }
      } else {
        print('listDevices failed: ${resp.statusCode} ${resp.body}');
      }
    } catch (e) {
      print('listDevices error: $e');
    }
    return [];
  }

  Future<bool> unbindDevice(String deviceId, String eqid) async {
    try {
      final resp = await http.delete(_u('/api/agents/$deviceId/owner', {'eqid': eqid})).timeout(const Duration(seconds: 6));
      final ok = resp.statusCode == 200;
      if (!ok) print('unbindDevice failed: ${resp.statusCode} ${resp.body}');
      return ok;
    } catch (e) {
      print('unbindDevice error: $e');
      return false;
    }
  }

  Future<bool> sendScan({
    required String data,
    required String eqid,
    List<String>? deviceIds,
  }) async {
    try {
      final resp = await http.post(
        _u('/api/scanner/scan'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'data': data,
          'eqid': eqid,
          if (deviceIds != null && deviceIds.isNotEmpty) 'deviceIds': deviceIds,
        }),
      ).timeout(const Duration(seconds: 6));
      final ok = resp.statusCode == 200;
      if (!ok) print('sendScan failed: ${resp.statusCode} ${resp.body}');
      return ok;
    } catch (e) {
      print('sendScan error: $e');
      return false;
    }
  }
}


