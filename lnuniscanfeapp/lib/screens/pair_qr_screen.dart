import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';

class PairQrScreen extends StatefulWidget {
  const PairQrScreen({super.key});

  @override
  State<PairQrScreen> createState() => _PairQrScreenState();
}

class _PairQrScreenState extends State<PairQrScreen> {
  final _codeCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    detectionTimeoutMs: 350,
    returnImage: false,
    // NOTE: do not restrict formats here; some devices/plugins fail to report
    // QR when formats are restricted. We'll parse the payload ourselves.
  );

  bool _busy = false;
  String? _error;
  String _lastDetect = '';

  @override
  void dispose() {
    _scanner.dispose();
    _codeCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  ({String code, String pin})? _parsePayload(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;

    // 1) URL: uniscan://pair?code=123456&pin=7890
    final uri = Uri.tryParse(s);
    if (uri != null && uri.queryParameters.isNotEmpty) {
      final code = (uri.queryParameters['code'] ?? '').trim().toUpperCase();
      final pin = (uri.queryParameters['pin'] ?? '').trim();
      if (RegExp(r'^[A-Z0-9]{6}$').hasMatch(code) && RegExp(r'^\d{4}$').hasMatch(pin)) {
        return (code: code, pin: pin);
      }
    }

    // 2) JSON: {"code":"123456","pin":"7890"} or {"pairCode":...,"pin":...}
    try {
      final obj = jsonDecode(s);
      if (obj is Map) {
        final code = (obj['code'] ?? obj['pairCode'] ?? '').toString().trim().toUpperCase();
        final pin = (obj['pin'] ?? '').toString().trim();
        if (RegExp(r'^[A-Z0-9]{6}$').hasMatch(code) && RegExp(r'^\d{4}$').hasMatch(pin)) {
          return (code: code, pin: pin);
        }
      }
    } catch (_) {}

    // 3) Plain: "123456-7890" or "ABC123 7890"
    final m = RegExp(r'^([A-Z0-9]{6})\s*[-: ]\s*(\d{4})$').firstMatch(s.toUpperCase());
    if (m != null) {
      return (code: m.group(1)!, pin: m.group(2)!);
    }

    return null;
  }

  Future<void> _pair({required String code, required String pin}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final app = context.read<AppState>();
    try {
      await app.pairWithCode(code, pin: pin);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_busy) return;
    final raws = capture.barcodes.map((b) => b.rawValue).whereType<String>().toList();
    final raw = raws.firstWhere((s) => s.trim().isNotEmpty, orElse: () => '');
    if (raw.isEmpty) {
      setState(() {
        _lastDetect = 'onDetect: barcodes=${capture.barcodes.length}, raw=empty';
      });
      return;
    }

    // Debug: help diagnose "no log changes" cases
    setState(() {
      _lastDetect = 'onDetect: barcodes=${capture.barcodes.length}, raw=$raw';
    });
    // ignore: avoid_print
    debugPrint('[PairQr] $_lastDetect');

    final parsed = _parsePayload(raw);
    if (parsed == null) {
      setState(() => _error = 'Invalid QR payload');
      return;
    }

    _codeCtrl.text = parsed.code;
    _pinCtrl.text = parsed.pin;
    // QR은 원샷 자동 등록
    _pair(code: parsed.code, pin: parsed.pin);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Pair Device'),
      ),
      child: SafeArea(
        child: Column(
          children: [
            _buildSectionHeader('Device'),
            _buildInfoCard(
              icon: CupertinoIcons.device_phone_portrait,
              title: 'Device ID',
              subtitle: app.eqid ?? '------',
            ),
            _buildSectionHeader('Pair (manual)'),
            _buildFieldCard(
              icon: CupertinoIcons.number,
              title: 'Pair code',
              hint: 'Enter 6 characters',
              controller: _codeCtrl,
              textCapitalization: TextCapitalization.characters,
              keyboardType: TextInputType.text,
              obscureText: false,
            ),
            _buildFieldCard(
              icon: CupertinoIcons.lock,
              title: 'PIN',
              hint: '4 digits',
              controller: _pinCtrl,
              textCapitalization: TextCapitalization.none,
              keyboardType: TextInputType.number,
              obscureText: true,
            ),
            _buildActionCard(
              icon: CupertinoIcons.check_mark_circled,
              title: 'Pair now',
              subtitle: _busy ? 'Pairing…' : 'Use manual input if QR scan fails',
              onTap: _busy ? null : () => _pair(code: _codeCtrl.text.trim(), pin: _pinCtrl.text.trim()),
              trailing: _busy ? const CupertinoActivityIndicator() : null,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  _error!,
                  style: const TextStyle(color: CupertinoColors.systemRed, fontSize: 12),
                ),
              ),
            if (_lastDetect.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: Text(
                  _lastDetect,
                  style: const TextStyle(color: CupertinoColors.systemGrey, fontSize: 11),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            _buildSectionHeader('Pair (QR scan: one-shot)'),
            Expanded(
              child: MobileScanner(
                controller: _scanner,
                onDetect: _onDetect,
                fit: BoxFit.cover,
                // NOTE: do not set scanWindow here; some platforms treat it as pixel-based
                // and it can effectively disable detection when given fractional values.
                errorBuilder: (context, error, child) {
                  // ignore: avoid_print
                  debugPrint('[PairQr] MobileScanner error: $error');
                  return Center(
                    child: Text(
                      'Camera error: $error',
                      style: const TextStyle(color: CupertinoColors.systemRed),
                      textAlign: TextAlign.center,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: CupertinoColors.systemGrey,
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey6,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(icon, color: CupertinoColors.systemBlue, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(fontSize: 14, color: CupertinoColors.systemGrey)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldCard({
    required IconData icon,
    required String title,
    required String hint,
    required TextEditingController controller,
    required TextCapitalization textCapitalization,
    required TextInputType keyboardType,
    required bool obscureText,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey6,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(icon, color: CupertinoColors.systemBlue, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                CupertinoTextField(
                  controller: controller,
                  placeholder: hint,
                  textCapitalization: textCapitalization,
                  keyboardType: keyboardType,
                  obscureText: obscureText,
                  autocorrect: false,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback? onTap,
    Widget? trailing,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey6,
        borderRadius: BorderRadius.circular(10),
      ),
      child: CupertinoButton(
        padding: const EdgeInsets.all(16),
        onPressed: onTap,
        child: Row(
          children: [
            Icon(icon, color: CupertinoColors.systemBlue, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: CupertinoColors.label),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(fontSize: 13, color: CupertinoColors.systemGrey)),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }
}

