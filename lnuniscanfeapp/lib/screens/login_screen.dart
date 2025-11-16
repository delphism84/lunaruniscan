import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../providers/websocket_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _idController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    // skip login and go to main screen
    _navigateToMainScreen();
  }

  void _navigateToMainScreen() {
    Navigator.of(context).pushReplacementNamed('/main');
  }

  void _showAlert(String title, String message) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            child: const Text('OK'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemBackground,
      child: SafeArea(
        child: Column(
          children: [
            // top background image
            Expanded(
              flex: 3,
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: CupertinoColors.white,
                ),
                child: Center(                                 
                  child: Image.asset(
                    'assets/images/login_top_bg.png',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            
            // login form
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // id input
                    Container(
                      decoration: BoxDecoration(
                        color: CupertinoColors.systemGrey6,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: CupertinoTextField(
                        controller: _idController,
                        placeholder: 'ID',
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: const BoxDecoration(),
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // password input
                    Container(
                      decoration: BoxDecoration(
                        color: CupertinoColors.systemGrey6,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: CupertinoTextField(
                        controller: _passwordController,
                        placeholder: 'Password',
                        obscureText: true,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: const BoxDecoration(),
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // login button
                    SizedBox(
                      width: double.infinity,
                      child: CupertinoButton(
                        color: CupertinoColors.systemBlue,
                        borderRadius: BorderRadius.circular(10),
                        onPressed: _isLoading ? null : _handleLogin,
                        child: _isLoading
                            ? const CupertinoActivityIndicator(
                                color: CupertinoColors.white,
                              )
                            : const Text(
                                'Login',
                                style: TextStyle(
                                  color: CupertinoColors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // signup and find buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        CupertinoButton(
                          onPressed: () {
                            // implement signup
                            _showAlert('Info', 'Signup feature coming soon');
                          },
                          child: const Text(
                            'Sign Up',
                            style: TextStyle(
                              fontSize: 14,
                              color: CupertinoColors.systemGrey,
                            ),
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 20,
                          color: CupertinoColors.systemGrey4,
                        ),
                        CupertinoButton(
                          onPressed: () {
                            // implement find id/password
                            _showAlert('Info', 'Find ID/Password feature coming soon');
                          },
                          child: const Text(
                            'Find ID/Password',
                            style: TextStyle(
                              fontSize: 14,
                              color: CupertinoColors.systemGrey,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            // footer logo
            Expanded(
              flex: 1,
              child: Container(
                padding: const EdgeInsets.all(16),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      CupertinoIcons.app_badge,
                      size: 40,
                      color: CupertinoColors.systemGrey3,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'LN UniScan',
                      style: TextStyle(
                        fontSize: 12,
                        color: CupertinoColors.systemGrey2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
