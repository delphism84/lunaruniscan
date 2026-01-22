import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/storage_service.dart';
import '../services/enhanced_scan_service.dart';
import '../models/scan_item.dart';
import '../services/local_store_service.dart';
import '../services/upload_queue_service.dart';
import '../services/ws_api_client.dart';

class AppState extends ChangeNotifier {
  final StorageService _storage = StorageService();
  final EnhancedScanService _scan = EnhancedScanService();
  final LocalStoreService _local = LocalStoreService();
  final UploadQueueService _uploader = UploadQueueService();
  final WsApiClient _wsApi = WsApiClient();

  String? _eqid;
  String _alias = 'SCANNER';
  String get alias => _alias;
  String? get eqid => _eqid;

  static const String _defaultWsUrl = 'ws://192.168.1.250:45444/ws/sendReq';
  String _wsUrl = _defaultWsUrl;
  String get wsUrl => _wsUrl;
  bool get isWsConnected => _wsApi.isConnected;

  // device id -> enabled
  final Map<String, bool> _deviceEnabled = {};
  List<String> get enabledDeviceIds =>
      _deviceEnabled.entries.where((e) => e.value).map((e) => e.key).toList();
  Map<String, bool> get deviceEnabled => Map.unmodifiable(_deviceEnabled);
  List<Map<String, dynamic>> _deviceList = [];
  List<Map<String, dynamic>> get deviceList => List.unmodifiable(_deviceList);

  StreamSubscription<IScanItem>? _scanSub;
  StreamSubscription<Map<String, dynamic>>? _wsSub;

  // ws jobId -> scan item id
  final Map<String, String> _jobToItemId = {};

  Future<bool> _connectAndInit(String url) async {
    await _wsApi.connect(url);
    _wsSub ??= _wsApi.messageStream?.listen(_onWsMessage);

    // verify by calling appInit (be-ws always responds)
    final data = await _wsApi.request('appInit', data: {'eqid': _eqid});
    final nextEqid = data['eqid'] as String?;
    final nextAlias = data['alias'] as String?;
    if (nextEqid != null && nextEqid.trim().isNotEmpty) {
      _eqid = nextEqid.trim();
    }
    if (nextAlias != null && nextAlias.trim().isNotEmpty) {
      _alias = nextAlias.trim();
    }
    return true;
  }

  Future<void> initialize() async {
    final state = await _storage.readState();
    final savedWsUrl = state['wsUrl'];
    if (savedWsUrl is String && savedWsUrl.trim().isNotEmpty) {
      _wsUrl = savedWsUrl.trim();
    }
    final savedEqid = state['eqid'];
    final savedAlias = state['alias'];
    if (savedEqid is String && savedEqid.trim().isNotEmpty) {
      _eqid = savedEqid.trim();
      _alias = (savedAlias is String && savedAlias.trim().isNotEmpty) ? savedAlias.trim() : 'SCANNER';
    }

    // connect ws + appInit (retry once with default url when saved url is stale)
    var activeUrl = _wsUrl;
    try {
      await _connectAndInit(activeUrl);
    } catch (_) {
      if (activeUrl != _defaultWsUrl) {
        try {
          activeUrl = _defaultWsUrl;
          await _connectAndInit(activeUrl);
        } catch (_) {
          // allow offline init (UI still works; scans will fail to dispatch)
        }
      }
    }

    _wsUrl = activeUrl;
    await _storage.updateState({'eqid': _eqid, 'alias': _alias, 'wsUrl': _wsUrl});

    notifyListeners();
    _listenScans();
    // 앱 시작 시 보류분 재시도
    _resendPendingInBackground();
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

        // 서버 전송(WS): 큐에 위임(동시성 제한 + 재시도)
        _uploader.enqueue(() async {
          try {
            final resp = await _wsApi.request('scanBarcode', data: {
              'eqid': _eqid!,
              'barcode': item.barcodeData,
            });
            final jobId = resp['jobId']?.toString();
            if (jobId != null && jobId.isNotEmpty) {
              _jobToItemId[jobId] = item.id;
            }
            // 최종 성공/실패는 scanJobUpdate 이벤트로 반영됨
            return true;
          } catch (_) {
            return false;
          }
        }, id: item.id, maxRetries: 3, onFinal: (id, finalOk) async {
          if (!finalOk && id != null) {
            // 최종 실패: 보류 큐에 기록
            try {
              await _local.addPending({
                'id': id,
                'kind': 'scanBarcode',
                'payload': {
                  'barcodeData': item.barcodeData,
                },
                'createdAt': DateTime.now().toIso8601String(),
              });
            } catch (_) {}
            _scan.updateItemStatus(item.id, ScanStatus.failed, progress: 0.0);
            notifyListeners();
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
        if (id == null || payload == null) continue;
        if (kind != 'sendScan' && kind != 'scanBarcode') continue;
        final code = payload['barcodeData'] as String?;
        if (code == null || code.isEmpty) continue;

        _uploader.enqueue(() async {
          try {
            await _wsApi.request('scanBarcode', data: {
              'eqid': _eqid!,
              'barcode': code,
            });
            return true;
          } catch (_) {
            return false;
          }
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
    final next = alias.trim().isEmpty ? 'SCANNER' : alias.trim();
    _alias = next;
    await _storage.updateState({'alias': _alias});
    notifyListeners();
  }

  Future<void> refreshDevices() async {
    if (_eqid == null) return;
    try {
      final resp = await _wsApi.request('pairList', data: {'eqid': _eqid});
      final list = (resp['list'] as List?) ?? const [];
      final rows = <Map<String, dynamic>>[];

      for (final x in list) {
        if (x is! Map) continue;
        final pcId = x['pcId']?.toString() ?? '';
        if (pcId.isEmpty) continue;
        final enabled = x['enabled'] == true;
        final online = x['online'] == true;

        _deviceEnabled[pcId] = enabled;
        rows.add({
          'id': pcId,
          'name': pcId,
          'status': online ? 'online' : 'offline',
          'type': 'PC',
        });
      }

      // remove stale enabled toggles
      final ids = rows.map((e) => e['id'] as String).toSet();
      _deviceEnabled.removeWhere((k, v) => !ids.contains(k));
      _deviceList = rows;
      notifyListeners();
    } catch (_) {
      // ignore: keep existing list
    }
  }

  Future<void> setDeviceEnabled(String deviceId, bool enabled) async {
    if (_eqid == null) return;
    _deviceEnabled[deviceId] = enabled;
    notifyListeners();
    try {
      await _wsApi.request('pairSetEnabled', data: {
        'eqid': _eqid,
        'pcId': deviceId,
        'enabled': enabled,
      });
    } catch (_) {
      // rollback on failure
      _deviceEnabled[deviceId] = !enabled;
      notifyListeners();
    }
  }

  Future<void> unbindDevice(String deviceId) async {
    // be-ws has no "remove pairing" yet; treat unbind as disable.
    await setDeviceEnabled(deviceId, false);
  }

  Future<void> setWsUrl(String url) async {
    final next = url.trim();
    if (next.isEmpty) return;
    _wsUrl = next;
    await _storage.updateState({'wsUrl': _wsUrl});
    // reconnect + re-init
    await _wsApi.connect(_wsUrl);
    try {
      final data = await _wsApi.request('appInit', data: {'eqid': _eqid});
      _eqid = (data['eqid'] as String?) ?? _eqid;
      final alias = (data['alias'] as String?);
      if (alias != null && alias.trim().isNotEmpty) _alias = alias.trim();
      await _storage.updateState({'eqid': _eqid, 'alias': _alias, 'wsUrl': _wsUrl});
    } catch (_) {}
    notifyListeners();
  }

  Future<void> pairWithCode(String code) async {
    if (_eqid == null) return;
    await _wsApi.request('pairRequest', data: {
      'eqid': _eqid,
      'code': code.trim(),
    });
    await refreshDevices();
  }

  void _onWsMessage(Map<String, dynamic> msg) {
    if (msg['type'] != 'event') return;
    final event = msg['event']?.toString();
    if (event == 'scanJobUpdate') {
      _applyScanJobUpdate(msg['data']);
    }
    if (event == 'paired') {
      // pairing added/changed; refresh device list opportunistically
      refreshDevices();
    }
  }

  void _applyScanJobUpdate(dynamic data) {
    if (data is! Map) return;
    final jobId = data['jobId']?.toString() ?? '';
    if (jobId.isEmpty) return;
    final itemId = _jobToItemId[jobId];
    if (itemId == null) return;

    final targets = (data['targets'] as List?) ?? const [];
    if (targets.isEmpty) {
      _scan.updateItemStatus(itemId, ScanStatus.completed, progress: 1.0);
      notifyListeners();
      return;
    }

    bool hasPending = false;
    bool anyFail = false;
    bool allOk = true;

    for (final t in targets) {
      if (t is! Map) continue;
      final status = t['status']?.toString() ?? '';
      if (status == 'pending' || status == 'sent') hasPending = true;
      if (status == 'ack_fail') anyFail = true;
      if (status != 'ack_ok') allOk = false;
    }

    if (hasPending) {
      _scan.updateItemStatus(itemId, ScanStatus.uploading, progress: 0.5);
    } else if (allOk) {
      _scan.updateItemStatus(itemId, ScanStatus.completed, progress: 1.0);
    } else if (anyFail) {
      _scan.updateItemStatus(itemId, ScanStatus.failed, progress: 0.0);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _wsSub?.cancel();
    _wsApi.dispose();
    super.dispose();
  }
}


