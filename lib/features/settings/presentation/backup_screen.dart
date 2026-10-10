import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../app/providers.dart';
import '../../../app/runtime.dart';
import '../../../app/theme.dart';
import '../../../core/backup/backup_service.dart';
import '../../../shared/widgets/common.dart';
import '../../auth/presentation/lock_screen.dart';
import '../../setup/application/setup_service.dart';
import '../application/settings_service.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});
  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  int _refresh = 0;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final services = ref.watch(servicesProvider);
    final rt = ref.watch(runtimeProvider);
    final settings = ref.watch(settingsStreamProvider).value;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Backup and restore')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            title: 'Automatic backups',
            subtitle: rt.mode == AppMode.demo ? 'Automatic backups are off in the demo.' : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  settings?.lastBackupAt == null
                      ? 'No backup has been made yet.'
                      : 'Last backup: ${formatLocalMs(settings!.lastBackupAt!)}',
                ),
                Text(
                  'Every ${settings?.backupIntervalHours ?? 24} h while CaféDesk is open (and soon after it starts, if one is due). '
                  'Keeps the last ${settings?.backupRetention ?? 14} automatic backups.',
                ),
                SelectableText('Folder: ${settings?.backupDirectory ?? rt.paths.backups.path}'),
                if (rt.lastBackupError != null)
                  Text(
                    'Last automatic backup failed: ${rt.lastBackupError}',
                    style: const TextStyle(color: AppColors.danger),
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      icon: _busy
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.backup),
                      label: const Text('Back up now'),
                      onPressed: _busy ? null : _backupNow,
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.tune),
                      label: const Text('Schedule and folder'),
                      onPressed: _schedule,
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.restore),
                      label: const Text('Restore from a file…'),
                      onPressed: _busy ? null : _restoreFromFile,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Card(
            color: Color(0xFFFFF7E6),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Keep a second copy somewhere else (USB drive, another computer). A backup stored only on this device '
                'is lost if the device is lost or fails. Backup files are NOT encrypted: anyone with the file can read your sales data.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Backups in the folder', style: t.titleMedium),
          FutureView<List<BackupFile>>(
            key: ValueKey(_refresh),
            future: services.backupService.listBackups(),
            builder: (context, files) => files.isEmpty
                ? const Padding(padding: EdgeInsets.all(16), child: Text('None yet'))
                : Column(
                    children: [
                      for (final f in files)
                        Card(
                          margin: const EdgeInsets.only(top: 8),
                          child: ListTile(
                            title: Text(
                              '${f.manifest.restaurantName} · ${formatLocalMs(f.manifest.createdAtUtc.millisecondsSinceEpoch)}',
                            ),
                            subtitle: Text(
                              '${f.manifest.reason} · ${f.manifest.billCount} bill(s) · ${(f.sizeBytes / 1024).ceil()} KB · from ${f.manifest.platform}',
                            ),
                            trailing: Wrap(
                              children: [
                                IconButton(
                                  tooltip: 'Save a copy elsewhere',
                                  icon: const Icon(Icons.save_alt),
                                  onPressed: () => _saveCopy(f),
                                ),
                                IconButton(
                                  tooltip: 'Restore this backup',
                                  icon: const Icon(Icons.restore),
                                  onPressed: () => _restoreBytes(File(f.path).readAsBytesSync(), f.path),
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
    );
  }

  Future<void> _backupNow() async {
    setState(() => _busy = true);
    final services = ref.read(servicesProvider);
    final f = await guard(context, () => services.backupService.createBackup(actor: requireActor(ref)));
    if (mounted) {
      setState(() {
        _busy = false;
        _refresh++;
      });
      if (f != null) showInfo(context, 'Backup saved: ${p.basename(f.path)}');
    }
  }

  Future<void> _saveCopy(BackupFile f) async {
    final bytes = await File(f.path).readAsBytes();
    if (!mounted) return;
    await guard(
      context,
      () => FilePicker.saveFile(fileName: p.basename(f.path), bytes: bytes, mimeType: 'application/zip'),
      success: 'Copy saved',
    );
  }

  Future<void> _schedule() async {
    final s = ref.read(settingsStreamProvider).value;
    if (s == null) return;
    var interval = s.backupIntervalHours;
    var retention = s.backupRetention;
    String? dir = s.backupDirectory;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) => AlertDialog(
          title: const Text('Backup schedule'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                isExpanded: true,
                initialValue: [1, 2, 4, 6, 12, 24, 48].contains(interval) ? interval : 24,
                decoration: const InputDecoration(labelText: 'Back up every'),
                items: [
                  for (final h in [1, 2, 4, 6, 12, 24, 48]) DropdownMenuItem(value: h, child: Text('$h hour(s)')),
                ],
                onChanged: (v) => setLocal(() => interval = v ?? interval),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                isExpanded: true,
                initialValue: [7, 14, 30, 60].contains(retention) ? retention : 14,
                decoration: const InputDecoration(labelText: 'Keep automatic backups'),
                items: [
                  for (final n in [7, 14, 30, 60]) DropdownMenuItem(value: n, child: Text('Last $n')),
                ],
                onChanged: (v) => setLocal(() => retention = v ?? retention),
              ),
              if (!Platform.isAndroid) ...[
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Folder'),
                  subtitle: Text(dir ?? 'Default (app data)'),
                  trailing: TextButton(
                    onPressed: () async {
                      final picked = await FilePicker.getDirectoryPath(
                        dialogTitle: 'Choose a backup folder (not OneDrive or a network share)',
                      );
                      if (picked != null) setLocal(() => dir = picked);
                    },
                    child: const Text('Change'),
                  ),
                ),
                if (dir != null)
                  TextButton(onPressed: () => setLocal(() => dir = null), child: const Text('Use default folder')),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok == true && mounted) {
      await guard(
        context,
        () => ref
            .read(servicesProvider)
            .settings
            .updateBackup(
              requireActor(ref),
              BackupSettingsInput(directory: dir, intervalHours: interval, retention: retention),
            ),
        success: 'Saved',
      );
      if (mounted) setState(() => _refresh++);
    }
  }

  Future<void> _restoreFromFile() async {
    final f = await FilePicker.pickFile(type: FileType.any);
    if (f == null || !mounted) return;
    final bytes = await f.readAsBytes();
    if (!mounted) return;
    await _restoreBytes(bytes, f.name);
  }

  Future<void> _restoreBytes(Uint8List bytes, String source) async {
    final services = ref.read(servicesProvider);
    final actor = requireActor(ref);
    setState(() => _busy = true);
    final insp = await guard(context, () => services.backupService.inspect(actor, bytes, sourcePath: source));
    if (mounted) setState(() => _busy = false);
    if (insp == null || !mounted) return;

    var newPrefix = insp.sameInstallation ? null : SetupService.generateReceiptPrefix();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) => AlertDialog(
          title: const Text('Replace all data with this backup?'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Restaurant: ${insp.restaurantName}'),
                Text('Backup date: ${formatLocalMs(insp.manifest.createdAtUtc.millisecondsSinceEpoch)}'),
                Text('Bills in backup: ${insp.billCount}'),
                Text('Made on: ${insp.manifest.platform} (app ${insp.manifest.appVersion})'),
                const SizedBox(height: 12),
                const Text(
                  'Everything currently on this device is replaced. This is not a merge. A safety backup of the current data is made first.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text('Print jobs from the backup are held for review and never print automatically.'),
                const SizedBox(height: 8),
                if (insp.sameInstallation)
                  const Text(
                    'This backup is from this device. Receipt numbers continue after the highest number already used here, '
                    'so no number is issued twice.',
                  )
                else ...[
                  const Text(
                    'This backup is from another device or installation.',
                    style: TextStyle(color: AppColors.warning),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: newPrefix != null,
                    onChanged: (v) =>
                        setLocal(() => newPrefix = v == true ? SetupService.generateReceiptPrefix() : null),
                    title: Text(
                      newPrefix == null
                          ? 'Keep the backup\'s receipt prefix (${insp.manifest.receiptPrefix})'
                          : 'Use a new receipt prefix on this device: $newPrefix',
                    ),
                    subtitle: const Text(
                      'Recommended if the other device keeps billing, so receipt numbers never clash.',
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Replace data'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) {
      await services.backupService.discardInspection(insp);
      return;
    }
    final approval = await requestOwnerApproval(
      context,
      ref,
      purpose: 'Enter the owner password to restore this backup.',
    );
    if (approval == null || !mounted) {
      await services.backupService.discardInspection(insp);
      return;
    }
    setState(() => _busy = true);
    final rt = ref.read(runtimeProvider);
    final outcome = await guard(
      context,
      () => services.backupService.restore(actor, insp, approval: approval, host: rt, newReceiptPrefix: newPrefix),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (outcome != null) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Restore complete'),
          content: Text(
            '${outcome.billCount} bill(s) restored. Your previous data was saved as '
            '${p.basename(outcome.preRestoreBackupPath)}. Please sign in again and review any held print jobs.',
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
        ),
      );
      await ref.read(appControllerProvider.notifier).reloadAfterRestore();
    } else {
      // The runtime rolled back and reopened the old database.
      await ref.read(appControllerProvider.notifier).reloadAfterRestore();
    }
  }
}
