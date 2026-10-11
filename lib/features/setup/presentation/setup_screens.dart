import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/security/password_hasher.dart';
import '../../../core/time/business_time.dart';
import '../../../shared/widgets/common.dart';
import '../application/setup_service.dart';

const separateInstallNotice =
    'One PC is the main till (POS): it keeps all orders, bills and reports. Waiter phones and kitchen displays '
    'connect to it over the café Wi-Fi (and through the cloud, if set up) and never keep their own sales. Two '
    'separate POS installs do NOT share data.';

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(
                  child: CircleAvatar(
                    radius: 36,
                    backgroundColor: AppColors.accent,
                    child: Icon(Icons.local_cafe, color: Colors.white, size: 36),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Welcome to CaféDesk Online',
                  style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text('What is this device for?', style: t.titleMedium, textAlign: TextAlign.center),
                const SizedBox(height: 22),
                _ChoiceCard(
                  icon: Icons.point_of_sale,
                  title: 'Main till (POS)',
                  text:
                      'The PC or tablet at the counter: orders, payments, bills and reports. You create the Admin '
                      'account here.',
                  action: 'Set up my restaurant',
                  primary: true,
                  onTap: () => ref.read(appControllerProvider.notifier).choosePos(),
                ),
                const SizedBox(height: 12),
                _ChoiceCard(
                  icon: Icons.phonelink_ring_outlined,
                  title: 'Waiter phone or kitchen screen',
                  text: 'Connects to the main till over the café Wi-Fi. The admin pairs it with a QR code.',
                  action: 'Connect to the till',
                  onTap: () => ref.read(appControllerProvider.notifier).chooseDeviceMode(),
                ),
                const SizedBox(height: 20),
                const _NoticeCard(icon: Icons.devices_other_outlined, text: separateInstallNotice),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.icon,
    required this.title,
    required this.text,
    required this.action,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String title;
  final String text;
  final String action;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(icon, size: 32, color: AppColors.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(title, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(text, style: t.bodyMedium),
              const SizedBox(height: 14),
              primary
                  ? FilledButton(onPressed: onTap, child: Text(action))
                  : FilledButton.tonal(onPressed: onTap, child: Text(action)),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xFFFFF7E6),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.warning),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    ),
  );
}

class SetupWizard extends ConsumerStatefulWidget {
  const SetupWizard({super.key});
  @override
  ConsumerState<SetupWizard> createState() => _SetupWizardState();
}

class _SetupWizardState extends ConsumerState<SetupWizard> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _taxId = TextEditingController();
  final _footer = TextEditingController(text: 'Thank you! Visit again.');
  final _prefix = TextEditingController(text: SetupService.generateReceiptPrefix());
  final _ownerName = TextEditingController();
  final _ownerEmail = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();
  String _timeZone = 'Asia/Kolkata';
  int _cutoff = 240;
  bool _busy = false;
  SetupResult? _result;

  @override
  void dispose() {
    for (final c in [
      _name,
      _address,
      _phone,
      _taxId,
      _footer,
      _prefix,
      _ownerName,
      _ownerEmail,
      _password,
      _password2,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final services = ref.read(servicesProvider);
    final r = await guard(
      context,
      () => services.setup.completeSetup(
        SetupInput(
          restaurantName: _name.text,
          address: _address.text,
          phone: _phone.text,
          taxRegistrationId: _taxId.text,
          timeZone: _timeZone,
          cutoffMinutes: _cutoff,
          receiptFooter: _footer.text,
          receiptPrefix: _prefix.text,
          ownerName: _ownerName.text,
          ownerEmail: _ownerEmail.text,
          ownerPassword: _password.text,
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = r;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_result != null) return _RecoveryCodeScreen(result: _result!);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Set up your restaurant')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _NoticeCard(icon: Icons.devices_other_outlined, text: separateInstallNotice),
                    const SizedBox(height: 16),
                    Text('Business', style: t.titleMedium),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _name,
                      decoration: const InputDecoration(labelText: 'Restaurant name *'),
                      validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _address,
                      decoration: const InputDecoration(labelText: 'Address'),
                      maxLines: 3,
                      minLines: 2,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phone,
                      decoration: const InputDecoration(labelText: 'Phone (optional)'),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _taxId,
                      decoration: const InputDecoration(
                        labelText: 'Tax registration ID (optional)',
                        helperText:
                            'Printed on receipts if entered. Taxes stay off until you configure them in Settings.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    const InputDecorator(
                      decoration: InputDecoration(labelText: 'Currency'),
                      child: Text('Indian rupee (INR)'),
                    ),
                    const SizedBox(height: 12),
                    TimeZoneField(value: _timeZone, onChanged: (v) => setState(() => _timeZone = v)),
                    const SizedBox(height: 12),
                    CutoffField(value: _cutoff, onChanged: (v) => setState(() => _cutoff = v)),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _footer,
                      decoration: const InputDecoration(labelText: 'Receipt footer'),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _prefix,
                      decoration: const InputDecoration(
                        labelText: 'Receipt number prefix',
                        helperText: 'Receipts look like ABC-000123. Use a different prefix on each device.',
                      ),
                      textCapitalization: TextCapitalization.characters,
                      validator: (v) {
                        try {
                          SetupService.validateReceiptPrefix(v ?? '');
                          return null;
                        } on Object catch (e) {
                          return errorText(e);
                        }
                      },
                    ),
                    const SizedBox(height: 24),
                    Text('Admin account', style: t.titleMedium),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _ownerName,
                      decoration: const InputDecoration(labelText: 'Admin name *'),
                      validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    EmailField(
                      controller: _ownerEmail,
                      label: 'Admin email *',
                      validator: (v) {
                        try {
                          PasswordHasher.normalizeEmail(v ?? '');
                          return null;
                        } on Object catch (e) {
                          return errorText(e);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    PasswordField(
                      controller: _password,
                      label: 'Admin password *',
                      helper: 'At least ${PasswordHasher.minPasswordLength} characters',
                      newPassword: true,
                      validator: (v) {
                        try {
                          PasswordHasher.validatePassword(v ?? '', email: _ownerEmail.text);
                          return null;
                        } on Object catch (e) {
                          return errorText(e);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    PasswordField(
                      controller: _password2,
                      label: 'Repeat password *',
                      newPassword: true,
                      validator: (v) => v != _password.text ? 'Passwords do not match' : null,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You sign in with this email and password. Only an admin can create accounts for other staff '
                      '(Staff screen). The email is just a sign-in name on this device: nothing is sent to it and '
                      'nothing goes online. Passwords control who can use the app; they do not encrypt the data, so '
                      'anyone with administrator access to this device could copy the database file.',
                      style: t.bodySmall,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Create restaurant'),
                    ),
                    const SizedBox(height: 24),
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

class _RecoveryCodeScreen extends ConsumerStatefulWidget {
  const _RecoveryCodeScreen({required this.result});
  final SetupResult result;
  @override
  ConsumerState<_RecoveryCodeScreen> createState() => _RecoveryCodeScreenState();
}

class _RecoveryCodeScreenState extends ConsumerState<_RecoveryCodeScreen> {
  bool _saved = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.key_outlined, size: 48, color: AppColors.accent),
                const SizedBox(height: 12),
                Text('Write down your admin recovery code', style: t.headlineSmall, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                const Text(
                  'If you forget the admin password, this code is the only way to reset it on this device. '
                  'There is no master password and no online recovery. Keep it somewhere safe and private. It will not be shown again '
                  '(an admin can create a new one later in Settings).',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: SelectableText(
                      widget.result.recoveryCode,
                      textAlign: TextAlign.center,
                      style: t.headlineMedium?.copyWith(fontFamily: 'monospace', letterSpacing: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Receipt prefix: ${widget.result.receiptPrefix}', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: _saved,
                  onChanged: (v) => setState(() => _saved = v ?? false),
                  title: const Text('I have written the recovery code down'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: !_saved
                      ? null
                      : () async {
                          ref.read(sessionProvider.notifier).login(widget.result.owner);
                          await ref.read(appControllerProvider.notifier).setupCompleted();
                        },
                  child: const Text('Continue'),
                ),
                const SizedBox(height: 12),
                Text(
                  'Next: add your menu (Menu → Import CSV or add items) and, if you have one, a receipt printer '
                  '(Settings → Printers). Billing works without a printer.',
                  style: t.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Searchable IANA time zone picker (bundled data, works offline).
class TimeZoneField extends StatelessWidget {
  const TimeZoneField({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    ensureTimeZonesLoaded();
    final zones = tz.timeZoneDatabase.locations.keys.toList()..sort();
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: value),
      optionsBuilder: (v) {
        final q = v.text.toLowerCase();
        return zones.where((z) => z.toLowerCase().contains(q)).take(30);
      },
      onSelected: onChanged,
      fieldViewBuilder: (context, controller, focus, onSubmit) => TextFormField(
        controller: controller,
        focusNode: focus,
        decoration: const InputDecoration(
          labelText: 'Time zone',
          helperText: 'Used for business days and report times',
        ),
        validator: (v) =>
            BusinessCalendar.isValidTimeZone((v ?? '').trim()) ? null : 'Choose a time zone from the list',
        onChanged: (v) {
          if (BusinessCalendar.isValidTimeZone(v.trim())) onChanged(v.trim());
        },
      ),
    );
  }
}

class CutoffField extends StatelessWidget {
  const CutoffField({super.key, required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<int>(
    isExpanded: true,
    initialValue: value,
    decoration: const InputDecoration(
      labelText: 'Business day ends at',
      helperText: 'Sales after midnight but before this time count for the previous day',
    ),
    items: [
      for (var h = 0; h < 12; h++)
        DropdownMenuItem(value: h * 60, child: Text('${formatCutoff(h * 60)}${h == 0 ? ' (midnight)' : ''}')),
    ],
    onChanged: (v) => v == null ? null : onChanged(v),
  );
}
