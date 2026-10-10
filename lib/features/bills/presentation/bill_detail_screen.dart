import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/printing/documents/layout.dart';
import '../../../core/printing/documents/print_documents.dart';
import '../../../core/printing/encoders/escpos.dart';
import '../../../core/security/permissions.dart';
import '../../../shared/widgets/common.dart';
import '../../refunds/presentation/refund_screen.dart';
import '../application/bill_service.dart';
import '../domain/payment_method.dart';

class BillDetailScreen extends ConsumerStatefulWidget {
  const BillDetailScreen({super.key, required this.billId});
  final String billId;
  @override
  ConsumerState<BillDetailScreen> createState() => _BillDetailScreenState();
}

class _BillDetailScreenState extends ConsumerState<BillDetailScreen> {
  int _refresh = 0;

  @override
  Widget build(BuildContext context) {
    final services = ref.watch(servicesProvider);
    final actor = requireActor(ref);
    return FutureView<(BillDetail, ReceiptDocument)>(
      key: ValueKey(_refresh),
      future: () async {
        final d = await services.bills.detail(widget.billId);
        return (d, BillService.buildReceiptDocument(d));
      }(),
      builder: (context, data) {
        final (d, receipt) = data;
        final wide = MediaQuery.sizeOf(context).width >= 900;
        final info = _BillInfo(detail: d);
        final preview = ReceiptPreview(document: receipt);
        return Scaffold(
          appBar: AppBar(
            title: Text(d.bill.receiptNo),
            actions: [
              if (actor.can(Permission.reprint))
                TextButton.icon(
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('Reprint (COPY)'),
                  onPressed: () async {
                    final ids = await guard(context, () => services.bills.reprint(actor, d.bill.id));
                    if (ids != null && context.mounted) {
                      showInfo(context, ids.isEmpty ? 'No receipt printer is set up' : 'Copy sent to the print queue');
                    }
                  },
                ),
              if (actor.can(Permission.viewBills))
                TextButton.icon(
                  icon: const Icon(Icons.undo),
                  label: const Text('Refund'),
                  onPressed: d.refundedTotal >= d.bill.total
                      ? null
                      : () async {
                          await Navigator.of(
                            context,
                          ).push(MaterialPageRoute<void>(builder: (_) => RefundScreen(billId: d.bill.id)));
                          if (mounted) setState(() => _refresh++);
                        },
                ),
            ],
          ),
          body: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: info),
                    ),
                    SizedBox(
                      width: 420,
                      child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: preview),
                    ),
                  ],
                )
              : ListView(padding: const EdgeInsets.all(16), children: [info, const SizedBox(height: 16), preview]),
        );
      },
    );
  }
}

class _BillInfo extends ConsumerWidget {
  const _BillInfo({required this.detail});
  final BillDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = detail.bill;
    final services = ref.watch(servicesProvider);
    final actor = requireActor(ref);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: 'Bill',
          subtitle: 'Completed bills cannot be edited or deleted. Corrections are made with refunds.',
          child: Column(
            children: [
              MoneyRow('Items (before discount, excl. tax)', b.itemsGrossEx),
              if (b.itemsDiscountEx > 0) MoneyRow('Discounts (excl. tax)', -b.itemsDiscountEx),
              if (b.chargesNetEx > 0) MoneyRow('Charges (excl. tax)', b.chargesNetEx),
              MoneyRow('Tax', b.taxTotal),
              if (b.roundingAdjustment != 0) MoneyRow('Rounding', b.roundingAdjustment),
              MoneyRow('Total', b.total, bold: true),
              const Divider(),
              for (final p in detail.payments)
                MoneyRow(
                  '${PaymentMethod.parse(p.method).label}${p.changeGiven > 0 ? ' (received ${formatMoney(p.tendered)}, change ${formatMoney(p.changeGiven)})' : ''}',
                  p.applied,
                ),
              if (b.discountReason != null)
                Align(alignment: Alignment.centerLeft, child: Text('Discount reason: ${b.discountReason}')),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Business date ${b.businessDate} · Cashier ${b.staffName}'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (detail.refunds.isNotEmpty)
          SectionCard(
            title: 'Refunds',
            child: Column(
              children: [
                for (final r in detail.refunds)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${r.refundNo} · ${formatMoney(r.total)}'),
                    subtitle: Text('${r.businessDate} · ${r.reason} · approved by ${r.authorizedByName}'),
                    trailing: IconButton(
                      tooltip: 'Reprint refund receipt',
                      icon: const Icon(Icons.print_outlined),
                      onPressed: () => guard(
                        context,
                        () => services.refunds.reprintRefund(actor, r.id),
                        success: 'Copy sent to the print queue',
                      ),
                    ),
                  ),
                MoneyRow('Refunded so far', detail.refundedTotal, bold: true, color: AppColors.warning),
              ],
            ),
          ),
      ],
    );
  }
}

/// On-screen preview using the same layout as a 48-column text printer.
class ReceiptPreview extends StatelessWidget {
  const ReceiptPreview({super.key, required this.document, this.charsPerLine = 42});
  final ReceiptDocument document;
  final int charsPerLine;

  @override
  Widget build(BuildContext context) {
    final lines = previewLines(
      layoutReceipt(document, LayoutOptions(charsPerLine: charsPerLine, cut: false, feedLines: 0)),
      charsPerLine,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          lines.join('\n'),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.25),
        ),
      ),
    );
  }
}
