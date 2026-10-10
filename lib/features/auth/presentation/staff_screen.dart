import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/security/permissions.dart';
import '../../../core/security/pin_hasher.dart';
import '../../../shared/widgets/common.dart';
import '../application/auth_service.dart';

class StaffScreen extends ConsumerWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(servicesProvider);
    final actor = requireActor(ref);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Add staff'),
        onPressed: () => _add(context, ref),
      ),
      body: StreamView<List<StaffSummary>>(
        stream: services.auth.watchStaff(includeDisabled: true),
        builder: (context, staff) => ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Owner: everything. Cashier: orders, payments, bills, reprints, own shift, expenses. '
                'Kitchen: kitchen tickets only. Keep at least two owners so one can reset the other\'s PIN.',
              ),
            ),
            for (final s in staff)
              ListTile(
                leading: Icon(s.disabled ? Icons.person_off_outlined : Icons.person_outline),
                title: Text(s.name, style: s.disabled ? const TextStyle(decoration: TextDecoration.lineThrough) : null),
                subtitle: Text('${s.role.label}${s.disabled ? ' · disabled' : ''}'),
                trailing: PopupMenuButton<String>(
                  tooltip: 'Options',
                  onSelected: (v) async {
                    switch (v) {
                      case 'rename':
                        final name = await askText(context, title: 'Rename', initial: s.name);
                        if (name != null && name.isNotEmpty && context.mounted) {
                          await guard(context, () => services.auth.updateStaff(actor, s.id, name: name));
                        }
                      case 'pin':
                        final pin = await _askPin(context, 'New PIN for ${s.name}');
                        if (pin != null && context.mounted) {
                          await guard(context, () => services.auth.resetPin(actor, s.id, pin), success: 'PIN changed');
                        }
                      case 'disable':
                        await guard(context, () => services.auth.updateStaff(actor, s.id, disabled: !s.disabled));
                      default:
                        if (v.startsWith('role:')) {
                          final role = StaffRole.parse(v.substring(5));
                          await guard(context, () => services.auth.updateStaff(actor, s.id, role: role));
                        }
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'rename', child: Text('Rename')),
                    const PopupMenuItem(value: 'pin', child: Text('Set PIN')),
                    for (final r in StaffRole.values)
                      if (r != s.role) PopupMenuItem(value: 'role:${r.name}', child: Text('Make ${r.label}')),
                    PopupMenuItem(value: 'disable', child: Text(s.disabled ? 'Enable' : 'Disable')),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final pin = TextEditingController();
    var role = StaffRole.cashier;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) => AlertDialog(
          title: const Text('Add staff'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                maxLength: 60,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              DropdownButtonFormField<StaffRole>(
                isExpanded: true,
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: [for (final r in StaffRole.values) DropdownMenuItem(value: r, child: Text(r.label))],
                onChanged: (v) => setLocal(() => role = v ?? role),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pin,
                obscureText: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
                decoration: const InputDecoration(labelText: 'PIN (4–8 digits)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Add')),
          ],
        ),
      ),
    );
    if (ok == true && context.mounted) {
      final services = ref.read(servicesProvider);
      await guard(
        context,
        () => services.auth.createStaff(requireActor(ref), name: name.text, role: role, pin: pin.text),
        success: 'Staff member added',
      );
    }
    name.dispose();
    pin.dispose();
  }
}

Future<String?> _askPin(BuildContext context, String title) async {
  final a = TextEditingController();
  final b = TextEditingController();
  String? error;
  final r = await showDialog<String>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setLocal) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (ctrl, label) in [(a, 'New PIN'), (b, 'Repeat PIN')])
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: ctrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
                  decoration: InputDecoration(labelText: label),
                ),
              ),
            if (error != null) Text(error!, style: const TextStyle(color: AppColors.danger)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              try {
                PinHasher.validatePin(a.text);
                if (a.text != b.text) throw const FormatException('PINs do not match');
                Navigator.pop(c, a.text);
              } on Object catch (e) {
                setLocal(() => error = e is FormatException ? e.message : errorText(e));
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  a.dispose();
  b.dispose();
  return r;
}

Future<void> showChangePinDialog(BuildContext context, WidgetRef ref) async {
  final current = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Change my PIN'),
      content: TextField(
        controller: current,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
        decoration: const InputDecoration(labelText: 'Current PIN'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Next')),
      ],
    ),
  );
  if (ok != true || !context.mounted) {
    current.dispose();
    return;
  }
  final next = await _askPin(context, 'New PIN');
  if (next != null && context.mounted) {
    final services = ref.read(servicesProvider);
    await guard(
      context,
      () => services.auth.changeOwnPin(requireActor(ref), current.text, next),
      success: 'PIN changed',
    );
  }
  current.dispose();
}
