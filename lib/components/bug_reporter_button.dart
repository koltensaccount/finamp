import 'package:finamp/services/kb_account_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BugReporterOverlay extends StatelessWidget {
  const BugReporterOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          child,
          Positioned(
            top: MediaQuery.paddingOf(context).top + 4,
            right: 8,
            child: const BugReporterButton(),
          ),
        ],
      ),
    );
  }
}

class BugReporterButton extends ConsumerStatefulWidget {
  const BugReporterButton({super.key});

  @override
  ConsumerState<BugReporterButton> createState() => _BugReporterButtonState();
}

class _BugReporterButtonState extends ConsumerState<BugReporterButton> {
  void _openBugReportDialog(BuildContext context) {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    String category = 'UI/Layout';
    bool isSubmitting = false;
    String? errorText;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final categories = ['UI/Layout', 'Playback', 'Identity', 'Books', 'Sync', 'Other'];

          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.bug_report_outlined, color: Color(0xFF007AFF), size: 22),
                SizedBox(width: 8),
                Text('Report an Issue', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Directly filed to AI-monitored task tracker with device diagnostics.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 6,
                    children: categories.map((cat) {
                      final selected = category == cat;
                      return ChoiceChip(
                        label: Text(cat, style: const TextStyle(fontSize: 12)),
                        selected: selected,
                        onSelected: (val) {
                          if (val) setDialogState(() => category = cat);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleController,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Summary / Title',
                      hintText: 'e.g. Mini player overlaps bottom bar',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Description / Steps (Optional)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 8),
                    Text(errorText!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: isSubmitting
                    ? null
                    : () async {
                        final title = titleController.text.trim();
                        if (title.isEmpty) {
                          setDialogState(() => errorText = 'Please enter a summary');
                          return;
                        }
                        setDialogState(() {
                          isSubmitting = true;
                          errorText = null;
                        });

                        try {
                          final service = ref.read(kbAccountServiceProvider);
                          final currentRoute = ModalRoute.of(context)?.settings.name ?? 'unknown';
                          await service.submitBugReport(
                            title: title,
                            description: descController.text.trim(),
                            category: category,
                            screen: currentRoute,
                          );

                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Bug report filed to AI tracker!'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } catch (e) {
                          setDialogState(() {
                            isSubmitting = false;
                            errorText = e.toString().replaceAll('Exception: ', '');
                          });
                        }
                      },
                child: isSubmitting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Submit Report'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Tooltip(
        message: 'Report an issue',
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _openBugReportDialog(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.08),
                width: 0.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.bug_report_outlined,
                  size: 14,
                  color: Theme.of(context).brightness == Brightness.dark ? Colors.white60 : Colors.black54,
                ),
                const SizedBox(width: 4),
                Text(
                  'Bug',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).brightness == Brightness.dark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
