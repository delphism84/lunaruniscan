import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/enhanced_scan_service.dart';
import '../services/scan_service.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final ScanService _scanService = ScanService();
  StreamSubscription<String>? _barcodeSubscription;
  StreamSubscription<String>? _imageSubscription;
  
  int _selectedTabIndex = 0; // 0: 바코드, 1: 카메라

  @override
  void initState() {
    super.initState();
    _initializeStreams();
  }

  void _initializeStreams() {
    // 바코드 스트림 구독
    _barcodeSubscription = _scanService.barcodeStream.listen((code) {
      if (mounted) {
        setState(() {});
      }
    });
    
    // 이미지 스트림 구독
    _imageSubscription = _scanService.imageStream.listen((imagePath) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _barcodeSubscription?.cancel();
    _imageSubscription?.cancel();
    super.dispose();
  }

  void _onTabChanged(int index) {
    setState(() {
      _selectedTabIndex = index;
      _scanService.setMode(index == 0 ? ScanMode.barcode : ScanMode.camera);
    });
  }

  void _toggleAutoMode() {
    setState(() {
      _scanService.setAutoMode(!_scanService.isAutoMode);
    });
  }

  void _onRecognizeButtonPressed() {
    _scanService.processManualBarcode();
  }

  void _onCaptureButtonPressed() {
    _scanService.captureImage();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.black,
      child: Column(
        children: [
          // 카메라 영역 (단일 MobileScanner)
          Expanded(
            child: MobileScanner(
              onDetect: _scanService.onBarcodeDetected,
            ),
          ),
          
          // 하단 컨트롤 영역 (140px)
          Container(
            height: 140,
            color: CupertinoColors.systemBackground,
            child: Column(
              children: [
                // 상태/컨트롤 행 (70px)
                Container(
                  height: 70,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildStatusRow(),
                ),
                
                // 탭 메뉴 행 (70px)
                Container(
                  height: 70,
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: CupertinoColors.systemGrey5,
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: _buildTabRow(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow() {
    if (_selectedTabIndex == 0) {
      // 바코드 모드
      return Row(
        children: [
          // 자동 모드 토글
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Text(
                  _scanService.isAutoMode ? 'Auto ON' : 'Auto OFF',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _scanService.isAutoMode 
                        ? CupertinoColors.systemGreen 
                        : CupertinoColors.systemOrange,
                  ),
                ),
                const SizedBox(width: 8),
                CupertinoSwitch(
                  value: _scanService.isAutoMode,
                  onChanged: (value) => _toggleAutoMode(),
                  activeColor: CupertinoColors.systemGreen,
                ),
              ],
            ),
          ),
          
          // 상태 메시지 또는 인식 버튼
          Expanded(
            flex: 3,
            child: _buildBarcodeStatusArea(),
          ),
          
          // 카운터 뱃지 (총 항목 수 표시 - EnhancedScanService 기반)
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: CupertinoColors.systemBlue,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${EnhancedScanService().scanItems.length}',
                style: const TextStyle(
                  color: CupertinoColors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      );
    } else {
      // 카메라 모드
      return Row(
        children: [
          // 상태 메시지
          Expanded(
            flex: 2,
            child: Text(
              _scanService.lastImageResult.isNotEmpty 
                  ? '촬영 완료: ${_scanService.lastImageResult}'
                  : '사진 촬영 준비',
              style: const TextStyle(
                fontSize: 14,
                color: CupertinoColors.label,
              ),
            ),
          ),
          
          // 촬영 버튼
          Expanded(
            flex: 1,
            child: Center(
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                color: CupertinoColors.systemBlue,
                borderRadius: BorderRadius.circular(20),
                onPressed: _onCaptureButtonPressed,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      CupertinoIcons.camera_fill,
                      color: CupertinoColors.white,
                      size: 18,
                    ),
                    SizedBox(width: 4),
                    Text(
                      '촬영',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: CupertinoColors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // 카운터 뱃지 (카메라 모드) - EnhancedScanService 기반
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: CupertinoColors.systemBlue,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${EnhancedScanService().scanItems.length}',
                style: const TextStyle(
                  color: CupertinoColors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      );
    }
  }

  Widget _buildBarcodeStatusArea() {
    if (_scanService.isAutoMode) {
      // 자동 모드: 마지막 결과를 라운드 박스 뱃지로 표시
      if (_scanService.lastBarcodeResult.isNotEmpty) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: CupertinoColors.systemGreen,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '(${_scanService.lastBarcodeResult})',
                style: const TextStyle(
                  fontSize: 12,
                  color: CupertinoColors.white,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_scanService.lastBarcodeTime != null) ...[
              const SizedBox(height: 4),
              Text(
                _formatTime(_scanService.lastBarcodeTime!),
                style: const TextStyle(
                  fontSize: 10,
                  color: CupertinoColors.systemGrey,
                ),
              ),
            ],
          ],
        );
      } else {
        return const Center(
          child: Text(
            'Scan a barcode',
            style: TextStyle(
              fontSize: 14,
              color: CupertinoColors.systemGrey,
            ),
            textAlign: TextAlign.center,
          ),
        );
      }
    } else {
      // 수동 모드: 한 줄 버튼(바코드 텍스트 + 인식 아이콘)
      final hasPending = _scanService.pendingBarcodeData != null;
      final buttonLabel = hasPending
          ? _scanService.pendingBarcodeData!
          : '바코드를 스캔 후 인식';
      return Center(
        child: CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: CupertinoColors.systemBlue,
          borderRadius: BorderRadius.circular(20),
          onPressed: _onRecognizeButtonPressed,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  '$buttonLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(CupertinoIcons.qrcode_viewfinder, color: CupertinoColors.white, size: 18),
            ],
          ),
        ),
      );
    }
  }

  String _formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:'
           '${dateTime.minute.toString().padLeft(2, '0')}:'
           '${dateTime.second.toString().padLeft(2, '0')}';
  }

  Widget _buildTabRow() {
    return Row(
      children: [
        // 바코드 스캔 탭
        Expanded(
          child: GestureDetector(
            onTap: () => _onTabChanged(0),
            child: Container(
              height: double.infinity,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: _selectedTabIndex == 0 
                        ? CupertinoColors.systemBlue 
                        : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    CupertinoIcons.qrcode_viewfinder,
                    size: 24,
                    color: _selectedTabIndex == 0 
                        ? CupertinoColors.systemBlue 
                        : CupertinoColors.systemGrey,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Barcode Scan',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _selectedTabIndex == 0 
                          ? CupertinoColors.systemBlue 
                          : CupertinoColors.systemGrey,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        
        // 카메라 촬영 탭
        Expanded(
          child: GestureDetector(
            onTap: () => _onTabChanged(1),
            child: Container(
              height: double.infinity,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: _selectedTabIndex == 1 
                        ? CupertinoColors.systemBlue 
                        : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    CupertinoIcons.camera,
                    size: 24,
                    color: _selectedTabIndex == 1 
                        ? CupertinoColors.systemBlue 
                        : CupertinoColors.systemGrey,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Camera Scan',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _selectedTabIndex == 1 
                          ? CupertinoColors.systemBlue 
                          : CupertinoColors.systemGrey,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
