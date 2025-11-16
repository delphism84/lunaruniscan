import 'dart:io';

enum ScanType {
  barcode,
  image,
}

enum ScanStatus {
  cached,      // 캐싱됨
  uploading,   // 전송중
  processing,  // 처리중 (서버에서 분석중)
  completed,   // 완료
  failed,      // 실패
}

abstract class IScanItem {
  String get id;
  ScanType get type;
  DateTime get timestamp;
  ScanStatus get status;
  double get progress; // 0.0 ~ 1.0
  String get displayText;
  String? get thumbnailPath;
  String? get filePath;
  
  Map<String, dynamic> toJson();
  void updateStatus(ScanStatus status, {double? progress});
  void updateProgress(double progress);
}

class BarcodeScanItem implements IScanItem {
  @override
  final String id;
  
  @override
  final ScanType type = ScanType.barcode;
  
  @override
  final DateTime timestamp;
  
  @override
  ScanStatus status;
  
  @override
  double progress;
  
  final String barcodeData;
  final String barcodeType;
  
  @override
  String? thumbnailPath;
  
  @override
  String? filePath;

  BarcodeScanItem({
    required this.id,
    required this.timestamp,
    required this.barcodeData,
    required this.barcodeType,
    this.status = ScanStatus.cached,
    this.progress = 0.0,
    this.thumbnailPath,
    this.filePath,
  });

  @override
  String get displayText => barcodeData;

  @override
  void updateStatus(ScanStatus newStatus, {double? progress}) {
    status = newStatus;
    if (progress != null) {
      this.progress = progress;
    }
  }

  @override
  void updateProgress(double newProgress) {
    progress = newProgress.clamp(0.0, 1.0);
  }

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'barcode',
    'timestamp': timestamp.toIso8601String(),
    'status': status.name,
    'progress': progress,
    'barcodeData': barcodeData,
    'barcodeType': barcodeType,
    'thumbnailPath': thumbnailPath,
    'filePath': filePath,
  };

  factory BarcodeScanItem.fromJson(Map<String, dynamic> json) => BarcodeScanItem(
    id: json['id'],
    timestamp: DateTime.parse(json['timestamp']),
    barcodeData: json['barcodeData'],
    barcodeType: json['barcodeType'],
    status: ScanStatus.values.firstWhere((e) => e.name == json['status']),
    progress: json['progress']?.toDouble() ?? 0.0,
    thumbnailPath: json['thumbnailPath'],
    filePath: json['filePath'],
  );
}

class ImageScanItem implements IScanItem {
  @override
  final String id;
  
  @override
  final ScanType type = ScanType.image;
  
  @override
  final DateTime timestamp;
  
  @override
  ScanStatus status;
  
  @override
  double progress;
  
  @override
  final String? thumbnailPath;
  
  @override
  final String? filePath;
  
  final String fileName;

  ImageScanItem({
    required this.id,
    required this.timestamp,
    required this.fileName,
    this.status = ScanStatus.cached,
    this.progress = 0.0,
    this.thumbnailPath,
    this.filePath,
  });

  @override
  String get displayText => fileName;

  @override
  void updateStatus(ScanStatus newStatus, {double? progress}) {
    status = newStatus;
    if (progress != null) {
      this.progress = progress;
    }
  }

  @override
  void updateProgress(double newProgress) {
    progress = newProgress.clamp(0.0, 1.0);
  }

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'image',
    'timestamp': timestamp.toIso8601String(),
    'status': status.name,
    'progress': progress,
    'fileName': fileName,
    'thumbnailPath': thumbnailPath,
    'filePath': filePath,
  };

  factory ImageScanItem.fromJson(Map<String, dynamic> json) => ImageScanItem(
    id: json['id'],
    timestamp: DateTime.parse(json['timestamp']),
    fileName: json['fileName'],
    status: ScanStatus.values.firstWhere((e) => e.name == json['status']),
    progress: json['progress']?.toDouble() ?? 0.0,
    thumbnailPath: json['thumbnailPath'],
    filePath: json['filePath'],
  );
}
