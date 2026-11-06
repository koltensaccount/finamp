import 'dart:async';

import 'package:finamp/components/bug_reporter_button.dart';
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
              Navigator.of(context, rootNavigator: true).pushReplacementNamed(ViewSelector.routeName);
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
    bool isCreatingAccount = isEnrollment;
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    final nameController = TextEditingController(text: isEnrollment ? 'Kolten' : '');
    bool obscurePassword = true;
    bool obscureConfirmPassword = true;
    bool isSubmitting = false;
    String? usernameError;
    String? passwordError;
    String? confirmPasswordError;
    String? generalError;
    Timer? debounceTimer;

    final parentNav = Navigator.of(context, rootNavigator: true);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: bgColor,
      barrierColor: Colors.black54,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final modalDark = Theme.of(ctx).brightness == Brightness.dark;
          final currentBg = modalDark ? const Color(0xFF1C1C1E) : Colors.white;

          void validateUsername(String val) {
            final trimmed = val.trim().toLowerCase();
            if (trimmed.isEmpty) {
              usernameError = 'Username is required';
            } else if (trimmed.length < 3) {
              usernameError = 'Username must be at least 3 characters';
            } else if (trimmed.length > 30) {
              usernameError = 'Username cannot exceed 30 characters';
            } else if (!RegExp(r'^[a-zA-Z0-9_\-]+$').hasMatch(trimmed)) {
              usernameError = 'Only letters, numbers, underscores, and hyphens';
            } else {
              usernameError = null;
            }
          }

          return Container(
            decoration: BoxDecoration(
              color: currentBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 14,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: modalDark ? Colors.white24 : Colors.black12,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Header Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          isCreatingAccount ? 'Create KB Account' : 'Sign In to KB Account',
                          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          debounceTimer?.cancel();
                          Navigator.pop(ctx);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isCreatingAccount
                        ? 'Set up your account to synchronize your music and book library across all devices.'
                        : 'Sign in to access your synchronized music and book ecosystem.',
                    style: TextStyle(
                      color: modalDark ? Colors.white60 : Colors.black54,
                      fontSize: 13,
                    ),
                  ),

                  // General error banner
                  if (generalError != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              generalError!,
                              style: const TextStyle(color: Colors.red, fontSize: 13, height: 1.3),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 18),

                  // Display Name (Account Creation Only)
                  if (isCreatingAccount) ...[
                    TextField(
                      controller: nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: 'Display Name',
                        hintText: 'e.g. Kolten',
                        helperText: "How your name appears across devices",
                        prefixIcon: const Icon(Icons.badge_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Username
                  TextField(
                    controller: usernameController,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.none,
                    onChanged: (val) {
                      setModalState(() {
                        generalError = null;
                        if (isCreatingAccount) {
                          validateUsername(val);
                        } else {
                          usernameError = null;
                        }
                      });
                      if (isCreatingAccount && usernameError == null && val.trim().length >= 3) {
                        debounceTimer?.cancel();
                        debounceTimer = Timer(const Duration(milliseconds: 500), () async {
                          final service = ref.read(kbAccountServiceProvider);
                          final check = await service.checkUsernameAvailability(val.trim());
                          if (ctx.mounted && isCreatingAccount) {
                            setModalState(() {
                              if (check['available'] == false) {
                                usernameError = check['error']?.toString() ?? 'Username is already taken';
                              }
                            });
                          }
                        });
                      }
                    },
                    decoration: InputDecoration(
                      labelText: 'Username',
                      hintText: 'e.g. kolten',
                      helperText: isCreatingAccount ? '3-30 letters, numbers, hyphens, or underscores' : null,
                      errorText: usernameError,
                      prefixIcon: const Icon(Icons.person_outline),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Password
                  TextField(
                    controller: passwordController,
                    obscureText: obscurePassword,
                    onChanged: (_) {
                      setModalState(() {
                        passwordError = null;
                        generalError = null;
                      });
                    },
                    decoration: InputDecoration(
                      labelText: 'Password',
                      helperText: isCreatingAccount ? 'At least 8 characters' : null,
                      errorText: passwordError,
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        ),
                        onPressed: () => setModalState(() => obscurePassword = !obscurePassword),
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),

                  // Confirm Password (Account Creation Only)
                  if (isCreatingAccount) ...[
                    const SizedBox(height: 14),
                    TextField(
                      controller: confirmPasswordController,
                      obscureText: obscureConfirmPassword,
                      onChanged: (_) {
                        setModalState(() {
                          confirmPasswordError = null;
                          generalError = null;
                        });
                      },
                      decoration: InputDecoration(
                        labelText: 'Confirm Password',
                        errorText: confirmPasswordError,
                        prefixIcon: const Icon(Icons.lock_reset_outlined),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscureConfirmPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          ),
                          onPressed: () => setModalState(() => obscureConfirmPassword = !obscureConfirmPassword),
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],

                  const SizedBox(height: 22),

                  // Submit Button
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
                            final confirmPass = confirmPasswordController.text;
                            final dName = nameController.text.trim();

                            // Validation checks
                            setModalState(() {
                              usernameError = null;
                              passwordError = null;
                              confirmPasswordError = null;
                              generalError = null;
                            });

                            bool hasValidationError = false;

                            if (user.isEmpty) {
                              usernameError = 'Please enter a username';
                              hasValidationError = true;
                            } else if (isCreatingAccount) {
                              if (user.length < 3 || user.length > 30) {
                                usernameError = 'Username must be between 3 and 30 characters';
                                hasValidationError = true;
                              } else if (!RegExp(r'^[a-zA-Z0-9_\-]+$').hasMatch(user)) {
                                usernameError = 'Username can only contain letters, numbers, underscores, and hyphens';
                                hasValidationError = true;
                              }
                            }

                            if (pass.isEmpty) {
                              passwordError = 'Please enter a password';
                              hasValidationError = true;
                            } else if (isCreatingAccount && pass.length < 8) {
                              passwordError = 'Password must be at least 8 characters long';
                              hasValidationError = true;
                            }

                            if (isCreatingAccount) {
                              if (confirmPass.isEmpty) {
                                confirmPasswordError = 'Please confirm your password';
                                hasValidationError = true;
                              } else if (pass != confirmPass) {
                                confirmPasswordError = 'Passwords do not match';
                                hasValidationError = true;
                              }
                            }

                            if (hasValidationError) {
                              setModalState(() {});
                              return;
                            }

                            setModalState(() {
                              isSubmitting = true;
                            });

                            try {
                              final service = ref.read(kbAccountServiceProvider);
                              if (isCreatingAccount) {
                                await service.createAccount(
                                  username: user,
                                  password: pass,
                                  displayName: dName.isNotEmpty ? dName : user,
                                );
                              } else {
                                await service.login(username: user, password: pass);
                              }

                              debounceTimer?.cancel();
                              if (ctx.mounted) {
                                Navigator.pop(ctx, true);
                              }
                            } catch (e) {
                              if (!ctx.mounted) return;
                              setModalState(() {
                                isSubmitting = false;
                                final rawMsg = e.toString().replaceAll('Exception: ', '').trim();
                                if (rawMsg.toLowerCase().contains('already taken') ||
                                    rawMsg.toLowerCase().contains('already registered') ||
                                    rawMsg.toLowerCase().contains('username')) {
                                  usernameError = rawMsg;
                                } else {
                                  generalError = rawMsg;
                                }
                              });
                            }
                          },
                    child: isSubmitting
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(
                            isCreatingAccount ? 'Create Account' : 'Sign In',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),

                  const SizedBox(height: 12),

                  // Toggle between Sign In and Create Account
                  TextButton(
                    onPressed: isSubmitting
                        ? null
                        : () {
                            setModalState(() {
                              isCreatingAccount = !isCreatingAccount;
                              usernameError = null;
                              passwordError = null;
                              confirmPasswordError = null;
                              generalError = null;
                            });
                          },
                    child: Text(
                      isCreatingAccount
                          ? 'Already have an account? Sign In'
                          : 'First time setup? Create KB Account',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).then((authenticated) {
      debounceTimer?.cancel();
      if ((authenticated ?? false) && mounted && parentNav.mounted) {
        parentNav.pushReplacementNamed(ViewSelector.routeName);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return BugReporterOverlay(
      child: Scaffold(
        body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
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
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.login_rounded, size: 20),
                          SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              'Sign In with KB Account',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
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
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.phonelink_setup_rounded, size: 20),
                          SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              'Pair with Another Device',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!_isCheckingStatus) ...[
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () => _showSignInModal(isEnrollment: !_isEnrolled),
                        child: Text(!_isEnrolled
                            ? 'First time setup? Create Owner Account'
                            : 'Need a new account? Create KB Account'),
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
      ),
    );
  }
}
