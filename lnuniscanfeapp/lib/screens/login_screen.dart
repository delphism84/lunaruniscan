import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _started = false;

  @override
  void dispose() {
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _bootstrap();
    }
  }

  Future<void> _bootstrap() async {
    final app = context.read<AppState>();
    await app.initialize();
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/main');
  }



  @override
  Widget build(BuildContext context) {
    return const CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemBackground,
      child: Center(
        child: CupertinoActivityIndicator(radius: 16),
      ),
    );
  }
}
