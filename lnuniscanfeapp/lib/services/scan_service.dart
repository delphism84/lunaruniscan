import 'dart:async';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'enhanced_scan_service.dart';

enum ScanMode { barcode, camera }

// ScanService는 결과 감지 및 위임만 담당 (경량)

class ScanService {
  static final ScanService _instance = ScanService._internal();
  factory ScanService() => _instance;
  ScanService._internal();

  // 모드 상태
  ScanMode _currentMode = ScanMode.barcode;
  bool _isAutoMode = true;
  
  // 바코드 관련 (UI 갱신용 최소 정보)
  final StreamController<String> _barcodeController = StreamController<String>.broadcast();
  Stream<String> get barcodeStream => _barcodeController.stream;
  String _lastBarcodeResult = '';
  DateTime? _lastBarcodeTime;
  String? _pendingBarcodeData;
  
  // 카메라 관련 (UI 갱신용 최소 정보)
  final StreamController<String> _imageController = StreamController<String>.broadcast();
  Stream<String> get imageStream => _imageController.stream;
  String _lastImageResult = '';
  DateTime? _lastImageTime;

  // Getters
  ScanMode get currentMode => _currentMode;
  bool get isAutoMode => _isAutoMode;
  String get lastBarcodeResult => _lastBarcodeResult;
  DateTime? get lastBarcodeTime => _lastBarcodeTime;
  String get lastImageResult => _lastImageResult;
  DateTime? get lastImageTime => _lastImageTime;
  String? get pendingBarcodeData => _pendingBarcodeData;
  // 카운터는 ScanService에서 관리하지 않음 (UI에서 별도 표시)

  // 모드 제어
  void setMode(ScanMode mode) {
    _currentMode = mode;
    _pendingBarcodeData = null; // 모드 변경시 대기중인 바코드 클리어
  }

  void setAutoMode(bool isAuto) {
    _isAutoMode = isAuto;
    _pendingBarcodeData = null; // 자동모드 변경시 대기중인 바코드 클리어
  }

  // 바코드 감지 처리
  void onBarcodeDetected(BarcodeCapture capture) {
    // 바코드 모드가 아니면 무시
    if (_currentMode != ScanMode.barcode) return;
    
    for (final barcode in capture.barcodes) {
      if (barcode.rawValue != null && barcode.rawValue!.isNotEmpty) {
        final code = barcode.rawValue!;
        
        if (_isAutoMode) {
          // 자동 모드: 즉시 처리 시도 (중복 필터는 EnhancedScanService가 수행)
          _processBarcodeResult(code);
        } else {
          // 수동 모드: 대기 상태로 설정(필터는 처리 시점에 서비스가 수행)
          _pendingBarcodeData = code;
        }
      }
    }
  }

  // 수동 바코드 인식 처리
  void processManualBarcode() {
    if (_pendingBarcodeData == null) return; // 바코드 없으면 무시
    _processBarcodeResult(_pendingBarcodeData!, force: true); // 수동은 중복 무시
    _pendingBarcodeData = null;
  }

  // 바코드 결과 처리
  void _processBarcodeResult(String code, {bool force = false}) {
    final now = DateTime.now();
    final accepted = force
        ? EnhancedScanService().addBarcodeForce(code, type: 'unknown')
        : EnhancedScanService().addBarcode(code, type: 'unknown');
    if (!accepted) return; // 필터됨(자동 모드 케이스)

    _lastBarcodeResult = code;
    _lastBarcodeTime = now;
    _barcodeController.add(code);
    print('바코드 인식됨: $code');
  }

  // 이미지 촬영 처리
  void captureImage() {
    if (_currentMode != ScanMode.camera) return;
    
    final now = DateTime.now();
    final imageName = 'captured_${now.millisecondsSinceEpoch}.jpg';
    
    _lastImageResult = imageName;
    _lastImageTime = now;
    
    // 큐 위임 (EnhancedScanService) - 실제 파일 저장 없음(placeholder)
    EnhancedScanService().addImagePlaceholder(fileName: imageName);
    
    _imageController.add(imageName);
    print('이미지 촬영됨: $imageName');
  }

  void dispose() {
    _barcodeController.close();
    _imageController.close();
  }
}
