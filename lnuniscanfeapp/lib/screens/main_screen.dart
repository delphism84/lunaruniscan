import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import 'scan_screen.dart';
import 'result_screen.dart';
import 'management_screen.dart';
import 'settings_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  bool _showDrawer = false;

  final List<Widget> _screens = [
    const ScanScreen(),
    const ResultScreen(),
    const ManagementScreen(),
    const SettingsScreen(),
  ];

  void _toggleDrawer() {
    setState(() {
      _showDrawer = !_showDrawer;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final topInset = MediaQuery.of(context).padding.top;
    final headerHeight = topInset + 60; // 최대한 얇게(안전영역 포함)
    final eqid = app.eqid ?? '------';
    final alias = app.alias;

    return CupertinoPageScaffold(
      child: Stack(
        children: [
          Column(
            children: [
              // top header (compact)
              Container(
                height: headerHeight,
                width: double.infinity,
                color: CupertinoColors.systemBlue,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, topInset + 6, 16, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              eqid,
                              style: const TextStyle(
                                fontSize: 20,
                                color: CupertinoColors.white,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            GestureDetector(
                              onTap: () => _showEditAliasDialog(app, alias),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: CupertinoColors.white.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(CupertinoIcons.pencil, color: CupertinoColors.white, size: 12),
                                    const SizedBox(width: 6),
                                    Text(
                                      alias,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: CupertinoColors.white,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // content area
              Expanded(
                child: _screens[_currentIndex],
              ),

              // bottom tabs (Korean labels)
              Container(
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: CupertinoColors.systemGrey5,
                      width: 0.5,
                    ),
                  ),
                ),
                child: CupertinoTabBar(
                  currentIndex: _currentIndex,
                  onTap: (index) {
                    setState(() {
                      _currentIndex = index;
                    });
                  },
                  backgroundColor: CupertinoColors.systemBackground.withOpacity(0.9),
                  activeColor: CupertinoColors.systemBlue,
                  inactiveColor: CupertinoColors.systemGrey,
                  iconSize: 24,
                  items: const [
                    BottomNavigationBarItem(
                      icon: Icon(CupertinoIcons.qrcode_viewfinder),
                      label: 'Scan',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(CupertinoIcons.list_bullet),
                      label: 'Results',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(CupertinoIcons.device_desktop),
                      label: 'Devices',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(CupertinoIcons.settings),
                      label: 'Settings',
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (_showDrawer) _buildDrawerOverlay(),
        ],
      ),
    );
  }

  void _showEditAliasDialog(AppState app, String current) {
    final controller = TextEditingController(text: current);
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Edit Alias'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            SizedBox(
              height: 36,
              child: CupertinoTextField(
                controller: controller,
                placeholder: 'SCANNER',
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                style: const TextStyle(fontSize: 11),
                placeholderStyle: const TextStyle(fontSize: 11, color: CupertinoColors.systemGrey),
                clearButtonMode: OverlayVisibilityMode.editing,
              ),
            ),
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
              final v = controller.text.trim();
              await app.updateAlias(v);
              if (mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerOverlay() {
    return GestureDetector(
      onTap: _toggleDrawer,
      child: Container(
        color: CupertinoColors.black.withOpacity(0.3),
        child: Row(
          children: [
            Container(
              width: 280,
              height: double.infinity,
              color: CupertinoColors.systemBackground.resolveFrom(context),
              child: SafeArea(
                child: Column(
                  children: [
                    // drawer header
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: CupertinoColors.systemGrey5,
                            width: 0.5,
                          ),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            CupertinoIcons.person_circle_fill,
                            size: 50,
                            color: CupertinoColors.systemBlue,
                          ),
                          SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'User Name',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'user@example.com',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: CupertinoColors.systemGrey,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    
                    // drawer menu items
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          _buildDrawerItem(
                            icon: CupertinoIcons.home,
                            title: 'Dashboard',
                            onTap: () {
                              _toggleDrawer();
                              setState(() {
                                _currentIndex = 0;
                              });
                            },
                          ),
                          _buildDrawerItem(
                            icon: CupertinoIcons.chart_bar,
                            title: 'Statistics',
                            onTap: () {
                              _toggleDrawer();
                            },
                          ),
                          _buildDrawerItem(
                            icon: CupertinoIcons.cloud_download,
                            title: 'Sync Data',
                            onTap: () {
                              _toggleDrawer();
                            },
                          ),
                          _buildDrawerItem(
                            icon: CupertinoIcons.doc_text,
                            title: 'Export',
                            onTap: () {
                              _toggleDrawer();
                            },
                          ),
                          Container(
                            height: 1,
                            color: CupertinoColors.systemGrey5,
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                          ),
                          _buildDrawerItem(
                            icon: CupertinoIcons.info,
                            title: 'About',
                            onTap: () {
                              _toggleDrawer();
                            },
                          ),
                          _buildDrawerItem(
                            icon: CupertinoIcons.question_circle,
                            title: 'Help',
                            onTap: () {
                              _toggleDrawer();
                            },
                          ),
                        ],
                      ),
                    ),
                    
                    // logout button
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: CupertinoColors.systemGrey5,
                            width: 0.5,
                          ),
                        ),
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: CupertinoButton(
                          color: CupertinoColors.systemRed,
                          borderRadius: BorderRadius.circular(10),
                          onPressed: () {
                            Navigator.of(context).pushReplacementNamed('/login');
                          },
                          child: const Text(
                            'Logout',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(child: Container()), // 빈 공간 (탭하면 drawer 닫힘)
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      onPressed: onTap,
      child: Row(
        children: [
          Icon(
            icon,
            color: CupertinoColors.systemBlue,
            size: 24,
          ),
          const SizedBox(width: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: CupertinoColors.label,
            ),
          ),
        ],
      ),
    );
  }
}
