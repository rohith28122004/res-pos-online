import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/security/password_hasher.dart';
import '../../../core/security/permissions.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/people.dart';
import '../application/auth_service.dart';

/// Sign in: tap your name, type your password. People who prefer can type
/// their email instead. There are no built-in accounts: the admin creates
/// everyone in Staff.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});
  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  late final Stream<List<StaffSummary>> _staff = ref.read(servicesProvider).auth.watchStaff();
  final _email = TextEditingController();
  final _password = TextEditingController();
  StaffSummary? _who;
  bool _useEmail = false;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _pick(StaffSummary? who, {bool useEmail = false}) => setState(() {
    _who = who;
    _useEmail = useEmail;
    _error = null;
    _password.clear();
  });

  Future<void> _signIn() async {
    if (_busy) return;
    final email = _who?.email ?? _email.text;
    if (email.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = _who == null ? 'Enter your email and password' : 'Enter your password');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final actor = await ref.read(servicesProvider).auth.login(email, _password.text);
      ref.read(sessionProvider.notifier).login(actor);
    } on Object catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) {
        _password.clear();
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsStreamProvider).value;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(
                    child: CircleAvatar(
                      radius: 34,
                      backgroundColor: AppColors.accent,
                      child: Icon(Icons.local_cafe, color: Colors.white, size: 34),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    settings?.name ?? 'CaféDesk Online',
                    style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Sign in to start',
                    style: t.bodyLarge?.copyWith(color: AppColors.ink.withValues(alpha: 0.7)),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: AutofillGroup(
                        child: StreamView<List<StaffSummary>>(
                          stream: _staff,
                          builder: (context, staff) {
                            final people = staff.where((s) => s.canSignIn).toList();
                            if (_who != null) return _passwordStep(_who!);
                            if (_useEmail || people.isEmpty) return _emailStep(canGoBack: people.isNotEmpty);
                            return _pickStep(people);
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => showDialog<void>(context: context, builder: (_) => const _RecoveryDialog()),
                    child: const Text('Forgot the admin password?'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pickStep(List<StaffSummary> people) {
    final t = Theme.of(context).textTheme;
    // The admin first, then cashiers, waiters and kitchen staff.
    final sorted = [...people]
      ..sort((a, b) {
        final byRole = a.role.index.compareTo(b.role.index);
        return byRole != 0 ? byRole : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Who is signing in?', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('Tap your name.', style: t.bodySmall),
        const SizedBox(height: 14),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 150,
            mainAxisExtent: scaledExtent(context, 128),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: sorted.length,
          itemBuilder: (context, i) => _PersonTile(person: sorted[i], onTap: () => _pick(sorted[i])),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          icon: const Icon(Icons.alternate_email, size: 18),
          label: const Text('Use email instead'),
          onPressed: () => _pick(null, useEmail: true),
        ),
      ],
    );
  }

  Widget _passwordStep(StaffSummary who) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            PersonAvatar(name: who.name, role: who.role, radius: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(who.name, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  RoleBadge(role: who.role),
                ],
              ),
            ),
            TextButton(onPressed: () => _pick(null), child: const Text('Not you?')),
          ],
        ),
        const SizedBox(height: 18),
        PasswordField(controller: _password, autofocus: true, onSubmitted: (_) => _signIn()),
        _errorText(),
        _signInButton(),
      ],
    );
  }

  Widget _emailStep({required bool canGoBack}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Sign in with email',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 14),
      EmailField(controller: _email, autofocus: true),
      const SizedBox(height: 12),
      PasswordField(controller: _password, onSubmitted: (_) => _signIn()),
      _errorText(),
      _signInButton(),
      if (canGoBack) ...[
        const SizedBox(height: 8),
        TextButton.icon(
          icon: const Icon(Icons.people_outline, size: 18),
          label: const Text('Choose my name instead'),
          onPressed: () => _pick(null),
        ),
      ],
    ],
  );

  Widget _errorText() => SizedBox(
    height: 40,
    child: Center(
      child: _error == null
          ? null
          : Text(
              _error!,
              style: const TextStyle(color: AppColors.danger),
              textAlign: TextAlign.center,
            ),
    ),
  );

  Widget _signInButton() => FilledButton(
    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
    onPressed: _busy ? null : _signIn,
    child: _busy
        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
        : const Text('Sign in'),
  );
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({required this.person, required this.onTap});
  final StaffSummary person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: Color(0xFFE6DED3)),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            PersonAvatar(name: person.name, role: person.role),
            const SizedBox(height: 8),
            Text(
              person.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            RoleBadge(role: person.role),
          ],
        ),
      ),
    ),
  );
}

/// Shown right after signing in with a password the owner chose: the person
/// picks their own before using the app.
class PasswordChangeRequiredScreen extends ConsumerStatefulWidget {
  const PasswordChangeRequiredScreen({super.key, required this.actor});
  final Actor actor;
  @override
  ConsumerState<PasswordChangeRequiredScreen> createState() => _PasswordChangeRequiredScreenState();
}

class _PasswordChangeRequiredScreenState extends ConsumerState<PasswordChangeRequiredScreen> {
  final _form = GlobalKey<FormState>();
  final _next = TextEditingController();
  final _repeat = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _next.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(servicesProvider).auth.chooseOwnPassword(widget.actor, _next.text);
      ref.read(sessionProvider.notifier).login(widget.actor.withPasswordChanged());
    } on Object catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Choose your password'),
      actions: [
        TextButton(onPressed: () => ref.read(sessionProvider.notifier).logout(), child: const Text('Sign out')),
      ],
    ),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Form(
            key: _form,
            child: AutofillGroup(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Hi ${widget.actor.name}. The admin set a starting password for you. '
                    'Choose your own now — only you should know it.',
                  ),
                  const SizedBox(height: 16),
                  PasswordField(
                    controller: _next,
                    label: 'New password',
                    helper: 'At least ${PasswordHasher.minPasswordLength} characters',
                    autofocus: true,
                    newPassword: true,
                    validator: _passwordRule,
                  ),
                  const SizedBox(height: 12),
                  PasswordField(
                    controller: _repeat,
                    label: 'Repeat new password',
                    newPassword: true,
                    validator: (v) => v != _next.text ? 'Passwords do not match' : null,
                    onSubmitted: (_) => _save(),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _busy ? null : _save, child: const Text('Save and continue')),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Form validator for a new password.
String? _passwordRule(String? v) {
  try {
    PasswordHasher.validatePassword(v ?? '');
    return null;
  } on AppException catch (e) {
    return e.message;
  }
}

/// Owner enters their password to approve one action.
Future<OwnerApproval?> requestOwnerApproval(BuildContext context, WidgetRef ref, {required String purpose}) async {
  final services = ref.read(servicesProvider);
  final owners = await services.auth.activeOwners();
  if (!context.mounted) return null;
  return showDialog<OwnerApproval>(
    context: context,
    builder: (c) => _ApprovalDialog(owners: owners, purpose: purpose, auth: services.auth),
  );
}

/// Calls [action] without approval first; if the service says owner
/// approval is needed (and the actor is not an owner), asks for it and
/// retries once.
Future<T?> withOwnerApproval<T>(
  BuildContext context,
  WidgetRef ref, {
  required String purpose,
  required Future<T> Function(OwnerApproval? approval) action,
  String? success,
}) async {
  try {
    final r = await action(null);
    if (success != null && context.mounted) showInfo(context, success);
    return r;
  } on ApprovalRequiredException catch (e) {
    if (!context.mounted) return null;
    final approval = await requestOwnerApproval(context, ref, purpose: '${e.message}\n\n$purpose');
    if (approval == null || !context.mounted) return null;
    return guard(context, () => action(approval), success: success);
  } on Object catch (e) {
    if (context.mounted) showError(context, e);
    return null;
  }
}

class _ApprovalDialog extends StatefulWidget {
  const _ApprovalDialog({required this.owners, required this.purpose, required this.auth});
  final List<StaffSummary> owners;
  final String purpose;
  final AuthService auth;
  @override
  State<_ApprovalDialog> createState() => _ApprovalDialogState();
}

class _ApprovalDialogState extends State<_ApprovalDialog> {
  late StaffSummary? _owner = widget.owners.length == 1 ? widget.owners.single : null;
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _approve() async {
    if (_owner == null || _busy || _password.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final approval = await widget.auth.approveAsOwner(_owner!.id, _password.text);
      if (mounted) Navigator.pop(context, approval);
    } on Object catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) {
        _password.clear();
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Admin approval'),
    content: SingleChildScrollView(
      child: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.purpose, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            if (_owner == null)
              for (final o in widget.owners)
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(o.name),
                  subtitle: o.email == null ? null : Text(o.email!),
                  onTap: () => setState(() => _owner = o),
                )
            else ...[
              Text(_owner!.name, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              PasswordField(
                controller: _password,
                label: 'Admin password',
                autofocus: true,
                onSubmitted: (_) => _approve(),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppColors.danger),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      if (_owner != null) FilledButton(onPressed: _busy ? null : _approve, child: const Text('Approve')),
    ],
  );
}

class _RecoveryDialog extends ConsumerStatefulWidget {
  const _RecoveryDialog();
  @override
  ConsumerState<_RecoveryDialog> createState() => _RecoveryDialogState();
}

class _RecoveryDialogState extends ConsumerState<_RecoveryDialog> {
  final _form = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  late final Future<List<StaffSummary>> _owners = ref.read(servicesProvider).auth.activeOwners();
  String? _ownerId;
  String? _newCode;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    _email.dispose();
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _reset() async {
    if (_busy || _ownerId == null || !_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final code = await ref
          .read(servicesProvider)
          .auth
          .resetOwnerPasswordWithRecoveryCode(_ownerId!, _code.text, _password.text, email: _email.text);
      if (mounted) setState(() => _newCode = code);
    } on Object catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_newCode != null) {
      return AlertDialog(
        title: const Text('Admin password reset'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Sign in with your email and new password. Your old recovery code no longer works — '
              'write down this new one:',
            ),
            const SizedBox(height: 12),
            SelectableText(_newCode!, style: const TextStyle(fontFamily: 'monospace', fontSize: 22)),
          ],
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
      );
    }
    return AlertDialog(
      title: const Text('Reset admin password'),
      content: SizedBox(
        width: 380,
        child: FutureView<List<StaffSummary>>(
          future: _owners,
          builder: (context, owners) => Form(
            key: _form,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Use the recovery code you wrote down during setup. There is no master password. '
                    'If the code is lost and no other admin can sign in, restore a backup whose admin password '
                    'you know.',
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _ownerId,
                    decoration: const InputDecoration(labelText: 'Admin'),
                    items: [for (final o in owners) DropdownMenuItem(value: o.id, child: Text(o.name))],
                    onChanged: (v) => setState(() {
                      _ownerId = v;
                      _email.text = owners.firstWhere((o) => o.id == v).email ?? '';
                    }),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _code,
                    decoration: const InputDecoration(labelText: 'Recovery code'),
                    textCapitalization: TextCapitalization.characters,
                    validator: (v) => (v ?? '').trim().isEmpty ? 'Enter the recovery code' : null,
                  ),
                  const SizedBox(height: 12),
                  EmailField(
                    controller: _email,
                    label: 'Admin email (for signing in)',
                    validator: (v) {
                      try {
                        PasswordHasher.normalizeEmail(v ?? '');
                        return null;
                      } on AppException catch (e) {
                        return e.message;
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  PasswordField(
                    controller: _password,
                    label: 'New password',
                    newPassword: true,
                    validator: _passwordRule,
                  ),
                  const SizedBox(height: 12),
                  PasswordField(
                    controller: _repeat,
                    label: 'Repeat new password',
                    newPassword: true,
                    validator: (v) => v != _password.text ? 'Passwords do not match' : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _busy || _ownerId == null ? null : _reset, child: const Text('Reset password')),
      ],
    );
  }
}

/// Locks the app after the configured idle time. Open orders are already
/// saved, so locking never loses work.
class InactivityGuard extends ConsumerStatefulWidget {
  const InactivityGuard({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<InactivityGuard> createState() => _InactivityGuardState();
}

class _InactivityGuardState extends ConsumerState<InactivityGuard> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    _reset();
  }

  @override
  void dispose() {
    _timer?.cancel();
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent e) {
    _reset();
    return false;
  }

  void _reset() {
    _timer?.cancel();
    final minutes = ref.read(settingsStreamProvider).value?.lockTimeoutMinutes ?? 5;
    _timer = Timer(Duration(minutes: minutes), () {
      if (mounted) ref.read(sessionProvider.notifier).logout();
    });
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) => _reset(),
    onPointerSignal: (_) => _reset(),
    child: widget.child,
  );
}
