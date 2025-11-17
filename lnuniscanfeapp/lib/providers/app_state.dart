import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../services/enhanced_scan_service.dart';
import '../models/scan_item.dart';

class AppState extends ChangeNotifier {
  final ApiService _api = ApiService();
  final StorageService _storage = StorageService();
  final EnhancedScanService _scan = EnhancedScanService();

  String? _eqid;
  String _alias = 'SCANNER';
  String get alias => _alias;
  String? get eqid => _eqid;

  // device id -> enabled
  final Map<String, bool> _deviceEnabled = {};
  List<String> get enabledDeviceIds =>
      _deviceEnabled.entries.where((e) => e.value).map((e) => e.key).toList();
  Map<String, bool> get deviceEnabled => Map.unmodifiable(_deviceEnabled);
  List<Map<String, dynamic>> _deviceList = [];
  List<Map<String, dynamic>> get deviceList => List.unmodifiable(_deviceList);

  StreamSubscription<IScanItem>? _scanSub;

  Future<void> initialize() async {
    await _api.loadBaseUrl();
    final state = await _storage.readState();
    final savedEqid = state['eqid'];
    final savedAlias = state['alias'];
    if (savedEqid is String && savedEqid.trim().isNotEmpty) {
      _eqid = savedEqid.trim();
      _alias = (savedAlias is String && savedAlias.trim().isNotEmpty) ? savedAlias.trim() : 'SCANNER';
      notifyListeners();
      _listenScans();
      return;
    }
    // request init
    final res = await _api.initApp();
    if (res != null) {
      _eqid = res['eqid'] as String?;
      _alias = (res['alias'] as String?) ?? 'SCANNER';
      await _storage.updateState({'eqid': _eqid, 'alias': _alias});
      notifyListeners();
      _listenScans();
    }
  }

  void _listenScans() {
    _scanSub ??= _scan.scanStream.listen((item) async {
      if (item is BarcodeScanItem && _eqid != null) {
        // mark uploading while sending
        _scan.updateItemStatus(item.id, ScanStatus.uploading, progress: 0.1);
        notifyListeners();
        final ok = await _api.sendScan(
          data: item.barcodeData,
          eqid: _eqid!,
          deviceIds: enabledDeviceIds,
        );
        _scan.updateItemStatus(
          item.id,
          ok ? ScanStatus.completed : ScanStatus.failed,
          progress: ok ? 1.0 : 0.0,
        );
        notifyListeners();
      }
    });
  }

  Future<void> updateAlias(String alias) async {
    if (_eqid == null) return;
    final next = alias.trim().isEmpty ? 'SCANNER' : alias.trim();
    final res = await _api.updateAlias(_eqid!, next);
    if (res != null) {
      _alias = res['alias'] as String? ?? next;
      await _storage.updateState({'alias': _alias});
      notifyListeners();
    }
  }

  Future<void> refreshDevices() async {
    if (_eqid == null) return;
    final list = await _api.listDevices(_eqid!);
    // enable state default: keep existing or default true
    for (final d in list) {
      final id = d['id'] as String? ?? '';
      if (id.isEmpty) continue;
      _deviceEnabled[id] = _deviceEnabled[id] ?? true;
    }
    // remove stale
    final ids = list.map((e) => e['id'] as String? ?? '').where((e) => e.isNotEmpty).toSet();
    _deviceEnabled.removeWhere((k, v) => !ids.contains(k));
    _deviceList = list;
    notifyListeners();
  }

  void setDeviceEnabled(String deviceId, bool enabled) {
    _deviceEnabled[deviceId] = enabled;
    notifyListeners();
  }

  Future<void> unbindDevice(String deviceId) async {
    if (_eqid == null) return;
    final ok = await _api.unbindDevice(deviceId, _eqid!);
    if (ok) {
      _deviceEnabled.remove(deviceId);
      notifyListeners();
    }
  }

  Future<void> setApiBaseUrl(String url) async {
    await _api.setBaseUrl(url);
    notifyListeners();
  }

  String get apiBaseUrl => _api.baseUrl;

  @override
  void dispose() {
    _scanSub?.cancel();
    super.dispose();
  }
}


