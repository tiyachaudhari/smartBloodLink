import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/status.dart' as ws_status;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/api_config.dart';

/// Thin wrapper around the `/ws` realtime channel.
///
/// The server requires the first message to be `{"type":"auth","token":...}`
/// within 5 seconds. Reconnection and token refresh are the caller's job.
class VitalinkSocket {
  final void Function(Map<String, dynamic> event) onEvent;
  final void Function(String? error)? onClosed;

  VitalinkSocket({required this.onEvent, this.onClosed});

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  bool _closedByUs = false;
  bool _notified = false;

  bool get isOpen => _channel != null && !_closedByUs;

  Future<bool> connect(String token) async {
    await dispose();
    _closedByUs = false;
    _notified = false;

    final completer = Completer<bool>();
    try {
      final channel = WebSocketChannel.connect(Uri.parse(ApiConfig.wsUrl));
      _channel = channel;
      await channel.ready.timeout(const Duration(seconds: 8));
      channel.sink.add(jsonEncode({'type': 'auth', 'token': token}));

      _sub = channel.stream.listen(
        (data) {
          Map<String, dynamic>? msg;
          try {
            final decoded = jsonDecode(data.toString());
            if (decoded is Map) msg = decoded.cast<String, dynamic>();
          } catch (_) {}
          if (msg == null) return;
          if (msg['type'] == 'auth_ok') {
            if (!completer.isCompleted) completer.complete(true);
          } else if (msg['type'] != 'pong') {
            onEvent(msg);
          }
        },
        onError: (Object e) {
          if (!completer.isCompleted) completer.complete(false);
          _notifyClosed(e.toString());
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete(false);
          _notifyClosed(null);
        },
        cancelOnError: false,
      );
    } catch (e) {
      if (!completer.isCompleted) completer.complete(false);
      _notifyClosed(e.toString());
      return false;
    }

    return completer.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        _notifyClosed('auth timeout');
        dispose();
        return false;
      },
    );
  }

  void _notifyClosed(String? error) {
    if (_notified || _closedByUs) return;
    _notified = true;
    onClosed?.call(error);
  }

  Future<void> dispose() async {
    _closedByUs = true;
    final sub = _sub;
    _sub = null;
    try {
      await sub?.cancel();
    } catch (_) {}
    final channel = _channel;
    _channel = null;
    try {
      await channel?.sink.close(ws_status.normalClosure);
    } catch (_) {}
  }
}
