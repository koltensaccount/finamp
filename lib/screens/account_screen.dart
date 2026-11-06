import 'login_screen.dart';
import 'package:finamp/components/finamp_app_bar_back_button.dart';
import 'package:finamp/services/kb_account_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  static const routeName = '/account';

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  List<Map<String, dynamic>> _devices = [];
  bool _isLoadingDevices = true;
  String? _deviceError;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    setState(() { _isLoadingDevices = true; _deviceError = null; });
    final service = ref.read(kbAccountServiceProvider);
    try {
      final list = await service.listDevices();
      if (mounted) {
        setState(() {
          _devices = list;
          _isLoadingDevices = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _deviceError = 'Could not verify your account connection. Sign in again if your session expired, or retry when the server is available.';
          _isLoadingDevices = false;
        });
      }
    }
  }

  void _showPairDeviceDialog() {
    final codeController = TextEditingController();
    bool isApproving = false;
    String? dialogError;
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('Pair New Device'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Enter the 6-digit code shown on your other device to connect it instantly to your KB Account.',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: codeController,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 28, letterSpacing: 8, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '000000',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                if (dialogError != null) ...[
                  const SizedBox(height: 8),
                  Text(dialogError!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: isApproving ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: isApproving
                    ? null
                    : () async {
                        final code = codeController.text.trim();
                        if (code.length < 6) {
                          setDialogState(() => dialogError = 'Please enter a 6-digit code');
                          return;
                        }
                        setDialogState(() {
                          isApproving = true;
                          dialogError = null;
                        });
                        try {
                          final service = ref.read(kbAccountServiceProvider);
                          final res = await service.approvePairing(code);
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                            scaffoldMessenger.showSnackBar(
                              SnackBar(
                                content: Text('Device paired successfully: ${res['device_name'] ?? 'Device'}'),
                                backgroundColor: Colors.green,
                              ),
                            );
                            await _loadDevices();
                          }
                        } catch (e) {
                          setDialogState(() {
                            isApproving = false;
                            dialogError = e.toString().replaceAll('Exception: ', '');
                          });
                        }
                      },
                child: isApproving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Pair Device'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showRenameDialog(String deviceId, String currentName) {
    final controller = TextEditingController(text: currentName);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Device'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Device Name',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                Navigator.pop(ctx);
                final service = ref.read(kbAccountServiceProvider);
                await service.renameDevice(deviceId, newName);
                await _loadDevices();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmRevokeDevice(String deviceId, String name) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke Device?'),
        content: Text('Are you sure you want to sign out and disconnect "$name"? It will lose access until re-paired.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              final service = ref.read(kbAccountServiceProvider);
              await service.revokeDevice(deviceId);
              await _loadDevices();
            },
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final service = ref.watch(kbAccountServiceProvider);
    final session = service.currentSession;

    if (session == null) {
      return Scaffold(
        appBar: AppBar(leading: const FinampAppBarBackButton(), title: const Text('KB Account')),
        body: Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Connect your KB account'),
            const SizedBox(height: 12),
            const Text('Your downloaded music remains available.'),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context, rootNavigator: true).pushNamed(LoginScreen.routeName),
              child: const Text('Sign In with KB Account'),
            ),
          ]),
        )),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: const FinampAppBarBackButton(),
        title: const Text('KB Account'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          if (_deviceError != null) ...[
            Text(_deviceError!),
            Wrap(spacing: 12, children: [
              FilledButton(onPressed: () => Navigator.of(context, rootNavigator: true).pushNamed(LoginScreen.routeName), child: const Text('Sign In Again')),
              TextButton(onPressed: _loadDevices, child: const Text('Retry')),
            ]),
            const SizedBox(height: 16),
          ],
          // User Card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E22) : const Color(0xFFF2F2F7),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: const Color(0xFF007AFF),
                  child: Text(
                    (session?.displayName.isNotEmpty ?? false) ? session!.displayName[0].toUpperCase() : 'K',
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session?.displayName ?? 'Kolten',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '@${session?.username ?? 'kolten'}',
                        style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Connected to KB Server',
                            style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Pair New Device Button
          FilledButton.icon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.phonelink_setup_rounded),
            label: const Text('Pair New Device (Enter 6-Digit Code)', style: TextStyle(fontSize: 15)),
            onPressed: _showPairDeviceDialog,
          ),
          const SizedBox(height: 28),

          // Devices Section Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'REGISTERED DEVICES',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: _loadDevices,
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Devices List
          if (_isLoadingDevices)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else if (_devices.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E22) : const Color(0xFFF2F2F7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('No devices registered.'),
            )
          else
            ..._devices.map((d) {
              final isCurrent = d['is_current'] == true;
              final dName = d['device_name'] as String? ?? 'Device';
              final platform = (d['platform'] as String? ?? '').toLowerCase();
              final deviceId = d['id'] as String? ?? '';

              IconData icon = Icons.devices_rounded;
              if (platform.contains('mac') || platform.contains('darwin')) {
                icon = Icons.laptop_mac_rounded;
              } else if (platform.contains('ios') || platform.contains('iphone')) {
                icon = Icons.phone_iphone_rounded;
              } else if (platform.contains('ipad')) {
                icon = Icons.tablet_mac_rounded;
              } else if (platform.contains('android')) {
                icon = Icons.phone_android_rounded;
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E22) : const Color(0xFFF2F2F7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: Icon(icon, color: isCurrent ? Colors.blue : null),
                  title: Row(
                    children: [
                      Flexible(child: Text(dName, style: const TextStyle(fontWeight: FontWeight.w600))),
                      if (isCurrent) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'This Device',
                            style: TextStyle(color: Colors.blue, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    '${d['platform'] ?? 'Unknown'} • Active',
                    style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 13),
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (val) {
                      if (val == 'rename') {
                        _showRenameDialog(deviceId, dName);
                      } else if (val == 'revoke') {
                        _confirmRevokeDevice(deviceId, dName);
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(value: 'rename', child: Text('Rename')),
                      if (!isCurrent)
                        const PopupMenuItem(
                          value: 'revoke',
                          child: Text('Revoke Access', style: TextStyle(color: Colors.red)),
                        ),
                    ],
                  ),
                ),
              );
            }),

          const SizedBox(height: 32),

          // Sign Out Buttons
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign Out of This Device'),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Sign Out?'),
                  content: const Text('You will need to sign in or pair again to access your music and books.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign Out')),
                  ],
                ),
              );
              if (confirm ?? false) {
                await service.logout();
                if (context.mounted) {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                }
              }
            },
          ),
          const SizedBox(height: 10),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Sign Out of All Devices?'),
                  content: const Text('This will invalidate all sessions across all your Macs, iPads, and phones.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Sign Out All'),
                    ),
                  ],
                ),
              );
              if (confirm ?? false) {
                await service.logout(all: true);
                if (context.mounted) {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                }
              }
            },
            child: const Text('Sign Out of All Devices'),
          ),
        ],
      ),
    );
  }
}
