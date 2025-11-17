import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  static const String _fileName = 'app_state.json';

  Future<File> _getStateFile() async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/$_fileName');
    if (!await file.exists()) {
      await file.create(recursive: true);
      await file.writeAsString(jsonEncode({}));
    }
    return file;
  }

  Future<Map<String, dynamic>> readState() async {
    try {
      final file = await _getStateFile();
      final raw = await file.readAsString();
      final data = jsonDecode(raw);
      if (data is Map<String, dynamic>) return data;
      return {};
    } catch (_) {
      return {};
    }
  }

  Future<void> writeState(Map<String, dynamic> state) async {
    try {
      final file = await _getStateFile();
      await file.writeAsString(jsonEncode(state));
    } catch (_) {
      // ignore
    }
  }

  Future<void> updateState(Map<String, dynamic> patch) async {
    final current = await readState();
    current.addAll(patch);
    await writeState(current);
  }
}


