import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

class ManagementScreen extends StatefulWidget {
  const ManagementScreen({super.key});

  @override
  State<ManagementScreen> createState() => _ManagementScreenState();
}

class _ManagementScreenState extends State<ManagementScreen> {
  bool _loading = false;
  List<Map<String, dynamic>> _devices = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refresh();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => _loading = true);

    final app = context.read<AppState>();
    await app.refreshDevices();

    if (!mounted) return;
    setState(() {
      _devices = app.deviceList;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final enabled = app.deviceEnabled;

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemBackground,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  const Text(
                    'Devices',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    onPressed: _loading ? null : _refresh,
                    child: const Icon(CupertinoIcons.refresh, size: 22),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CupertinoActivityIndicator())
                  : _devices.isEmpty
                      ? const Center(
                          child: Text(
                            'No PC registered',
                            style: TextStyle(color: CupertinoColors.systemGrey),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _devices.length,
                          itemBuilder: (context, index) {
                            final d = _devices[index];
                            final id = (d['id'] as String?) ?? '';
                            final name = (d['name'] as String?) ?? 'PC';
                            final status = (d['status'] as String?) ?? 'offline';
                            final on = enabled[id] ?? true;
                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFE4EF), // pink-ish for PC rows
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  const SizedBox(width: 12),
                                  const Icon(CupertinoIcons.device_desktop, color: CupertinoColors.systemPink),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '$name',
                                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'ID: $id • $status',
                                          style: const TextStyle(fontSize: 11, color: CupertinoColors.systemGrey),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  CupertinoSwitch(
                                    value: on,
                                    onChanged: (v) => app.setDeviceEnabled(id, v),
                                  ),
                                  CupertinoButton(
                                    padding: const EdgeInsets.all(12),
                                    onPressed: () => _confirmUnbind(app, id),
                                    child: const Icon(CupertinoIcons.xmark_circle, color: CupertinoColors.systemRed),
                                  ),
                                ],
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

  void _confirmUnbind(AppState app, String deviceId) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Unbind'),
        content: const Text('Unbind this PC?'),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('Unbind'),
            onPressed: () async {
              await app.unbindDevice(deviceId);
              if (mounted) Navigator.of(context).pop();
              if (mounted) _refresh();
            },
          ),
        ],
      ),
    );
  }
}
