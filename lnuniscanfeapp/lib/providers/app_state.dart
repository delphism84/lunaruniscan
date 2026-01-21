import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../services/enhanced_scan_service.dart';
import '../models/scan_item.dart';
import '../services/local_store_service.dart';
import '../services/upload_queue_service.dart';

class AppState extends ChangeNotifier {
  final ApiService _api = ApiService();
  final StorageService _storage = StorageService();
  final EnhancedScanService _scan = EnhancedScanService();
  final LocalStoreService _local = LocalStoreService();
  final UploadQueueService _uploader = UploadQueueService();

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
      // 앱 시작 시 보류분 재시도
      _resendPendingInBackground();
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
      // 앱 시작 시 보류분 재시도
      _resendPendingInBackground();
    }
  }

  void _listenScans() {
    _scanSub ??= _scan.scanStream.listen((item) async {
      if (item is BarcodeScanItem && _eqid != null) {
        _scan.updateItemStatus(item.id, ScanStatus.uploading, progress: 0.1);
        notifyListeners();

        // 로컬 저장 비동기 처리
        () async {
          try {
            await _local.appendScan(item);
          } catch (_) {}
        }();

        // 서버 업로드: 큐에 위임(동시성 제한 + 재시도)
        _uploader.enqueue(() async {
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
          return ok;
        }, id: item.id, maxRetries: 3, onFinal: (id, finalOk) async {
          if (!finalOk && id != null) {
            // 최종 실패: 보류 큐에 기록
            try {
              await _local.addPending({
                'id': id,
                'kind': 'sendScan',
                'payload': {
                  'barcodeData': item.barcodeData,
                },
                'createdAt': DateTime.now().toIso8601String(),
              });
            } catch (_) {}
          }
        });
      }
    });
  }

  // 수동 동기화 버튼에서 호출
  Future<void> manualSync() async {
    await _resendPendingInBackground();
  }

  Future<void> _resendPendingInBackground() async {
    // 보류 목록을 읽어 재업로드 큐에 위임
    try {
      final pending = await _local.readPending();
      if (pending.isEmpty || _eqid == null) return;

      final successIds = <String>{};
      for (final p in pending) {
        final id = p['id'] as String?;
        final kind = p['kind'] as String?;
        final payload = p['payload'] as Map<String, dynamic>?;
        if (id == null || kind != 'sendScan' || payload == null) continue;
        final code = payload['barcodeData'] as String?;
        if (code == null || code.isEmpty) continue;

        _uploader.enqueue(() async {
          final ok = await _api.sendScan(
            data: code,
            eqid: _eqid!,
            deviceIds: enabledDeviceIds,
          );
          return ok;
        }, id: id, maxRetries: 3, onFinal: (finalId, finalOk) async {
          if (finalOk && finalId != null) {
            successIds.add(finalId);
          }
        });
      }

      // 큐 완료 후 제거: 간단히 지연 후 삭제 (최대 동시 2, 재시도 포함 여유 대기)
      Future.delayed(const Duration(seconds: 8), () async {
        if (successIds.isNotEmpty) {
          await _local.removePendingByIds(successIds);
        }
      });
    } catch (_) {}
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


