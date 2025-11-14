import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  WebSocketChannel? _channel;
  StreamController<Map<String, dynamic>>? _messageController;
  String? _serverUrl;
  bool _isConnected = false;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  int _reconnectAttempts = 0;
  static const int maxReconnectAttempts = 5;
  static const Duration reconnectDelay = Duration(seconds: 3);
  static const Duration heartbeatInterval = Duration(seconds: 30);

  // getters
  bool get isConnected => _isConnected;
  Stream<Map<String, dynamic>>? get messageStream => _messageController?.stream;

  // connect to websocket server
  Future<bool> connect(String url) async {
    try {
      _serverUrl = url;
      _messageController ??= StreamController<Map<String, dynamic>>.broadcast();
      
      _channel = WebSocketChannel.connect(Uri.parse(url));
      
      // listen to messages
      _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDisconnected,
      );

      _isConnected = true;
      _reconnectAttempts = 0;
      _startHeartbeat();
      
      print('websocket connected to: $url');
      return true;
    } catch (e) {
      print('websocket connection failed: $e');
      _isConnected = false;
      _scheduleReconnect();
      return false;
    }
  }

  // send message
  void send(Map<String, dynamic> message) {
    if (_isConnected && _channel != null) {
      try {
        final jsonMessage = jsonEncode(message);
        _channel!.sink.add(jsonMessage);
        print('sent message: $jsonMessage');
      } catch (e) {
        print('failed to send message: $e');
      }
    } else {
      print('websocket not connected, cannot send message');
    }
  }

  // send raw string
  void sendRaw(String message) {
    if (_isConnected && _channel != null) {
      try {
        _channel!.sink.add(message);
        print('sent raw message: $message');
      } catch (e) {
        print('failed to send raw message: $e');
      }
    } else {
      print('websocket not connected, cannot send raw message');
    }
  }

  // disconnect
  void disconnect() {
    _isConnected = false;
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _channel?.sink.close(status.goingAway);
    _channel = null;
    print('websocket disconnected');
  }

  // handle incoming messages
  void _onMessage(dynamic message) {
    try {
      final Map<String, dynamic> data = jsonDecode(message);
      _messageController?.add(data);
      print('received message: $data');
    } catch (e) {
      // if not json, treat as raw message
      _messageController?.add({'raw': message.toString()});
      print('received raw message: $message');
    }
  }

  // handle errors
  void _onError(error) {
    print('websocket error: $error');
    _isConnected = false;
    _scheduleReconnect();
  }

  // handle disconnection
  void _onDisconnected() {
    print('websocket disconnected');
    _isConnected = false;
    _heartbeatTimer?.cancel();
    _scheduleReconnect();
  }

  // schedule reconnection
  void _scheduleReconnect() {
    if (_reconnectAttempts < maxReconnectAttempts && _serverUrl != null) {
      _reconnectAttempts++;
      print('scheduling reconnect attempt $_reconnectAttempts in ${reconnectDelay.inSeconds}s');
      
      _reconnectTimer = Timer(reconnectDelay, () {
        connect(_serverUrl!);
      });
    } else {
      print('max reconnect attempts reached or no server url');
    }
  }

  // start heartbeat
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (timer) {
      if (_isConnected) {
        send({'type': 'ping', 'timestamp': DateTime.now().millisecondsSinceEpoch});
      } else {
        timer.cancel();
      }
    });
  }

  // dispose
  void dispose() {
    disconnect();
    _messageController?.close();
    _messageController = null;
  }
}
