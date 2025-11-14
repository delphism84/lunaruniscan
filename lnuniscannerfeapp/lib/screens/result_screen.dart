import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import '../services/enhanced_scan_service.dart';
import '../models/scan_item.dart';

class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  final EnhancedScanService _scanService = EnhancedScanService();

  @override
  void initState() {
    super.initState();
    // listen to scan updates for real-time progress
    _scanService.scanStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemBackground,
      child: SafeArea(
        child: Column(
          children: [
            // header info
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: CupertinoColors.systemGrey5,
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Items: ${_scanService.scanItems.length}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _buildStatusChip('Processing', _scanService.getItemsCountByStatus(ScanStatus.processing), CupertinoColors.systemOrange),
                          const SizedBox(width: 8),
                          _buildStatusChip('Uploading', _scanService.getItemsCountByStatus(ScanStatus.uploading), CupertinoColors.systemBlue),
                          const SizedBox(width: 8),
                          _buildStatusChip('Completed', _scanService.getItemsCountByStatus(ScanStatus.completed), CupertinoColors.systemGreen),
                        ],
                      ),
                    ],
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      setState(() {});
                    },
                    child: const Icon(
                      CupertinoIcons.refresh,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
            
            // scan results list
            Expanded(
              child: _scanService.scanItems.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            CupertinoIcons.qrcode,
                            size: 64,
                            color: CupertinoColors.systemGrey3,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'No scan results yet',
                            style: TextStyle(
                              fontSize: 18,
                              color: CupertinoColors.systemGrey,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Start scanning to see results here',
                            style: TextStyle(
                              fontSize: 14,
                              color: CupertinoColors.systemGrey2,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _scanService.scanItems.length,
                      itemBuilder: (context, index) {
                        final item = _scanService.scanItems[_scanService.scanItems.length - 1 - index]; // reverse order
                        return _buildScanItemCard(item);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        '$label: $count',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }

  Widget _buildScanItemCard(IScanItem item) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey6,
        borderRadius: BorderRadius.circular(10),
      ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                _buildItemThumbnail(item),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              item.displayText,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Text(
                                            _formatTime(item.timestamp),
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: CupertinoColors.systemGrey,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _buildStatusIndicator(item),
                                          ),
                                          CupertinoButton(
                                            padding: EdgeInsets.zero,
                                            onPressed: () => _showItemDetail(item),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: CupertinoColors.systemBlue.withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: const Text(
                                                'Detail',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: CupertinoColors.systemBlue,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
    );
  }

  Widget _buildItemThumbnail(IScanItem item) {
    if (item.type == ScanType.image && item.thumbnailPath != null) {
      return Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          image: DecorationImage(
            image: FileImage(File(item.thumbnailPath!)),
            fit: BoxFit.cover,
          ),
        ),
      );
    } else {
      return Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: CupertinoColors.systemGrey5,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          item.type == ScanType.barcode 
              ? CupertinoIcons.barcode 
              : CupertinoIcons.photo,
          color: CupertinoColors.systemGrey,
          size: 24,
        ),
      );
    }
  }

  Widget _buildStatusIndicator(IScanItem item) {
    String statusText;
    Color statusColor;
    Widget? progressWidget;

    switch (item.status) {
      case ScanStatus.cached:
        statusText = 'Cached';
        statusColor = CupertinoColors.systemGrey;
        break;
      case ScanStatus.uploading:
        statusText = 'Uploading ${(item.progress * 100).toInt()}%';
        statusColor = CupertinoColors.systemBlue;
        progressWidget = _buildProgressBar(item.progress, statusColor);
        break;
      case ScanStatus.processing:
        statusText = 'Processing ${(item.progress * 100).toInt()}%';
        statusColor = CupertinoColors.systemOrange;
        progressWidget = _buildProgressBar(item.progress, statusColor);
        break;
      case ScanStatus.completed:
        statusText = 'Completed';
        statusColor = CupertinoColors.systemGreen;
        break;
      case ScanStatus.failed:
        statusText = 'Failed';
        statusColor = CupertinoColors.systemRed;
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          statusText,
          style: TextStyle(
            fontSize: 12,
            color: statusColor,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (progressWidget != null) ...[
          const SizedBox(height: 4),
          progressWidget,
        ],
      ],
    );
  }

  Widget _buildProgressBar(double progress, Color color) {
    return Container(
      height: 4,
      width: 120,
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(2),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: progress,
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
  }

  void _showItemDetail(IScanItem item) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text('${item.type.name.toUpperCase()} Detail'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Data: ${item.displayText}'),
            const SizedBox(height: 8),
            Text('Status: ${item.status.name}'),
            const SizedBox(height: 8),
            Text('Progress: ${(item.progress * 100).toInt()}%'),
            const SizedBox(height: 8),
            Text('Time: ${item.timestamp}'),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Close'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
