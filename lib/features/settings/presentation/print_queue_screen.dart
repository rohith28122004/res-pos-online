import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/printing/queue/print_job_writer.dart';
import '../../../shared/widgets/common.dart';
import '../../checkout/presentation/checkout_screen.dart';
import '../application/printer_service.dart';

/// Durable print jobs. "Sent to printer" means the printer connection or
/// Windows spooler accepted the data — not that paper came out.
class PrintQueueScreen extends ConsumerStatefulWidget {
  const PrintQueueScreen({super.key});
  @override
  ConsumerState<PrintQueueScreen> createState() => _PrintQueueScreenState();
}

class _PrintQueueScreenState extends ConsumerState<PrintQueueScreen> {
  bool _attentionOnly = true;

  @override
  Widget build(BuildContext context) {
    final services = ref.watch(servicesProvider);
    final actor = requireActor(ref);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterChip(
                label: const Text('Needs attention only'),
                selected: _attentionOnly,
                onSelected: (v) => setState(() => _attentionOnly = v),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.replay),
                label: const Text('Retry all failed'),
                onPressed: () => guard(context, () async {
                  final n = await services.printers.retryAllFailed(actor);
                  ref.read(runtimeProvider).kickPrintQueue();
                  return n;
                }),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Failed = definitely not sent, safe to retry. Unknown = the connection broke while sending: '
            'check the printer first. Printing problems never change a saved bill.',
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: StreamView<List<PrintJobView>>(
            key: ValueKey(_attentionOnly),
            stream: services.printers.watchJobs(attentionOnly: _attentionOnly),
            builder: (context, jobs) {
              if (jobs.isEmpty) {
                return EmptyState(
                  icon: Icons.print_outlined,
                  title: _attentionOnly ? 'Nothing needs attention' : 'No print jobs yet',
                );
              }
              return ListView.separated(
                itemCount: jobs.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) => _JobTile(view: jobs[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _JobTile extends ConsumerWidget {
  const _JobTile({required this.view});
  final PrintJobView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final j = view.job;
    final services = ref.watch(servicesProvider);
    final actor = requireActor(ref);
    final docLabel = switch (j.documentType) {
      'receipt' => 'Receipt',
      'kot' => 'Kitchen ticket',
      'refund' => 'Refund receipt',
      'test' => 'Test page',
      _ => j.documentType,
    };
    void kick() => ref.read(runtimeProvider).kickPrintQueue();
    return ListTile(
      leading: Icon(printJobIcon(j.state), color: printJobColor(j.state)),
      title: Text('$docLabel${j.copyLabel == null ? '' : ' (${j.copyLabel})'} → ${view.printerName}'),
      subtitle: Text(
        [
          PrintJobState.label(j.state),
          formatLocalMs(j.createdAt),
          if (j.attemptCount > 0) '${j.attemptCount} attempt(s)',
          ?j.lastError,
        ].join(' · '),
      ),
      isThreeLine: j.lastError != null,
      trailing: Wrap(
        spacing: 4,
        children: [
          if (j.state == PrintJobState.failed || j.state == PrintJobState.held)
            TextButton(
              onPressed: () async {
                await guard(context, () => services.printers.retry(actor, j.id));
                kick();
              },
              child: Text(j.state == PrintJobState.held ? 'Release' : 'Retry'),
            ),
          if (j.state == PrintJobState.unknown) ...[
            TextButton(
              onPressed: () =>
                  guard(context, () => services.printers.confirmPrinted(actor, j.id), success: 'Marked as printed'),
              child: const Text('It printed'),
            ),
            TextButton(
              onPressed: () async {
                final ok = await confirm(
                  context,
                  title: 'Reprint?',
                  message:
                      'Only reprint if you checked the printer and it did NOT print. The reprint is marked REPRINT.',
                  confirmLabel: 'Reprint',
                );
                if (ok && context.mounted) {
                  await guard(context, () => services.printers.retry(actor, j.id, confirmedNotPrinted: true));
                  kick();
                }
              },
              child: const Text('Reprint'),
            ),
          ],
          if ([PrintJobState.queued, PrintJobState.failed, PrintJobState.unknown, PrintJobState.held].contains(j.state))
            IconButton(
              tooltip: 'Cancel job',
              icon: const Icon(Icons.close),
              onPressed: () => guard(context, () => services.printers.cancel(actor, j.id)),
            ),
        ],
      ),
    );
  }
}

/// Status colour helper re-exported for other screens.
Color jobStateColor(String s) => switch (s) {
  PrintJobState.failed => AppColors.danger,
  PrintJobState.unknown || PrintJobState.held => AppColors.warning,
  PrintJobState.submitted || PrintJobState.resolved => AppColors.success,
  _ => AppColors.info,
};
