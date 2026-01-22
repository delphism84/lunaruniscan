import 'dart:async';

import 'websocket_service.dart';

class WsRequestException implements Exception {
  final String code;
  final String message;
  WsRequestException(this.code, this.message);

  @override
  String toString() => 'WsRequestException($code): $message';
}

/// Thin request/response helper over `WebSocketService`.
///
/// be-ws expects:
/// - `type`: message type (e.g. appInit, pairRequest, scanBarcode)
/// - `requestId`: client-generated id for matching
/// - `clientType`: "app" | "pcAgent"
/// - `timestamp`: ISO string
/// - `data`: payload
class WsApiClient {
  final WebSocketService _ws = WebSocketService();

  StreamSubscription<Map<String, dynamic>>? _sub;
  final Map<String, Completer<Map<String, dynamic>>> _pending = {};
  int _seq = 0;

  bool get isConnected => _ws.isConnected;
  Stream<Map<String, dynamic>>? get messageStream => _ws.messageStream;

  Future<bool> connect(String url) async {
    final ok = await _ws.connect(url);
    _sub ??= _ws.messageStream?.listen(_onMessage);
    return ok;
  }

  void disconnect() {
    _ws.disconnect();
  }

  String _nextRequestId() {
    _seq++;
    return 'r${DateTime.now().millisecondsSinceEpoch}_$_seq';
  }

  void _onMessage(Map<String, dynamic> msg) {
    if (msg['type'] != 'response') return;
    final requestId = msg['requestId'];
    if (requestId is! String || requestId.isEmpty) return;

    final c = _pending.remove(requestId);
    c?.complete(msg);
  }

  Future<Map<String, dynamic>> request(
    String type, {
    Map<String, dynamic>? data,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final requestId = _nextRequestId();
    final completer = Completer<Map<String, dynamic>>();
    _pending[requestId] = completer;

    _ws.send({
      'type': type,
      'requestId': requestId,
      'clientType': 'app',
      'timestamp': DateTime.now().toIso8601String(),
      if (data != null) 'data': data,
    });

    Map<String, dynamic> resp;
    try {
      resp = await completer.future.timeout(timeout);
    } on TimeoutException {
      _pending.remove(requestId);
      throw WsRequestException('TIMEOUT', '$type timeout');
    }

    final ok = resp['ok'] == true;
    if (!ok) {
      final err = resp['error'];
      if (err is Map) {
        throw WsRequestException(
          (err['code']?.toString() ?? 'ERR'),
          (err['message']?.toString() ?? 'unknown'),
        );
      }
      throw WsRequestException('ERR', 'unknown');
    }

    final respData = resp['data'];
    if (respData is Map<String, dynamic>) return respData;
    if (respData is Map) return respData.cast<String, dynamic>();
    return <String, dynamic>{};
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    for (final c in _pending.values) {
      if (!c.isCompleted) {
        c.completeError(WsRequestException('CANCELLED', 'disposed'));
      }
    }
    _pending.clear();
  }
}

