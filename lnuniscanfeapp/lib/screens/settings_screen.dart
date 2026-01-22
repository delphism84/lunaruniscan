import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/enhanced_scan_service.dart';
import '../providers/app_state.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final EnhancedScanService _scanService = EnhancedScanService();
  late int _duplicateFilterSeconds;

  @override
  void initState() {
    super.initState();
    _duplicateFilterSeconds = _scanService.getDuplicateFilterSeconds();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemBackground,
      child: SafeArea(
        child: ListView(
          children: [
            // app settings section
            _buildSectionHeader('App Settings'),
            _buildSettingItem(
              icon: CupertinoIcons.link,
              title: 'API Base URL',
              subtitle: app.apiBaseUrl,
              onTap: () => _showApiDialog(app),
            ),
            _buildSettingItem(
              icon: CupertinoIcons.bell,
              title: 'Notifications',
              trailing: CupertinoSwitch(
                value: true,
                onChanged: (value) {},
              ),
            ),
            _buildSettingItem(
              icon: CupertinoIcons.camera,
              title: 'Camera Settings',
              onTap: () {},
            ),
            _buildSettingItem(
              icon: CupertinoIcons.cloud,
              title: 'Manual Sync',
              onTap: () async {
                await app.manualSync();
                if (!mounted) return;
                showCupertinoDialog(
                  context: context,
                  builder: (context) => CupertinoAlertDialog(
                    title: const Text('Sync Started'),
                    content: const Text('Pending uploads will be retried in background.'),
                    actions: [
                      CupertinoDialogAction(
                        child: const Text('OK'),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                );
              },
            ),
            
            const SizedBox(height: 20),
            
            // scan settings section
            _buildSectionHeader('Scan Settings'),
            _buildSettingItem(
              icon: CupertinoIcons.barcode,
              title: 'Duplicate Filter',
              subtitle: 'Ignore same barcode within $_duplicateFilterSeconds seconds',
              onTap: () => _showDuplicateFilterDialog(),
            ),
            _buildSettingItem(
              icon: CupertinoIcons.clear,
              title: 'Clear Duplicate Cache',
              subtitle: 'Reset barcode scan history',
              onTap: () => _clearDuplicateCache(),
            ),
            
            const SizedBox(height: 20),
            
            // data settings section
            _buildSectionHeader('Data Management'),
            _buildSettingItem(
              icon: CupertinoIcons.download_circle,
              title: 'Export Data',
              onTap: () {},
            ),
            _buildSettingItem(
              icon: CupertinoIcons.trash,
              title: 'Clear Cache',
              onTap: () {},
              textColor: CupertinoColors.systemRed,
            ),
            
            const SizedBox(height: 20),
            
            // about section
            _buildSectionHeader('About'),
            _buildSettingItem(
              icon: CupertinoIcons.info,
              title: 'App Version',
              subtitle: '1.0.0',
            ),
            _buildSettingItem(
              icon: CupertinoIcons.doc_text,
              title: 'Terms of Service',
              onTap: () {},
            ),
            _buildSettingItem(
              icon: CupertinoIcons.lock,
              title: 'Privacy Policy',
              onTap: () {},
            ),
          ],
        ),
      ),
    );
  }

  void _showApiDialog(AppState app) {
    final controller = TextEditingController(text: app.apiBaseUrl);
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('API Base URL'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            CupertinoTextField(controller: controller, placeholder: 'http://192.168.1.251:50100'),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          CupertinoDialogAction(
            child: const Text('Save'),
            onPressed: () async {
              await app.setApiBaseUrl(controller.text.trim());
              if (mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  void _showDuplicateFilterDialog() {
    int tempSeconds = _duplicateFilterSeconds;
    
    showCupertinoDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return CupertinoAlertDialog(
              title: const Text('Duplicate Filter Time'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 16),
                  const Text('Set the time interval to ignore duplicate barcodes:'),
                  const SizedBox(height: 16),
                  Container(
                    height: 120,
                    child: CupertinoPicker(
                      itemExtent: 32,
                      scrollController: FixedExtentScrollController(
                        initialItem: tempSeconds - 1, // 1-based to 0-based
                      ),
                      onSelectedItemChanged: (int index) {
                        setDialogState(() {
                          tempSeconds = index + 1; // 0-based to 1-based
                        });
                      },
                      children: List.generate(30, (index) {
                        final seconds = index + 1;
                        return Center(
                          child: Text(
                            '$seconds second${seconds > 1 ? 's' : ''}',
                            style: const TextStyle(fontSize: 16),
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
              actions: [
                CupertinoDialogAction(
                  child: const Text('Cancel'),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
                CupertinoDialogAction(
                  child: const Text('Save'),
                  onPressed: () {
                    setState(() {
                      _duplicateFilterSeconds = tempSeconds;
                    });
                    _scanService.setDuplicateFilterSeconds(tempSeconds);
                    Navigator.of(context).pop();
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _clearDuplicateCache() {
    showCupertinoDialog(
      context: context,
      builder: (BuildContext context) {
        return CupertinoAlertDialog(
          title: const Text('Clear Duplicate Cache'),
          content: const Text(
            'This will reset the barcode scan history used for duplicate filtering. '
            'All barcodes will be treated as new scans.',
          ),
          actions: [
            CupertinoDialogAction(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              child: const Text('Clear'),
              onPressed: () {
                _scanService.clearDuplicateFilterCache();
                Navigator.of(context).pop();
                
                // show confirmation
                showCupertinoDialog(
                  context: context,
                  builder: (context) => CupertinoAlertDialog(
                    title: const Text('Cache Cleared'),
                    content: const Text('Duplicate filter cache has been cleared successfully.'),
                    actions: [
                      CupertinoDialogAction(
                        child: const Text('OK'),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
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

  Widget _buildSettingItem({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    Color? textColor,
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
            Icon(
              icon,
              color: CupertinoColors.systemBlue,
              size: 24,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: textColor ?? CupertinoColors.label,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 14,
                        color: CupertinoColors.systemGrey,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null)
              trailing
            else if (onTap != null)
              const Icon(
                CupertinoIcons.chevron_right,
                size: 16,
                color: CupertinoColors.systemGrey3,
              ),
          ],
        ),
      ),
    );
  }
}
