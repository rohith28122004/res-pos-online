import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/database/app_database.dart';
import '../../../shared/widgets/common.dart';

const _filters = <String, String>{
  '': 'Everything',
  'bill.': 'Bills',
  'refund.': 'Refunds',
  'order.': 'Orders & voids',
  'kot.': 'Kitchen',
  'settings.': 'Settings',
  'menu.': 'Menu & prices',
  'tax_profile.': 'Taxes',
  'staff.': 'Staff',
  'auth.': 'Sign-ins',
  'shift.': 'Shifts',
  'drawer.': 'Cash drawer',
  'expense.': 'Expenses',
  'backup.': 'Backup & restore',
  'print.': 'Printing',
  'printer.': 'Printers',
  'export.': 'Exports',
};

/// Read-only audit trail: who did what, when, and who approved it.
class AuditScreen extends ConsumerStatefulWidget {
  const AuditScreen({super.key});
  @override
  ConsumerState<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends ConsumerState<AuditScreen> {
  String _prefix = '';
  final _events = <AuditEventRow>[];
  bool _loading = false;
  bool _end = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load(reset: true));
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final services = ref.read(servicesProvider);
      final before = reset || _events.isEmpty ? null : _events.last.at;
      final page = await services.audit.events(requireActor(ref), actionPrefix: _prefix, beforeMs: before, limit: 100);
      setState(() {
        if (reset) _events.clear();
        _events.addAll(page);
        _end = page.length < 100;
      });
    } on Object catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Audit trail')),
    body: Column(
      children: [
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              for (final e in _filters.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(e.value),
                    selected: _prefix == e.key,
                    onSelected: (_) {
                      setState(() => _prefix = e.key);
                      unawaited(_load(reset: true));
                    },
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _events.isEmpty && !_loading
              ? const EmptyState(icon: Icons.history, title: 'No events')
              : ListView.builder(
                  itemCount: _events.length + 1,
                  itemBuilder: (context, i) {
                    if (i == _events.length) {
                      if (_end) return const SizedBox(height: 32);
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Center(
                          child: _loading
                              ? const CircularProgressIndicator()
                              : OutlinedButton(onPressed: _load, child: const Text('Load older')),
                        ),
                      );
                    }
                    final e = _events[i];
                    return ListTile(
                      dense: true,
                      title: Text(
                        '${e.action} · ${e.actorName ?? 'system'}${e.approvedBy != null ? ' (owner approved)' : ''}',
                      ),
                      subtitle: Text(
                        '${formatLocalMs(e.at)}${e.detailsJson == null ? '' : ' · ${e.detailsJson}'}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  },
                ),
        ),
      ],
    ),
  );
}
