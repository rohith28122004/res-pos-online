import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/database/app_database.dart';
import '../../../core/printing/encoders/escpos.dart';
import '../../../core/printing/queue/print_job_writer.dart';
import '../../../core/printing/queue/print_queue.dart';
import '../../../core/printing/transports/bluetooth_transport.dart';
import '../../../core/printing/transports/tcp_transport.dart';
import '../../../core/printing/transports/transport.dart';
import '../../../core/printing/transports/windows_spooler.dart';
import '../../../shared/widgets/common.dart';
import '../application/printer_service.dart';

class PrintersScreen extends ConsumerWidget {
  const PrintersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(servicesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Printers')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Add printer'),
        onPressed: () =>
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PrinterEditorScreen())),
      ),
      body: StreamView<List<PrinterProfileRow>>(
        stream: services.printers.watchProfiles(),
        builder: (context, printers) => ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'ESC/POS-compatible thermal printers, 58 or 80 mm. Compatibility depends on the model — test with '
                'the sample receipt before going live. Billing works without any printer.',
              ),
            ),
            if (printers.isEmpty) const EmptyState(icon: Icons.print_disabled_outlined, title: 'No printers set up'),
            for (final p in printers)
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(p.name, style: Theme.of(context).textTheme.titleMedium)),
                          StatusChip(
                            label: p.enabled ? 'Enabled' : 'Disabled',
                            color: p.enabled ? AppColors.success : AppColors.warning,
                          ),
                        ],
                      ),
                      Text(
                        '${PrinterRole.label(p.role)} · ${p.paperWidthMm} mm · ${TransportType.parse(p.transport).label}',
                      ),
                      Text(
                        '${p.endpoint}${p.port == null ? '' : ':${p.port}'} · ${RenderMode.label(p.renderMode)} · ${CodePage.parse(p.codePage).label}',
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: () => _testConnection(context, p),
                            child: const Text('Test connection'),
                          ),
                          OutlinedButton(
                            onPressed: () async {
                              await guard(
                                context,
                                () => services.printers.printTestPage(requireActor(ref), p.id),
                                success: 'Test page queued',
                              );
                              ref.read(runtimeProvider).kickPrintQueue();
                            },
                            child: const Text('Print test page'),
                          ),
                          OutlinedButton(
                            onPressed: () async {
                              await guard(
                                context,
                                () => services.printers.printSamples(requireActor(ref), p.id),
                                success: 'Sample receipt/KOT queued',
                              );
                              ref.read(runtimeProvider).kickPrintQueue();
                            },
                            child: const Text('Print sample'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(
                              context,
                            ).push(MaterialPageRoute<void>(builder: (_) => PrinterEditorScreen(existing: p))),
                            child: const Text('Edit'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _testConnection(BuildContext context, PrinterProfileRow p) async {
    final type = TransportType.parse(p.transport);
    final transport = switch (type) {
      TransportType.tcp => const TcpTransport() as PrinterTransport,
      TransportType.bluetooth => const BluetoothTransport(),
      TransportType.windowsRaw || TransportType.windowsDriver => const WindowsSpoolerTransport(),
    };
    final r = await guard(
      context,
      () => transport.testConnection(endpointOf(p), timeout: Duration(milliseconds: p.timeoutMs)),
    );
    if (r == null || !context.mounted) return;
    if (r.ok) {
      showInfo(
        context,
        'Connected to ${p.name}. This does not print anything — use "Print test page" to check paper output.',
      );
    } else {
      showError(context, r.error ?? 'Could not connect');
    }
  }
}

class PrinterEditorScreen extends ConsumerStatefulWidget {
  const PrinterEditorScreen({super.key, this.existing});
  final PrinterProfileRow? existing;
  @override
  ConsumerState<PrinterEditorScreen> createState() => _PrinterEditorScreenState();
}

class _PrinterEditorScreenState extends ConsumerState<PrinterEditorScreen> {
  late final PrinterProfileRow? e = widget.existing;
  late TransportType _transport = e == null ? _defaultTransport() : TransportType.parse(e!.transport);
  late final _name = TextEditingController(text: e?.name ?? '');
  late final _endpoint = TextEditingController(text: e?.endpoint ?? '');
  late final _port = TextEditingController(text: (e?.port ?? 9100).toString());
  late int _paper = e?.paperWidthMm ?? 80;
  late final _dots = TextEditingController(text: (e?.dotsWidth ?? 576).toString());
  late final _chars = TextEditingController(text: (e?.charsPerLine ?? 48).toString());
  late final _feed = TextEditingController(text: (e?.feedLines ?? 3).toString());
  late final _timeout = TextEditingController(text: ((e?.timeoutMs ?? 8000) ~/ 1000).toString());
  late String _role = e?.role ?? PrinterRole.both;
  late String _codePage = e?.codePage ?? CodePage.cp437.code;
  late String _mode = e?.renderMode ?? RenderMode.auto;
  late String _cutter = e?.cutter ?? CutMode.partial.code;
  late bool _pulse = e?.drawerPulse ?? false;
  late bool _enabled = e?.enabled ?? true;
  List<DiscoveredPrinter> _found = const [];
  String? _discoveryNote;

  static TransportType _defaultTransport() => Platform.isWindows
      ? TransportType.windowsRaw
      : (Platform.isAndroid ? TransportType.bluetooth : TransportType.tcp);

  @override
  void initState() {
    super.initState();
    unawaited(_discover());
  }

  @override
  void dispose() {
    for (final c in [_name, _endpoint, _port, _dots, _chars, _feed, _timeout]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _discover() async {
    setState(() => _discoveryNote = null);
    try {
      if (_transport == TransportType.bluetooth) {
        var status = await BluetoothTransport.permissionStatus();
        if (status != 'granted') status = await BluetoothTransport.requestPermission();
        if (status != 'granted') {
          setState(
            () => _discoveryNote = status == 'permanently_denied'
                ? 'Bluetooth permission is blocked. Allow "Nearby devices" for CaféDesk in Android settings.'
                : 'Bluetooth permission was denied. CaféDesk needs it only to talk to your paired printer.',
          );
          return;
        }
        final list = await BluetoothTransport.bondedDevices();
        setState(() {
          _found = list;
          if (list.isEmpty) {
            _discoveryNote =
                'No paired devices. Pair the printer in Android Bluetooth settings first (PIN is often 0000 or 1234).';
          }
        });
      } else if (_transport == TransportType.windowsRaw || _transport == TransportType.windowsDriver) {
        final names = await listWindowsPrinters();
        setState(() {
          _found = [for (final n in names) DiscoveredPrinter(name: n, address: n, type: _transport)];
          if (names.isEmpty) _discoveryNote = 'No printers are installed in Windows. Install the printer driver first.';
        });
      } else {
        setState(() {
          _found = const [];
          _discoveryNote =
              'Enter the printer\'s IP address (print a self-test page on the printer to see it). Port is usually 9100.';
        });
      }
    } on Object catch (err) {
      setState(() => _discoveryNote = errorText(err));
    }
  }

  void _setPaper(int mm) {
    setState(() {
      _paper = mm;
      _dots.text = mm == 58 ? '384' : '576';
      _chars.text = mm == 58 ? '32' : '48';
    });
  }

  Future<void> _save() async {
    final services = ref.read(servicesProvider);
    final input = PrinterProfileInput(
      name: _name.text,
      role: _role,
      paperWidthMm: _paper,
      dotsWidth: int.tryParse(_dots.text) ?? 0,
      charsPerLine: int.tryParse(_chars.text) ?? 0,
      codePage: _codePage,
      renderMode: _mode,
      cutter: _cutter,
      drawerPulse: _pulse,
      transport: _transport,
      endpoint: _endpoint.text,
      port: _transport == TransportType.tcp ? int.tryParse(_port.text) : null,
      timeoutMs: (int.tryParse(_timeout.text) ?? 8) * 1000,
      feedLines: int.tryParse(_feed.text) ?? 3,
      enabled: _enabled,
    );
    final id = await guard(
      context,
      () => services.printers.saveProfile(requireActor(ref), input, id: e?.id),
      success: 'Printer saved',
    );
    if (id != null && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final available = [
      TransportType.tcp,
      if (Platform.isAndroid) TransportType.bluetooth,
      if (Platform.isWindows) ...[TransportType.windowsRaw, TransportType.windowsDriver],
    ];
    final services = ref.watch(servicesProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(e == null ? 'Add printer' : 'Edit printer'),
        actions: [
          if (e != null)
            IconButton(
              tooltip: 'Remove printer',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirm(
                      context,
                      title: 'Remove ${e!.name}?',
                      message: 'Waiting jobs for this printer are cancelled. History is kept.',
                      destructive: true,
                    ) &&
                    context.mounted) {
                  final ok = await guard(
                    context,
                    () => services.printers.archiveProfile(requireActor(ref), e!.id).then((_) => true),
                  );
                  if (ok == true && context.mounted) Navigator.pop(context);
                }
              },
            ),
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: _name,
                maxLength: 40,
                decoration: const InputDecoration(labelText: 'Printer name (e.g. Counter, Kitchen)'),
              ),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Prints'),
                items: [
                  for (final r in [PrinterRole.receipt, PrinterRole.kot, PrinterRole.both])
                    DropdownMenuItem(value: r, child: Text(PrinterRole.label(r))),
                ],
                onChanged: (v) => setState(() => _role = v ?? _role),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<TransportType>(
                isExpanded: true,
                initialValue: available.contains(_transport) ? _transport : available.first,
                decoration: const InputDecoration(labelText: 'Connection'),
                items: [for (final t in available) DropdownMenuItem(value: t, child: Text(t.label))],
                onChanged: (v) {
                  setState(() {
                    _transport = v ?? _transport;
                    _endpoint.clear();
                  });
                  unawaited(_discover());
                },
              ),
              if (_transport == TransportType.windowsDriver)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Driver rendered: the receipt is drawn as an image and printed through the Windows driver. '
                    'Use this when the printer queue does not accept raw ESC/POS data.',
                  ),
                ),
              const SizedBox(height: 12),
              if (_transport == TransportType.tcp) ...[
                TextField(
                  controller: _endpoint,
                  decoration: const InputDecoration(labelText: 'IP address or host name'),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _port,
                  decoration: const InputDecoration(labelText: 'Port'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _endpoint,
                        readOnly: _transport == TransportType.bluetooth,
                        decoration: InputDecoration(
                          labelText: _transport == TransportType.bluetooth
                              ? 'Paired printer address'
                              : 'Windows printer name',
                        ),
                      ),
                    ),
                    IconButton(tooltip: 'Search again', onPressed: _discover, icon: const Icon(Icons.refresh)),
                  ],
                ),
                RadioGroup<String>(
                  groupValue: _endpoint.text,
                  onChanged: (v) => setState(() {
                    _endpoint.text = v ?? '';
                    final f = _found.where((x) => x.address == v).firstOrNull;
                    if (_name.text.isEmpty && f != null) _name.text = f.name;
                  }),
                  child: Column(
                    children: [
                      for (final f in _found)
                        RadioListTile<String>(
                          value: f.address,
                          title: Text(f.name),
                          subtitle: f.detail == null ? null : Text(f.detail!),
                        ),
                    ],
                  ),
                ),
              ],
              if (_discoveryNote != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_discoveryNote!)),
              const Divider(height: 32),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 58, label: Text('58 mm')),
                  ButtonSegment(value: 80, label: Text('80 mm')),
                ],
                selected: {_paper},
                onSelectionChanged: (s) => _setPaper(s.first),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _dots,
                      decoration: const InputDecoration(
                        labelText: 'Printable width (dots)',
                        helperText: '384 for 58 mm, 576 for 80 mm',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _chars,
                      decoration: const InputDecoration(
                        labelText: 'Characters per line',
                        helperText: '32 or 48 usually',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _mode,
                decoration: const InputDecoration(
                  labelText: 'Print mode',
                  helperText:
                      'Image mode prints ₹ and Tamil/Hindi text but is slower. Text mode prints INR instead of ₹.',
                ),
                items: [
                  for (final m in [RenderMode.auto, RenderMode.text, RenderMode.raster])
                    DropdownMenuItem(value: m, child: Text(RenderMode.label(m))),
                ],
                onChanged: (v) => setState(() => _mode = v ?? _mode),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _codePage,
                decoration: const InputDecoration(labelText: 'Code page (text mode)'),
                items: [for (final c in CodePage.values) DropdownMenuItem(value: c.code, child: Text(c.label))],
                onChanged: (v) => setState(() => _codePage = v ?? _codePage),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _cutter,
                decoration: const InputDecoration(labelText: 'Paper cutter'),
                items: [for (final c in CutMode.values) DropdownMenuItem(value: c.code, child: Text(c.label))],
                onChanged: (v) => setState(() => _cutter = v ?? _cutter),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _feed,
                      decoration: const InputDecoration(labelText: 'Blank lines before cut'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _timeout,
                      decoration: const InputDecoration(labelText: 'Timeout (seconds)'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                value: _pulse,
                onChanged: (v) => setState(() => _pulse = v),
                title: const Text('Open cash drawer after original receipts'),
                subtitle: const Text('Off by default. Only for a drawer wired to this printer\'s drawer port.'),
              ),
              SwitchListTile(
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
                title: const Text('Enabled'),
              ),
              const SizedBox(height: 24),
              FilledButton(onPressed: _save, child: const Text('Save printer')),
            ],
          ),
        ),
      ),
    );
  }
}
