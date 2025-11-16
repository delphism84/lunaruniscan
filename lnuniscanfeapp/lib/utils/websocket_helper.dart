import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../providers/websocket_provider.dart';

class WebSocketHelper {
  // global send function - can be called from anywhere
  static void send(BuildContext context, Map<String, dynamic> message) {
    final wsProvider = Provider.of<WebSocketProvider>(context, listen: false);
    wsProvider.send(message);
  }

  // global send raw function
  static void sendRaw(BuildContext context, String message) {
    final wsProvider = Provider.of<WebSocketProvider>(context, listen: false);
    wsProvider.sendRaw(message);
  }

  // global connect function
  static Future<bool> connect(BuildContext context, String url) async {
    final wsProvider = Provider.of<WebSocketProvider>(context, listen: false);
    return await wsProvider.connect(url);
  }

  // global disconnect function
  static void disconnect(BuildContext context) {
    final wsProvider = Provider.of<WebSocketProvider>(context, listen: false);
    wsProvider.disconnect();
  }

  // check connection status
  static bool isConnected(BuildContext context) {
    final wsProvider = Provider.of<WebSocketProvider>(context, listen: false);
    return wsProvider.isConnected;
  }

  // listen to messages - use this in your widgets
  static Stream<Map<String, dynamic>>? getMessageStream(BuildContext context) {
    final wsProvider = Provider.of<WebSocketProvider>(context, listen: false);
    return wsProvider.messageStream;
  }

  // example usage in a widget:
  /*
  void _setupWebSocketListener() {
    final messageStream = WebSocketHelper.getMessageStream(context);
    messageStream?.listen((message) {
      print('received message: $message');
      
      // handle different message types
      switch (message['type']) {
        case 'login_response':
          _handleLoginResponse(message);
          break;
        case 'notification':
          _handleNotification(message);
          break;
        case 'pong':
          print('heartbeat pong received');
          break;
        default:
          print('unknown message type: ${message['type']}');
      }
    });
  }

  void _sendMessage() {
    WebSocketHelper.send(context, {
      'type': 'chat',
      'message': 'hello world',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }
  */
}
