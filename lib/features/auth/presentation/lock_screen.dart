import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/runtime.dart';
import '../../../app/theme.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/security/permissions.dart';
import '../../../core/security/pin_hasher.dart';
import '../../../shared/widgets/common.dart';
import '../../setup/application/demo_seed.dart';
import '../application/auth_service.dart';

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});
  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  StaffSummary? _selected;

  @override
  Widget build(BuildContext context) {
    final services = ref.watch(servicesProvider);
    final settings = ref.watch(settingsStreamProvider).value;
    final isDemo = ref.watch(runtimeProvider).mode == AppMode.demo;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (isDemo) const DemoBanner(),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock_outline, size: 40, color: AppColors.accent),
                        const SizedBox(height: 8),
                        Text(settings?.name ?? 'CaféDesk', style: t.headlineSmall, textAlign: TextAlign.center),
                        const SizedBox(height: 4),
                        Text(
                          _selected == null ? 'Who is using the till?' : 'Enter PIN for ${_selected!.name}',
                          style: t.bodyLarge,
                        ),
                        const SizedBox(height: 20),
                        if (_selected == null)
                          StreamView<List<StaffSummary>>(
                            stream: services.auth.watchStaff(),
                            builder: (context, staff) => Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              alignment: WrapAlignment.center,
                              children: [
                                for (final s in staff)
                                  SizedBox(
                                    width: 160,
                                    height: 96,
                                    child: OutlinedButton(
                                      onPressed: () => setState(() => _selected = s),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(_roleIcon(s.role)),
                                          const SizedBox(height: 4),
                                          Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                          Text(s.role.label, style: t.bodySmall),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          )
                        else
                          PinEntry(
                            key: ValueKey(_selected!.id),
                            onSubmit: (pin) async {
                              final actor = await services.auth.login(_selected!.id, pin);
                              ref.read(sessionProvider.notifier).login(actor);
                            },
                            onCancel: () => setState(() => _selected = null),
                          ),
                        const SizedBox(height: 16),
                        if (isDemo)
                          Text(
                            'Demo PINs — Owner ${DemoPins.owner} · Cashier ${DemoPins.cashier} · Kitchen ${DemoPins.kitchen}',
                            style: t.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                        TextButton(onPressed: () => _recover(context), child: const Text('Forgot the owner PIN?')),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _recover(BuildContext context) async {
    await showDialog<void>(context: context, builder: (_) => const _RecoveryDialog());
  }

  static IconData _roleIcon(StaffRole r) => switch (r) {
    StaffRole.owner => Icons.workspace_premium_outlined,
    StaffRole.cashier => Icons.point_of_sale_outlined,
    StaffRole.kitchen => Icons.soup_kitchen_outlined,
  };
}

class DemoBanner extends StatelessWidget {
  const DemoBanner({super.key});

  /// Has its own Material (it can sit above a Scaffold) and keeps clear of
  /// the status bar.
  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFFFE08A),
    child: SafeArea(
      bottom: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Text(
          'DEMO MODE — sample data only. Leave the demo from Settings to use your real restaurant.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: AppColors.ink),
        ),
      ),
    ),
  );
}

/// PIN pad with hidden digits. Works with touch and the keyboard.
class PinEntry extends StatefulWidget {
  const PinEntry({super.key, required this.onSubmit, this.onCancel, this.submitLabel = 'Unlock'});
  final Future<void> Function(String pin) onSubmit;
  final VoidCallback? onCancel;
  final String submitLabel;

  @override
  State<PinEntry> createState() => _PinEntryState();
}

class _PinEntryState extends State<PinEntry> {
  String _pin = '';
  String? _error;
  bool _busy = false;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_pin.length < 4 || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_pin);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _pin = '';
        });
      }
    }
  }

  void _digit(String d) {
    if (_pin.length >= 8) return;
    setState(() {
      _pin += d;
      _error = null;
    });
  }

  void _back() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final ch = event.character;
        if (ch != null && RegExp(r'^\d$').hasMatch(ch)) {
          _digit(ch);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.backspace) {
          _back();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
          unawaited(_submit());
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          widget.onCancel?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            label: 'PIN, ${_pin.length} digits entered',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < (_pin.length < 4 ? 4 : _pin.length); i++)
                  Container(
                    margin: const EdgeInsets.all(6),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < _pin.length ? AppColors.accent : Colors.transparent,
                      border: Border.all(color: AppColors.accent, width: 2),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 40,
            child: Center(
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : (_error == null
                        ? null
                        : Text(
                            _error!,
                            style: const TextStyle(color: AppColors.danger),
                            textAlign: TextAlign.center,
                          )),
            ),
          ),
          NumberPad(onDigit: _digit, onBackspace: _back, onDone: _submit, doneLabel: widget.submitLabel),
          if (widget.onCancel != null) TextButton(onPressed: widget.onCancel, child: const Text('Back')),
        ],
      ),
    );
  }
}

/// Owner enters their PIN to approve one action.
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

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Owner approval'),
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
                  onTap: () => setState(() => _owner = o),
                )
            else ...[
              Text(_owner!.name, style: Theme.of(context).textTheme.titleMedium),
              PinEntry(
                submitLabel: 'Approve',
                onSubmit: (pin) async {
                  final approval = await widget.auth.approveAsOwner(_owner!.id, pin);
                  if (context.mounted) Navigator.pop(context, approval);
                },
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
  );
}

class _RecoveryDialog extends ConsumerStatefulWidget {
  const _RecoveryDialog();
  @override
  ConsumerState<_RecoveryDialog> createState() => _RecoveryDialogState();
}

class _RecoveryDialogState extends ConsumerState<_RecoveryDialog> {
  final _code = TextEditingController();
  final _pin = TextEditingController();
  String? _ownerId;
  String? _newCode;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final services = ref.watch(servicesProvider);
    if (_newCode != null) {
      return AlertDialog(
        title: const Text('Owner PIN reset'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Your old recovery code no longer works. Write down this new one:'),
            const SizedBox(height: 12),
            SelectableText(_newCode!, style: const TextStyle(fontFamily: 'monospace', fontSize: 22)),
          ],
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
      );
    }
    return AlertDialog(
      title: const Text('Reset owner PIN'),
      content: SizedBox(
        width: 380,
        child: FutureView<List<StaffSummary>>(
          future: services.auth.activeOwners(),
          builder: (context, owners) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Use the recovery code you wrote down during setup. There is no master PIN. '
                'If the code is lost and no other owner can sign in, restore a backup whose owner PIN you know.',
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _ownerId,
                decoration: const InputDecoration(labelText: 'Owner'),
                items: [for (final o in owners) DropdownMenuItem(value: o.id, child: Text(o.name))],
                onChanged: (v) => setState(() => _ownerId = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _code,
                decoration: const InputDecoration(labelText: 'Recovery code'),
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pin,
                obscureText: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
                decoration: const InputDecoration(labelText: 'New PIN'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _busy || _ownerId == null
              ? null
              : () async {
                  setState(() => _busy = true);
                  try {
                    PinHasher.validatePin(_pin.text);
                    final code = await services.auth.resetOwnerPinWithRecoveryCode(_ownerId!, _code.text, _pin.text);
                    if (mounted) setState(() => _newCode = code);
                  } on Object catch (e) {
                    if (context.mounted) showError(context, e);
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
          child: const Text('Reset PIN'),
        ),
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
