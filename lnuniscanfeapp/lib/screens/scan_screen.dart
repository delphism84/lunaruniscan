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

  @override
  void initState() {
    super.initState();
    _initializeStreams();
    _scanService.setMode(ScanMode.barcode);
  }

  void _initializeStreams() {
    // 바코드 스트림 구독
    _barcodeSubscription = _scanService.barcodeStream.listen((code) {
      if (mounted) {
        setState(() {});
      }
    });
    
    // 카메라 모드 제거됨
  }

  @override
  void dispose() {
    _barcodeSubscription?.cancel();
    super.dispose();
  }

  void _toggleAutoMode() {
    setState(() {
      _scanService.setAutoMode(!_scanService.isAutoMode);
    });
  }

  void _onRecognizeButtonPressed() {
    _scanService.processManualBarcode();
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
          
          // 하단 컨트롤 영역 (70px)
          Container(
            height: 70,
            color: CupertinoColors.systemBackground,
            child: Column(
              children: [
                // 상태/컨트롤 행
                Container(
                  height: 70,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildStatusRow(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow() {
    // 바코드 모드만 유지
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
        
        // 카운터 뱃지
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

}
