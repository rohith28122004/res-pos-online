enum PaymentMethod {
  cash('cash', 'Cash'),
  upi('upi', 'UPI'),
  card('card', 'Card');

  const PaymentMethod(this.code, this.label);
  final String code;
  final String label;

  static PaymentMethod parse(String code) => PaymentMethod.values.firstWhere((m) => m.code == code);
}

/// One tender line entered at checkout. Card and UPI are recorded manually —
/// the app does not verify them with any bank or payment provider.
class TenderInput {
  const TenderInput({required this.method, required this.applied, int? tendered}) : tendered = tendered ?? applied;

  final PaymentMethod method;

  /// Amount allocated to the bill (revenue).
  final int applied;

  /// Cash handed over; may exceed [applied] for cash, creating change.
  final int tendered;

  int get change => tendered - applied;
}
