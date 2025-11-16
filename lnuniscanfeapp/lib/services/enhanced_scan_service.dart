import 'dart:async';
import 'dart:math';
import '../models/scan_item.dart';

class EnhancedScanService {
  static final EnhancedScanService _instance = EnhancedScanService._internal();
  factory EnhancedScanService() => _instance;
  EnhancedScanService._internal();

  final StreamController<IScanItem> _scanController = StreamController<IScanItem>.broadcast();
  Stream<IScanItem> get scanStream => _scanController.stream;

  final List<IScanItem> _scanItems = [];
  List<IScanItem> get scanItems => List.unmodifiable(_scanItems);

  // duplicate filter settings
  int duplicateFilterSeconds = 5; // default 5 seconds
  final Map<String, DateTime> _lastScanTimes = {}; // barcode -> last scan time


  // public: enqueue barcode directly (used by lightweight ScanService)
  // returns true if accepted (not filtered as duplicate)
  bool addBarcode(String code, {String type = 'unknown'}) {
    final now = DateTime.now();
    if (_isDuplicateBarcode(code, now)) {
      print('duplicate barcode ignored: $code (within ${duplicateFilterSeconds}s)');
      return false;
    }
    _lastScanTimes[code] = now;

    final scanItem = BarcodeScanItem(
      id: _generateId(),
      timestamp: now,
      barcodeData: code,
      barcodeType: type,
    );
    _addScanItem(scanItem);
    print('barcode enqueued: ${scanItem.barcodeData}');
    return true;
  }

  // public: force enqueue barcode (manual mode bypass duplicate filter)
  bool addBarcodeForce(String code, {String type = 'unknown'}) {
    final now = DateTime.now();
    _lastScanTimes[code] = now; // refresh last seen

    final scanItem = BarcodeScanItem(
      id: _generateId(),
      timestamp: now,
      barcodeData: code,
      barcodeType: type,
    );
    _addScanItem(scanItem);
    print('barcode enqueued (forced): ${scanItem.barcodeData}');
    return true;
  }

  // no-op file I/O: images are handled as placeholders only

  // public: enqueue image placeholder (no actual file i/o)
  void addImagePlaceholder({String? fileName}) {
    final now = DateTime.now();
    final name = fileName ?? 'scan_${now.millisecondsSinceEpoch}.jpg';
    final scanItem = ImageScanItem(
      id: _generateId(),
      timestamp: now,
      fileName: name,
      filePath: null,
      thumbnailPath: null,
    );
    _addScanItem(scanItem);
    print('image placeholder enqueued: $name');
  }

  // add scan item to list and cache
  void _addScanItem(IScanItem item) {
    _scanItems.add(item);
    _scanController.add(item);
  }

  // processing simulation & file cleanup removed (not used in current UI)

  // get items by status
  List<IScanItem> getItemsByStatus(ScanStatus status) {
    return _scanItems.where((item) => item.status == status).toList();
  }

  // get items count by status
  int getItemsCountByStatus(ScanStatus status) {
    return _scanItems.where((item) => item.status == status).length;
  }

  // get progress summary
  Map<String, int> getProgressSummary() {
    final summary = <String, int>{};
    for (final status in ScanStatus.values) {
      summary[status.name] = getItemsCountByStatus(status);
    }
    return summary;
  }

  // update item status manually
  void updateItemStatus(String itemId, ScanStatus status, {double? progress}) {
    final itemIndex = _scanItems.indexWhere((item) => item.id == itemId);
    if (itemIndex != -1) {
      _scanItems[itemIndex].updateStatus(status, progress: progress);
      _scanController.add(_scanItems[itemIndex]);
    }
  }

  // clear all cache
  Future<void> clearAllCache() async {
    _scanItems.clear();
    _scanController.addStream(Stream<IScanItem>.empty());
  }

  // check if barcode is duplicate within filter time
  bool _isDuplicateBarcode(String barcodeData, DateTime currentTime) {
    final lastScanTime = _lastScanTimes[barcodeData];
    if (lastScanTime == null) {
      return false; // first time scanning this barcode
    }
    
    final timeDifference = currentTime.difference(lastScanTime);
    return timeDifference.inSeconds < duplicateFilterSeconds;
  }

  // set duplicate filter time in seconds
  void setDuplicateFilterSeconds(int seconds) {
    duplicateFilterSeconds = seconds;
    print('duplicate filter time set to ${seconds}s');
  }

  // get current duplicate filter time
  int getDuplicateFilterSeconds() {
    return duplicateFilterSeconds;
  }

  // clear duplicate filter cache (for testing or reset)
  void clearDuplicateFilterCache() {
    _lastScanTimes.clear();
    print('duplicate filter cache cleared');
  }

  // get duplicate filter statistics
  Map<String, dynamic> getDuplicateFilterStats() {
    return {
      'filterSeconds': duplicateFilterSeconds,
      'trackedBarcodes': _lastScanTimes.length,
      'lastScanTimes': Map.from(_lastScanTimes.map((key, value) => 
        MapEntry(key, value.toIso8601String()))),
    };
  }

  // removed periodic cleanup; map stays small in current usage

  // generate unique id
  String _generateId() {
    return '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
  }

  void dispose() {
    _scanController.close();
  }
}
