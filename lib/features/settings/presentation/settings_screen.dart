import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/app_info.dart';
import '../../../core/database/app_database.dart';
import '../../../core/money/money.dart';
import '../../../core/pricing/tax.dart';
import '../../../core/time/business_time.dart';
import '../../../shared/widgets/common.dart';
import '../../audit/presentation/audit_screen.dart';
import '../../setup/presentation/setup_screens.dart';
import '../../tables/presentation/tables_screen.dart';
import '../application/settings_service.dart';
import '../../devices/presentation/connected_devices_screen.dart';
import 'backup_screen.dart';
import 'printers_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void open(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    return ListView(
      children: [
        const _KitchenSwitch(),
        const Divider(),
        _tile(
          Icons.storefront_outlined,
          'Business details',
          'Name, address, receipt header and footer',
          () => open(const BusinessSettingsScreen()),
        ),
        _tile(
          Icons.schedule_outlined,
          'Day, time zone and lock',
          'Business day cutoff, auto-lock, automatic printing',
          () => open(const OperationsSettingsScreen()),
        ),
        _tile(
          Icons.percent_outlined,
          'Discounts, charges and rounding',
          'Cashier discount limit, service and delivery charges',
          () => open(const PricingSettingsScreen()),
        ),
        _tile(
          Icons.receipt_outlined,
          'Taxes',
          'Tax profiles (off until you set them up)',
          () => open(const TaxProfilesScreen()),
        ),
        _tile(
          Icons.phonelink_ring_outlined,
          'Connected devices',
          'Waiter phones, kitchen displays and the cloud relay',
          () => open(const ConnectedDevicesScreen()),
        ),
        _tile(
          Icons.print_outlined,
          'Printers',
          'Receipt and kitchen printers, test prints',
          () => open(const PrintersScreen()),
        ),
        _tile(
          Icons.table_restaurant_outlined,
          'Tables',
          'Add, rename or archive tables',
          () => open(const TablesAdminScreen()),
        ),
        _tile(
          Icons.backup_outlined,
          'Backup and restore',
          'Scheduled backups, save a copy, restore from a file',
          () => open(const BackupScreen()),
        ),
        _tile(Icons.history_outlined, 'Audit trail', 'Who did what and when', () => open(const AuditScreen())),
        _tile(
          Icons.key_outlined,
          'Admin recovery code',
          'Create a new code if the old one is lost',
          () => _recovery(context, ref),
        ),
        const Divider(),
        _tile(
          Icons.info_outline,
          'About and data',
          'Where data is stored, what passwords protect',
          () => open(const AboutScreen()),
        ),
      ],
    );
  }

  Widget _tile(IconData icon, String title, String subtitle, VoidCallback onTap) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );

  Future<void> _recovery(BuildContext context, WidgetRef ref) async {
    final ok = await confirm(
      context,
      title: 'Create a new recovery code?',
      message: 'The old recovery code will stop working.',
      confirmLabel: 'Create',
    );
    if (!ok || !context.mounted) return;
    final services = ref.read(servicesProvider);
    final code = await guard(context, () => services.auth.regenerateRecoveryCode(requireActor(ref)));
    if (code == null || !context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('New admin recovery code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Write this down and keep it private. It is shown only once.'),
            const SizedBox(height: 12),
            SelectableText(code, style: const TextStyle(fontFamily: 'monospace', fontSize: 22)),
          ],
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Done'))],
      ),
    );
  }
}

/// Kitchen on/off. Off: no kitchen screen; waiters prepare orders and mark
/// them ready themselves.
class _KitchenSwitch extends ConsumerWidget {
  const _KitchenSwitch();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(settingsStreamProvider).value?.kitchenEnabled ?? true;
    return SwitchListTile(
      secondary: Icon(on ? Icons.soup_kitchen_outlined : Icons.no_food_outlined),
      title: const Text('Kitchen'),
      subtitle: Text(
        on
            ? 'On: orders go to the kitchen screen; the kitchen marks them ready.'
            : 'Off: no kitchen screen. Waiters prepare orders and mark them ready.',
      ),
      value: on,
      onChanged: (v) async {
        if (!v &&
            !await confirm(
              context,
              title: 'Switch the kitchen off?',
              message:
                  'Orders will no longer go to a kitchen screen. Waiters see them under "To prepare" and mark '
                  'them ready. Kitchen displays stop showing new orders. You can switch it back on any time.',
              confirmLabel: 'Switch off',
            )) {
          return;
        }
        if (!context.mounted) return;
        await guard(
          context,
          () => ref.read(servicesProvider).settings.setKitchenEnabled(requireActor(ref), enabled: v),
          success: v ? 'Kitchen switched on' : 'Kitchen switched off',
        );
      },
    );
  }
}

/// Shared scaffold for a settings form backed by the settings row.
class _SettingsPage extends ConsumerWidget {
  const _SettingsPage({required this.title, required this.builder});
  final String title;
  final Widget Function(BuildContext context, RestaurantSettingsRow s) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsStreamProvider);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: s.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e),
        data: (row) => row == null
            ? const LoadingView()
            : Center(
                child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: builder(context, row)),
              ),
      ),
    );
  }
}

class BusinessSettingsScreen extends StatelessWidget {
  const BusinessSettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => _SettingsPage(
    title: 'Business details',
    builder: (context, s) => _BusinessForm(s: s),
  );
}

class _BusinessForm extends ConsumerStatefulWidget {
  const _BusinessForm({required this.s});
  final RestaurantSettingsRow s;
  @override
  ConsumerState<_BusinessForm> createState() => _BusinessFormState();
}

class _BusinessFormState extends ConsumerState<_BusinessForm> {
  late final _name = TextEditingController(text: widget.s.name);
  late final _address = TextEditingController(text: widget.s.address);
  late final _phone = TextEditingController(text: widget.s.phone ?? '');
  late final _taxId = TextEditingController(text: widget.s.taxRegistrationId ?? '');
  late final _header = TextEditingController(text: widget.s.receiptHeader ?? '');
  late final _footer = TextEditingController(text: widget.s.receiptFooter);

  @override
  void dispose() {
    for (final c in [_name, _address, _phone, _taxId, _header, _footer]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      TextField(
        controller: _name,
        decoration: const InputDecoration(labelText: 'Restaurant name'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _address,
        maxLines: 3,
        decoration: const InputDecoration(labelText: 'Address'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _phone,
        decoration: const InputDecoration(labelText: 'Phone'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _taxId,
        decoration: const InputDecoration(labelText: 'Tax registration ID (optional)'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _header,
        decoration: const InputDecoration(labelText: 'Extra receipt header line (optional)'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _footer,
        maxLines: 2,
        decoration: const InputDecoration(labelText: 'Receipt footer'),
      ),
      const SizedBox(height: 8),
      const Text('Changes apply to new bills. Old receipts always reprint exactly as they were.'),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: () async {
          if (!await confirm(
            context,
            title: 'Save business details?',
            message: 'This is recorded in the audit trail.',
          )) {
            return;
          }
          if (!context.mounted) return;
          await guard(
            context,
            () => ref
                .read(servicesProvider)
                .settings
                .updateBusinessDetails(
                  requireActor(ref),
                  BusinessDetailsInput(
                    name: _name.text,
                    address: _address.text,
                    phone: _phone.text,
                    taxRegistrationId: _taxId.text,
                    receiptHeader: _header.text,
                    receiptFooter: _footer.text,
                  ),
                ),
            success: 'Saved',
          );
        },
        child: const Text('Save'),
      ),
    ],
  );
}

class OperationsSettingsScreen extends StatelessWidget {
  const OperationsSettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => _SettingsPage(
    title: 'Day, time zone and lock',
    builder: (context, s) => _OperationsForm(s: s),
  );
}

class _OperationsForm extends ConsumerStatefulWidget {
  const _OperationsForm({required this.s});
  final RestaurantSettingsRow s;
  @override
  ConsumerState<_OperationsForm> createState() => _OperationsFormState();
}

class _OperationsFormState extends ConsumerState<_OperationsForm> {
  late String _tz = widget.s.timeZone;
  late int _cutoff = widget.s.cutoffMinutes;
  late int _lock = widget.s.lockTimeoutMinutes;
  late bool _kotPrices = widget.s.kotShowPrices;
  late bool _autoReceipt = widget.s.autoPrintReceipt;
  late bool _autoKot = widget.s.autoPrintKot;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      TimeZoneField(value: _tz, onChanged: (v) => setState(() => _tz = v)),
      const SizedBox(height: 12),
      CutoffField(value: _cutoff, onChanged: (v) => setState(() => _cutoff = v)),
      const SizedBox(height: 8),
      Text(
        'Changing the cutoff only affects sales from now on. Existing bills keep the business date they were saved with '
        '(currently ${formatCutoff(widget.s.cutoffMinutes)}).',
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<int>(
        isExpanded: true,
        initialValue: [1, 2, 5, 10, 15, 30, 60].contains(_lock) ? _lock : 5,
        decoration: const InputDecoration(labelText: 'Lock after inactivity'),
        items: [
          for (final m in [1, 2, 5, 10, 15, 30, 60]) DropdownMenuItem(value: m, child: Text('$m minute(s)')),
        ],
        onChanged: (v) => setState(() => _lock = v ?? _lock),
      ),
      SwitchListTile(
        value: _autoReceipt,
        onChanged: (v) => setState(() => _autoReceipt = v),
        title: const Text('Print receipt after each sale'),
      ),
      SwitchListTile(
        value: _autoKot,
        onChanged: (v) => setState(() => _autoKot = v),
        title: const Text('Print kitchen tickets'),
      ),
      SwitchListTile(
        value: _kotPrices,
        onChanged: (v) => setState(() => _kotPrices = v),
        title: const Text('Show prices on kitchen tickets'),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: () async {
          if (!await confirm(context, title: 'Save these settings?', message: 'This is recorded in the audit trail.')) {
            return;
          }
          if (!context.mounted) return;
          await guard(
            context,
            () => ref
                .read(servicesProvider)
                .settings
                .updateOperations(
                  requireActor(ref),
                  OperationsSettingsInput(
                    timeZone: _tz,
                    cutoffMinutes: _cutoff,
                    lockTimeoutMinutes: _lock,
                    kotShowPrices: _kotPrices,
                    autoPrintReceipt: _autoReceipt,
                    autoPrintKot: _autoKot,
                  ),
                ),
            success: 'Saved',
          );
        },
        child: const Text('Save'),
      ),
    ],
  );
}

class PricingSettingsScreen extends StatelessWidget {
  const PricingSettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => _SettingsPage(
    title: 'Discounts, charges and rounding',
    builder: (context, s) => _PricingForm(s: s),
  );
}

class _PricingForm extends ConsumerStatefulWidget {
  const _PricingForm({required this.s});
  final RestaurantSettingsRow s;
  @override
  ConsumerState<_PricingForm> createState() => _PricingFormState();
}

class _PricingFormState extends ConsumerState<_PricingForm> {
  late final _limit = TextEditingController(text: _pct(widget.s.cashierDiscountLimitBps));
  late final _service = TextEditingController(text: _pct(widget.s.serviceChargeBps));
  late final _delivery = TextEditingController(text: money.plain(widget.s.deliveryChargeDefault));
  late String? _serviceTax = widget.s.serviceChargeTaxProfileId;
  late String? _deliveryTax = widget.s.deliveryChargeTaxProfileId;
  late int _rounding = widget.s.roundingUnit;

  static String _pct(int bps) => formatBps(bps).replaceAll('%', '');

  @override
  void dispose() {
    _limit.dispose();
    _service.dispose();
    _delivery.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final services = ref.watch(servicesProvider);
    return StreamView<List<TaxProfileRow>>(
      stream: services.settings.watchTaxProfiles(),
      builder: (context, profiles) {
        DropdownButtonFormField<String?> taxPicker(String label, String? value, ValueChanged<String?> onChanged) =>
            DropdownButtonFormField<String?>(
              isExpanded: true,
              initialValue: profiles.any((p) => p.id == value) ? value : null,
              decoration: InputDecoration(labelText: label),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('No tax')),
                for (final p in profiles) DropdownMenuItem<String?>(value: p.id, child: Text(p.name)),
              ],
              onChanged: onChanged,
            );
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _limit,
              decoration: const InputDecoration(
                labelText: 'Cashier discount limit (%)',
                suffixText: '%',
                helperText: 'Bigger discounts need admin approval',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _service,
              decoration: const InputDecoration(
                labelText: 'Service charge for dine-in (%)',
                suffixText: '%',
                helperText: '0 = off. Staff can remove it per order.',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            taxPicker('Tax on service charge', _serviceTax, (v) => setState(() => _serviceTax = v)),
            const SizedBox(height: 12),
            MoneyField(controller: _delivery, label: 'Default delivery charge'),
            const SizedBox(height: 12),
            taxPicker('Tax on delivery charge', _deliveryTax, (v) => setState(() => _deliveryTax = v)),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              isExpanded: true,
              initialValue: _rounding,
              decoration: const InputDecoration(
                labelText: 'Round the payable total',
                helperText: 'Off by default. The rounding is shown on the bill.',
              ),
              items: [
                for (final u in roundingUnits)
                  DropdownMenuItem(value: u, child: Text(u == 0 ? 'No rounding' : 'To the nearest ${formatMoney(u)}')),
              ],
              onChanged: (v) => setState(() => _rounding = v ?? _rounding),
            ),
            const SizedBox(height: 8),
            const Text('New settings apply to orders started from now on. Open orders keep what they started with.'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                if (!await confirm(
                  context,
                  title: 'Save pricing settings?',
                  message: 'This is recorded in the audit trail.',
                )) {
                  return;
                }
                if (!context.mounted) return;
                await guard(context, () {
                  return services.settings.updatePricing(
                    requireActor(ref),
                    PricingSettingsInput(
                      cashierDiscountLimitBps: parsePercentToBps(_limit.text.isEmpty ? '0' : _limit.text),
                      serviceChargeBps: parsePercentToBps(_service.text.isEmpty ? '0' : _service.text),
                      serviceChargeTaxProfileId: _serviceTax,
                      deliveryChargeDefault: money.parse(_delivery.text.isEmpty ? '0' : _delivery.text),
                      deliveryChargeTaxProfileId: _deliveryTax,
                      roundingUnit: _rounding,
                    ),
                  );
                }, success: 'Saved');
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }
}

class TaxProfilesScreen extends ConsumerWidget {
  const TaxProfilesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(servicesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Taxes')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Add tax profile'),
        onPressed: () => _edit(context, ref, null),
      ),
      body: StreamView<List<TaxProfileRow>>(
        stream: services.settings.watchTaxProfiles(),
        builder: (context, profiles) => ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Taxes are off until you create a profile and assign it to menu items. CaféDesk does not know your '
                'registration or the correct rates — check them with your accountant. Reports are operational, not tax filings.',
              ),
            ),
            if (profiles.isEmpty) const EmptyState(icon: Icons.receipt_outlined, title: 'No tax profiles'),
            for (final p in profiles)
              ListTile(
                title: Text(p.name),
                subtitle: Text(
                  [
                    TaxMode.parse(p.mode).label,
                    formatBps(p.rateBps),
                    for (final c in TaxSnapshot.decodeComponents(p.componentsJson)) '${c.name} ${formatBps(c.rateBps)}',
                  ].join(' · '),
                ),
                trailing: IconButton(
                  tooltip: 'Archive',
                  icon: const Icon(Icons.archive_outlined),
                  onPressed: () async {
                    if (await confirm(
                          context,
                          title: 'Archive ${p.name}?',
                          message: 'Items using it keep it until you change them; past bills are unaffected.',
                        ) &&
                        context.mounted) {
                      await guard(
                        context,
                        () => services.settings.setTaxProfileArchived(requireActor(ref), p.id, true),
                      );
                    }
                  },
                ),
                onTap: () => _edit(context, ref, p),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, TaxProfileRow? p) async {
    final name = TextEditingController(text: p?.name ?? '');
    final rate = TextEditingController(text: p == null ? '' : formatBps(p.rateBps).replaceAll('%', ''));
    var mode = p == null ? TaxMode.exclusive : TaxMode.parse(p.mode);
    final comps = [
      for (final c in TaxSnapshot.decodeComponents(p?.componentsJson))
        (TextEditingController(text: c.name), TextEditingController(text: formatBps(c.rateBps).replaceAll('%', ''))),
    ];
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) => AlertDialog(
          title: Text(p == null ? 'New tax profile' : 'Edit ${p.name}'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    maxLength: 40,
                    decoration: const InputDecoration(labelText: 'Name (e.g. GST 5%)'),
                  ),
                  DropdownButtonFormField<TaxMode>(
                    isExpanded: true,
                    initialValue: mode,
                    decoration: const InputDecoration(labelText: 'How prices work'),
                    items: [for (final m in TaxMode.values) DropdownMenuItem(value: m, child: Text(m.label))],
                    onChanged: (v) => setLocal(() => mode = v ?? mode),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: rate,
                    decoration: const InputDecoration(labelText: 'Total rate', suffixText: '%'),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Split into named parts (optional, e.g. CGST + SGST)'),
                  ),
                  for (final (n, r) in comps)
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: n,
                            decoration: const InputDecoration(labelText: 'Part name'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 90,
                          child: TextField(
                            controller: r,
                            decoration: const InputDecoration(labelText: '%'),
                          ),
                        ),
                      ],
                    ),
                  TextButton.icon(
                    onPressed: () => setLocal(() => comps.add((TextEditingController(), TextEditingController()))),
                    icon: const Icon(Icons.add),
                    label: const Text('Add part'),
                  ),
                  const Text(
                    'Edits apply to items added to orders from now on. Existing orders and bills keep their tax.',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok == true && context.mounted) {
      final services = ref.read(servicesProvider);
      await guard(context, () async {
        final input = TaxProfileInput(
          name: name.text,
          mode: mode,
          rateBps: parsePercentToBps(rate.text.isEmpty ? '0' : rate.text),
          components: [
            for (final (n, r) in comps)
              if (n.text.trim().isNotEmpty)
                TaxComponentRate(name: n.text.trim(), rateBps: parsePercentToBps(r.text.isEmpty ? '0' : r.text)),
          ],
        );
        if (p == null) {
          await services.settings.createTaxProfile(requireActor(ref), input);
        } else {
          await services.settings.updateTaxProfile(requireActor(ref), p.id, input);
        }
      }, success: 'Tax profile saved');
    }
    name.dispose();
    rate.dispose();
    for (final (n, r) in comps) {
      n.dispose();
      r.dispose();
    }
  }
}

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rt = ref.watch(runtimeProvider);
    final inst = ref.watch(installationProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('About and data')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '${AppInfo.name} ${AppInfo.version} (build ${AppInfo.build})',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Where your data is',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText('Database: ${rt.databaseFile.path}'),
                SelectableText('Backups: ${rt.paths.backups.path}'),
                if (inst != null)
                  Text('Installation: ${inst.installationId.substring(0, 8)}… · receipt prefix ${inst.receiptPrefix}'),
                const SizedBox(height: 8),
                const Text(
                  'Keep the database on this device\'s own storage. Do not put it in OneDrive, Dropbox or a network folder.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const SectionCard(
            title: 'No live sync',
            child: Text(separateInstallNotice),
          ),
          const SizedBox(height: 12),
          const SectionCard(
            title: 'What passwords protect',
            child: Text(
              'Email + password accounts control who can use CaféDesk on this device; only an admin creates them. Passwords are stored as salted Argon2id hashes, not in plain text, and the email is only a sign-in name (nothing is sent to it). '
              'They do not encrypt the database or backups: someone with administrator access to the device or a backup file '
              'can read the data. Backup files are not encrypted — store copies safely.',
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Payments',
            child: Text(
              'Card and UPI payments are recorded manually by staff. CaféDesk does not connect to banks or payment providers '
              'and never stores card numbers or UPI credentials.',
              style: TextStyle(color: AppColors.ink.withValues(alpha: 0.9)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Exposed so other screens can show the current day key.
String businessDayLabel(BusinessCalendar c) => c.businessDateOf(DateTime.now().toUtc()).key;
