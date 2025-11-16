import 'package:flutter/foundation.dart';
import '../services/websocket_service.dart';

class WebSocketProvider extends ChangeNotifier {
  final WebSocketService _webSocketService = WebSocketService();
  
  bool get isConnected => _webSocketService.isConnected;
  Stream<Map<String, dynamic>>? get messageStream => _webSocketService.messageStream;

  // connect to server
  Future<bool> connect(String url) async {
    final result = await _webSocketService.connect(url);
    notifyListeners();
    return result;
  }

  // send message
  void send(Map<String, dynamic> message) {
    _webSocketService.send(message);
  }

  // send raw string
  void sendRaw(String message) {
    _webSocketService.sendRaw(message);
  }

  // disconnect
  void disconnect() {
    _webSocketService.disconnect();
    notifyListeners();
  }

  @override
  void dispose() {
    _webSocketService.dispose();
    super.dispose();
  }
}
