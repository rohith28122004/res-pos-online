import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/security/password_hasher.dart';
import '../../../core/security/permissions.dart';
import '../../../shared/widgets/common.dart';
import '../application/auth_service.dart';

/// Owner-only: create sign-in accounts (email + password) and manage them.
class StaffScreen extends ConsumerWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(servicesProvider);
    final actor = requireActor(ref);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Create account'),
        onPressed: () => _create(context, ref),
      ),
      body: StreamView<List<StaffSummary>>(
        stream: services.auth.watchStaff(includeDisabled: true),
        builder: (context, staff) => ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Everyone signs in with their email and password. Only an owner creates accounts; a new person '
                'chooses their own password the first time they sign in.\n'
                'Owner: everything. Cashier: orders, payments, bills, reprints, own shift, expenses. '
                'Kitchen: kitchen tickets only. Keep at least two owners so one can reset the other\'s password.',
              ),
            ),
            for (final s in staff)
              ListTile(
                leading: Icon(s.disabled ? Icons.person_off_outlined : Icons.person_outline),
                title: Text(s.name, style: s.disabled ? const TextStyle(decoration: TextDecoration.lineThrough) : null),
                subtitle: Text(
                  [
                    s.role.label,
                    s.email ?? 'no email — cannot sign in',
                    if (s.email != null && !s.hasPassword) 'no password — cannot sign in',
                    if (s.mustChangePassword) 'will choose a password at next sign-in',
                    if (s.disabled) 'disabled',
                  ].join(' · '),
                ),
                trailing: PopupMenuButton<String>(
                  tooltip: 'Options',
                  onSelected: (v) async {
                    switch (v) {
                      case 'rename':
                        final name = await askText(context, title: 'Rename', initial: s.name);
                        if (name != null && name.isNotEmpty && context.mounted) {
                          await guard(context, () => services.auth.updateStaff(actor, s.id, name: name));
                        }
                      case 'email':
                        final email = await askText(
                          context,
                          title: 'Email for ${s.name}',
                          label: 'Email',
                          initial: s.email ?? '',
                          maxLength: 254,
                          keyboard: TextInputType.emailAddress,
                        );
                        if (email != null && email.isNotEmpty && context.mounted) {
                          await guard(
                            context,
                            () => services.auth.updateStaff(actor, s.id, email: email),
                            success: 'Email saved',
                          );
                        }
                      case 'password':
                        final own = s.id == actor.staffId;
                        final password = await askNewPassword(
                          context,
                          title: 'New password for ${s.name}',
                          message: own ? null : '${s.name} will choose their own password at the next sign-in.',
                        );
                        if (password != null && context.mounted) {
                          await guard(
                            context,
                            () => services.auth.resetPassword(actor, s.id, password),
                            success: 'Password set',
                          );
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
                    PopupMenuItem(value: 'email', child: Text(s.email == null ? 'Set email' : 'Change email')),
                    PopupMenuItem(value: 'password', child: Text(s.hasPassword ? 'Reset password' : 'Set password')),
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

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final created = await showDialog<bool>(context: context, builder: (_) => const _CreateAccountDialog());
    if (created == true && context.mounted) showInfo(context, 'Account created');
  }
}

class _CreateAccountDialog extends ConsumerStatefulWidget {
  const _CreateAccountDialog();
  @override
  ConsumerState<_CreateAccountDialog> createState() => _CreateAccountDialogState();
}

class _CreateAccountDialogState extends ConsumerState<_CreateAccountDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  var _role = StaffRole.cashier;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(servicesProvider)
          .auth
          .createStaff(requireActor(ref), name: _name.text, email: _email.text, role: _role, password: _password.text);
      if (mounted) Navigator.pop(context, true);
    } on Object catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Create account'),
    content: SizedBox(
      width: 380,
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                maxLength: 60,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a name' : null,
              ),
              EmailField(controller: _email, validator: _emailRule),
              const SizedBox(height: 12),
              DropdownButtonFormField<StaffRole>(
                isExpanded: true,
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: [for (final r in StaffRole.values) DropdownMenuItem(value: r, child: Text(r.label))],
                onChanged: (v) => setState(() => _role = v ?? _role),
              ),
              const SizedBox(height: 12),
              PasswordField(
                controller: _password,
                label: 'Starting password',
                helper: 'Tell them in person. They choose their own when they first sign in.',
                newPassword: true,
                validator: (v) => _passwordRule(v, email: _email.text),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
      FilledButton(onPressed: _busy ? null : _save, child: const Text('Create')),
    ],
  );
}

String? _emailRule(String? v) {
  try {
    PasswordHasher.normalizeEmail(v ?? '');
    return null;
  } on AppException catch (e) {
    return e.message;
  }
}

String? _passwordRule(String? v, {String? email}) {
  try {
    PasswordHasher.validatePassword(v ?? '', email: email);
    return null;
  } on AppException catch (e) {
    return e.message;
  }
}

/// Asks for a new password twice. Returns null when cancelled.
Future<String?> askNewPassword(BuildContext context, {required String title, String? message}) async {
  final form = GlobalKey<FormState>();
  final a = TextEditingController();
  final b = TextEditingController();
  final r = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 380,
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(message)),
              PasswordField(
                controller: a,
                label: 'New password',
                helper: 'At least ${PasswordHasher.minPasswordLength} characters',
                autofocus: true,
                newPassword: true,
                validator: _passwordRule,
              ),
              const SizedBox(height: 12),
              PasswordField(
                controller: b,
                label: 'Repeat password',
                newPassword: true,
                validator: (v) => v != a.text ? 'Passwords do not match' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (form.currentState!.validate()) Navigator.pop(c, a.text);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
  a.dispose();
  b.dispose();
  return r;
}

Future<void> showChangePasswordDialog(BuildContext context, WidgetRef ref) async {
  final form = GlobalKey<FormState>();
  final current = TextEditingController();
  final next = TextEditingController();
  final repeat = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Change my password'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PasswordField(controller: current, label: 'Current password', autofocus: true),
              const SizedBox(height: 12),
              PasswordField(
                controller: next,
                label: 'New password',
                helper: 'At least ${PasswordHasher.minPasswordLength} characters',
                newPassword: true,
                validator: _passwordRule,
              ),
              const SizedBox(height: 12),
              PasswordField(
                controller: repeat,
                label: 'Repeat new password',
                newPassword: true,
                validator: (v) => v != next.text ? 'Passwords do not match' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (form.currentState!.validate()) Navigator.pop(c, true);
          },
          child: const Text('Change password'),
        ),
      ],
    ),
  );
  if (ok == true && context.mounted) {
    final services = ref.read(servicesProvider);
    await guard(
      context,
      () => services.auth.changeOwnPassword(requireActor(ref), current.text, next.text),
      success: 'Password changed',
    );
  }
  current.dispose();
  next.dispose();
  repeat.dispose();
}
