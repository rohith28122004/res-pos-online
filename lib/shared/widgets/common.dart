import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/errors/app_exception.dart';
import '../../core/money/money.dart';

/// Breakpoints: phone < 700 ≤ tablet < 1100 ≤ desktop.
enum ScreenSize { phone, tablet, desktop }

ScreenSize screenSizeOf(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  if (w < 700) return ScreenSize.phone;
  if (w < 1100) return ScreenSize.tablet;
  return ScreenSize.desktop;
}

const money = CurrencyFormat.inr;

String formatMoney(int minor) => money.format(minor);

/// Human message for any error thrown by services.
String errorText(Object e) => switch (e) {
  AppException(:final message) => message,
  _ => 'Something went wrong: $e',
};

/// Snackbars span phones but stay readable-width on tablets and PCs.
double? _snackWidth(BuildContext context) => MediaQuery.sizeOf(context).width >= 700 ? 480 : null;

void showError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(errorText(e)),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
        width: _snackWidth(context),
        duration: const Duration(seconds: 6),
      ),
    );
}

void showInfo(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating, width: _snackWidth(context)),
    );
}

/// Runs [action], showing failures as a snackbar. Returns null on failure.
Future<T?> guard<T>(BuildContext context, Future<T> Function() action, {String? success}) async {
  try {
    final r = await action();
    if (success != null && context.mounted) showInfo(context, success);
    return r;
  } on Object catch (e) {
    if (context.mounted) showError(context, e);
    return null;
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Colors.black38),
            const SizedBox(height: 12),
            Text(title, style: t.titleMedium, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                style: t.bodyMedium?.copyWith(color: Colors.black54),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label});
  final String? label;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        if (label != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(label!)),
      ],
    ),
  );
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.error_outline,
    title: 'Could not load this',
    message: errorText(error),
    action: onRetry == null ? null : OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
  );
}

/// Builds a StreamBuilder with consistent loading/error states.
class StreamView<T> extends StatelessWidget {
  const StreamView({super.key, required this.stream, required this.builder, this.loadingLabel});
  final Stream<T> stream;
  final Widget Function(BuildContext context, T data) builder;
  final String? loadingLabel;

  @override
  Widget build(BuildContext context) => StreamBuilder<T>(
    stream: stream,
    builder: (context, snap) {
      if (snap.hasError) return ErrorView(error: snap.error!);
      if (!snap.hasData) return LoadingView(label: loadingLabel);
      return builder(context, snap.data as T);
    },
  );
}

class FutureView<T> extends StatelessWidget {
  const FutureView({super.key, required this.future, required this.builder});
  final Future<T> future;
  final Widget Function(BuildContext context, T data) builder;

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: future,
    builder: (context, snap) {
      if (snap.hasError) return ErrorView(error: snap.error!);
      if (snap.connectionState != ConnectionState.done) return const LoadingView();
      return builder(context, snap.data as T);
    },
  );
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.color, this.icon});
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.5)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 16, color: color), const SizedBox(width: 4)],
        Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ],
    ),
  );
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child, this.trailing, this.subtitle});
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    if (subtitle != null)
                      Text(subtitle!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54)),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}

class MoneyRow extends StatelessWidget {
  const MoneyRow(this.label, this.amount, {super.key, this.bold = false, this.big = false, this.color});
  final String label;
  final int amount;
  final bool bold;
  final bool big;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final base = big ? Theme.of(context).textTheme.titleLarge : Theme.of(context).textTheme.bodyLarge;
    final style = base?.copyWith(fontWeight: bold ? FontWeight.w700 : FontWeight.w400, color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(formatMoney(amount), style: style?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }
}

/// Text field for rupee amounts; parses with integer maths.
class MoneyField extends StatelessWidget {
  const MoneyField({
    super.key,
    required this.controller,
    required this.label,
    this.autofocus = false,
    this.onChanged,
    this.helper,
  });
  final TextEditingController controller;
  final String label;
  final bool autofocus;
  final String? helper;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    autofocus: autofocus,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
    decoration: InputDecoration(labelText: label, prefixText: '₹ ', helperText: helper),
    onChanged: onChanged,
  );
}

/// Hidden password input with a show/hide button. Works inside or outside a
/// [Form].
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    this.label = 'Password',
    this.helper,
    this.autofocus = false,
    this.validator,
    this.onSubmitted,
    this.newPassword = false,
    this.focusNode,
  });
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String label;
  final String? helper;
  final bool autofocus;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onSubmitted;

  /// Choosing a new password (not typing an existing one).
  final bool newPassword;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: widget.controller,
    focusNode: widget.focusNode,
    autofocus: widget.autofocus,
    obscureText: !_visible,
    autocorrect: false,
    enableSuggestions: false,
    maxLength: 128,
    autofillHints: [widget.newPassword ? AutofillHints.newPassword : AutofillHints.password],
    validator: widget.validator,
    onFieldSubmitted: widget.onSubmitted,
    decoration: InputDecoration(
      labelText: widget.label,
      helperText: widget.helper,
      counterText: '',
      suffixIcon: IconButton(
        tooltip: _visible ? 'Hide password' : 'Show password',
        icon: Icon(_visible ? Icons.visibility_off_outlined : Icons.visibility_outlined),
        onPressed: () => setState(() => _visible = !_visible),
      ),
    ),
  );
}

/// Email input for sign-in accounts.
class EmailField extends StatelessWidget {
  const EmailField({super.key, required this.controller, this.label = 'Email', this.autofocus = false, this.validator});
  final TextEditingController controller;
  final String label;
  final bool autofocus;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    autofocus: autofocus,
    keyboardType: TextInputType.emailAddress,
    autocorrect: false,
    maxLength: 254,
    autofillHints: const [AutofillHints.email],
    validator: validator,
    decoration: InputDecoration(labelText: label, counterText: ''),
  );
}

int? tryParseMoney(String text) {
  if (text.trim().isEmpty) return null;
  try {
    return money.parse(text);
  } on ValidationException {
    return null;
  }
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: AppColors.danger) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Asks for a mandatory reason (voids, refunds, cash movements...).
Future<String?> askReason(
  BuildContext context, {
  required String title,
  String hint = 'Reason',
  String confirmLabel = 'Continue',
}) async {
  final ctrl = TextEditingController();
  final r = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLength: 140,
        decoration: InputDecoration(labelText: hint),
        onSubmitted: (v) => v.trim().isEmpty ? null : Navigator.pop(c, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => ctrl.text.trim().isEmpty ? null : Navigator.pop(c, ctrl.text.trim()),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  ctrl.dispose();
  return r;
}

Future<String?> askText(
  BuildContext context, {
  required String title,
  String label = '',
  String initial = '',
  int maxLength = 60,
  TextInputType? keyboard,
}) async {
  final ctrl = TextEditingController(text: initial);
  final r = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLength: maxLength,
        keyboardType: keyboard,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (v) => Navigator.pop(c, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('Save')),
      ],
    ),
  );
  ctrl.dispose();
  return r;
}

/// Large digit keypad used for amounts on touch screens.
class NumberPad extends StatelessWidget {
  const NumberPad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.onDone,
    this.doneLabel = 'OK',
    this.extraKey,
  });
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback? onDone;
  final String doneLabel;

  /// e.g. "." for amounts; null shows a blank.
  final String? extraKey;

  @override
  Widget build(BuildContext context) {
    Widget key(String label, VoidCallback? onTap, {IconData? icon, bool primary = false}) => Padding(
      padding: const EdgeInsets.all(4),
      child: SizedBox(
        height: 60,
        child: primary
            ? FilledButton(onPressed: onTap, child: Text(label))
            : OutlinedButton(
                onPressed: onTap,
                child: icon != null
                    ? Icon(icon, semanticLabel: label)
                    : Text(label, style: const TextStyle(fontSize: 22)),
              ),
      ),
    );
    final rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
    ];
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final r in rows) Row(children: [for (final d in r) Expanded(child: key(d, () => onDigit(d)))]),
          Row(
            children: [
              Expanded(
                child: extraKey == null
                    ? key('Delete', onBackspace, icon: Icons.backspace_outlined)
                    : key(extraKey!, () => onDigit(extraKey!)),
              ),
              Expanded(child: key('0', () => onDigit('0'))),
              Expanded(
                child: extraKey == null
                    ? key(doneLabel, onDone, primary: true)
                    : key('Delete', onBackspace, icon: Icons.backspace_outlined),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String formatLocalMs(int ms, {bool withDate = true}) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  final time = '${two(d.hour)}:${two(d.minute)}';
  return withDate ? '${d.year}-${two(d.month)}-${two(d.day)} $time' : time;
}

/// A fixed tile height that grows with the user's text-size setting, so large
/// system fonts do not overflow grid tiles.
double scaledExtent(BuildContext context, double base) {
  final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
  return base * (scale < 1 ? 1 : scale);
}
