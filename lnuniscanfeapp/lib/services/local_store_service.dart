import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/scan_item.dart';

class LocalStoreService {
  static final LocalStoreService _instance = LocalStoreService._internal();
  factory LocalStoreService() => _instance;
  LocalStoreService._internal();

  Future<File> _getLogFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/scan_log.jsonl');
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    return file;
  }

  Future<void> appendScan(IScanItem item) async {
    final file = await _getLogFile();
    final line = jsonEncode(item.toJson());
    await file.writeAsString('$line\n', mode: FileMode.append, flush: false);
  }

  // pending uploads (jsonl: one json per line)
  Future<File> _getPendingFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/pending_uploads.jsonl');
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    return file;
  }

  Future<void> addPending(Map<String, dynamic> record) async {
    final file = await _getPendingFile();
    await file.writeAsString('${jsonEncode(record)}\n', mode: FileMode.append, flush: false);
  }

  Future<List<Map<String, dynamic>>> readPending() async {
    final file = await _getPendingFile();
    final lines = await file.readAsLines();
    final list = <Map<String, dynamic>>[];
    for (final l in lines) {
      if (l.trim().isEmpty) continue;
      try {
        final obj = jsonDecode(l);
        if (obj is Map<String, dynamic>) list.add(obj);
      } catch (_) {}
    }
    return list;
  }

  Future<void> removePendingByIds(Set<String> ids) async {
    final file = await _getPendingFile();
    final lines = await file.readAsLines();
    final kept = <String>[];
    for (final l in lines) {
      if (l.trim().isEmpty) continue;
      try {
        final obj = jsonDecode(l);
        if (obj is Map && ids.contains(obj['id'])) {
          // drop
        } else {
          kept.add(l);
        }
      } catch (_) {
        kept.add(l);
      }
    }
    await file.writeAsString(kept.join('\n') + (kept.isNotEmpty ? '\n' : ''), mode: FileMode.write, flush: true);
  }
}


