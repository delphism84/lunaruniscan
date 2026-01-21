import 'dart:async';
import 'dart:math';

typedef UploadTask = Future<bool> Function();

class UploadQueueService {
  static final UploadQueueService _instance = UploadQueueService._internal();
  factory UploadQueueService() => _instance;
  UploadQueueService._internal();

  final int _maxConcurrent = 2;
  int _active = 0;
  final List<_QueuedTask> _queue = <_QueuedTask>[];

  Future<void> enqueue(
    UploadTask task, {
    String? id,
    int maxRetries = 3,
    void Function(String? id, bool finalOk)? onFinal,
  }) async {
    final completer = Completer<void>();
    _queue.add(_QueuedTask(
      task: task,
      id: id,
      maxRetries: maxRetries,
      onDone: completer.complete,
      onFinal: onFinal,
    ));
    _drain();
    return completer.future;
  }

  void _drain() {
    while (_active < _maxConcurrent && _queue.isNotEmpty) {
      final next = _queue.removeAt(0);
      _run(next);
    }
  }

  Future<void> _run(_QueuedTask q) async {
    _active++;
    try {
      int attempt = 0;
      bool finalOk = false;
      while (true) {
        final ok = await q.task();
        if (ok) {
          finalOk = true;
          break;
        }
        attempt++;
        if (attempt > q.maxRetries) break;
        final delayMs = min(500 * pow(2, attempt).toInt(), 5000);
        await Future.delayed(Duration(milliseconds: delayMs));
      }
      if (q.onFinal != null) {
        q.onFinal!(q.id, finalOk);
      }
    } catch (_) {
      // swallow: best-effort queue
    } finally {
      _active--;
      q.onDone();
      _drain();
    }
  }
}

class _QueuedTask {
  final UploadTask task;
  final String? id;
  final int maxRetries;
  final void Function() onDone;
  final void Function(String? id, bool finalOk)? onFinal;
  _QueuedTask({
    required this.task,
    required this.onDone,
    this.id,
    this.maxRetries = 3,
    this.onFinal,
  });
}


