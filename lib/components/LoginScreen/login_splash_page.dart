import 'dart:async';

import 'package:finamp/components/finamp_icon.dart';
import 'package:finamp/screens/view_selector.dart';
import 'package:finamp/services/kb_account_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

class LoginSplashPage extends ConsumerStatefulWidget {
  static const routeName = "login/splash";

  final VoidCallback onGetStartedPressed;

  const LoginSplashPage({super.key, required this.onGetStartedPressed});

  @override
  ConsumerState<LoginSplashPage> createState() => _LoginSplashPageState();
}

class _LoginSplashPageState extends ConsumerState<LoginSplashPage> {
  bool _isCheckingStatus = true;
  bool _isEnrolled = true;

  // Pairing state
  bool _isPairingMode = false;
  String? _pairingCode;
  String? _pairingId;
  String? _pollToken;
  Timer? _pollTimer;
  bool _isPolling = false;

  @override
  void initState() {
    super.initState();
    _checkServerStatus();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkServerStatus() async {
    final service = ref.read(kbAccountServiceProvider);
    try {
      final status = await service.checkStatus();
      if (mounted) {
        setState(() {
          _isEnrolled = status['enrolled'] == true;
          _isCheckingStatus = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCheckingStatus = false;
        });
      }
    }
  }

  Future<void> _startPairing() async {
    setState(() {
      _isPairingMode = true;
      _pairingCode = null;
    });

    final service = ref.read(kbAccountServiceProvider);
    try {
      final res = await service.createPairingRequest();
      if (!mounted) return;
      setState(() {
        _pairingCode = (res['code'] ?? res['pairing_code']) as String?;
        _pairingId = res['pairing_id'] as String?;
        _pollToken = res['poll_token'] as String?;
      });

      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
        if (_isPolling || !mounted || _pairingCode == null) return;
        _isPolling = true;
        try {
          final pollRes = await service.pollPairing(
            code: _pairingCode!,
            pairingId: _pairingId,
            pollToken: _pollToken,
          );
          if (pollRes['state'] == 'approved') {
            timer.cancel();
            if (mounted) {
              Navigator.of(context).pushReplacementNamed(ViewSelector.routeName);
            }
          }
        } catch (_) {} finally {
          _isPolling = false;
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to request pairing code: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isPairingMode = false);
      }
    }
  }

  void _showSignInModal({bool isEnrollment = false}) {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    final nameController = TextEditingController(text: isEnrollment ? 'Kolten' : '');
    bool isSubmitting = false;
    String? errorText;

    final parentNav = Navigator.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          return Padding(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isEnrollment ? 'Create KB Account' : 'Sign In to KB Account',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  isEnrollment
                      ? 'Set up your master owner account to connect all your devices.'
                      : 'Sign in to access your synchronized music and book library.',
                  style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 13),
                ),
                const SizedBox(height: 18),
                if (isEnrollment) ...[
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: 'Display Name',
                      prefixIcon: const Icon(Icons.badge_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: usernameController,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Username',
                    prefixIcon: const Icon(Icons.person_outline),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 10),
                  Text(errorText!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final user = usernameController.text.trim();
                          final pass = passwordController.text;
                          if (user.isEmpty || pass.isEmpty) {
                            setModalState(() => errorText = 'Please enter both username and password');
                            return;
                          }
                          setModalState(() {
                            isSubmitting = true;
                            errorText = null;
                          });

                          try {
                            final service = ref.read(kbAccountServiceProvider);
                            if (isEnrollment) {
                              await service.enrollOwner(
                                username: user,
                                password: pass,
                                displayName: nameController.text.trim().isNotEmpty ? nameController.text.trim() : user,
                              );
                            } else {
                              await service.login(username: user, password: pass);
                            }

                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                              parentNav.pushReplacementNamed(ViewSelector.routeName);
                            }
                          } catch (e) {
                            setModalState(() {
                              isSubmitting = false;
                              errorText = e.toString().replaceAll('Exception: ', '');
                            });
                          }
                        },
                  child: isSubmitting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(isEnrollment ? 'Create Account' : 'Sign In', style: const TextStyle(fontSize: 16)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 24),
                  Hero(tag: "finamp_logo", child: FinampIcon(140, 140)),
                  const SizedBox(height: 20),
                  Text(
                    'KB Music',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                      color: isDark ? Colors.white : const Color(0xFF161618),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Personal Music & Books Ecosystem',
                    style: TextStyle(fontSize: 15, color: isDark ? Colors.white60 : Colors.black54),
                  ),
                  const SizedBox(height: 40),

                  if (_isPairingMode) ...[
                    // Pairing code card
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E1E22) : const Color(0xFFF2F2F7),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'Pair This Device',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Open KB Music on your Mac or phone, go to Account, and tap "Pair New Device". Enter this code:',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black54),
                          ),
                          const SizedBox(height: 20),
                          if (_pairingCode == null)
                            const CircularProgressIndicator()
                          else
                            Text(
                              _pairingCode!,
                              style: const TextStyle(
                                fontSize: 44,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 8,
                                color: Color(0xFF007AFF),
                              ),
                            ),
                          const SizedBox(height: 16),
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                              SizedBox(width: 10),
                              Text('Waiting for approval...', style: TextStyle(fontSize: 13, color: Colors.grey)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () {
                        _pollTimer?.cancel();
                        setState(() => _isPairingMode = false);
                      },
                      child: const Text('Cancel Pairing'),
                    ),
                  ] else ...[
                    // Standard Sign In & Pair Options
                    FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => _showSignInModal(isEnrollment: false),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.login_rounded, size: 20),
                          SizedBox(width: 10),
                          Text('Sign In with KB Account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _startPairing,
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.phonelink_setup_rounded, size: 20),
                          SizedBox(width: 10),
                          Text('Pair with Another Device', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    if (!_isEnrolled && !_isCheckingStatus) ...[
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () => _showSignInModal(isEnrollment: true),
                        child: const Text('First time setup? Create Owner Account'),
                      ),
                    ],
                  ],

                  const SizedBox(height: 48),

                  // Fallback manual server connection
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: isDark ? Colors.white38 : Colors.black38),
                    icon: const Icon(TablerIcons.server, size: 16),
                    label: const Text('Self-Hosted Advanced Setup', style: TextStyle(fontSize: 13)),
                    onPressed: widget.onGetStartedPressed,
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
