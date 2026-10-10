import 'dart:math';

import '../protocol/canonical_json.dart';
import '../security/permissions.dart';
import '../time/business_time.dart';

/// Owner approvals granted to a paired device through a sealed `approve`
/// request (docs/PROTOCOL.md §6). Single-use, bound to the device that asked,
/// valid for [OwnerApproval.validity]. Held in memory only: a host restart
/// simply means asking the owner again.
class ApprovalRegistry {
  ApprovalRegistry(this.clock);

  final Clock clock;
  final _grants = <String, _Grant>{};
  final _random = Random.secure();

  /// Stores [approval] for [deviceId] and returns its single-use id.
  String grant(OwnerApproval approval, String deviceId) {
    _prune();
    final id = b64url(List<int>.generate(18, (_) => _random.nextInt(256)));
    _grants[id] = _Grant(approval, deviceId);
    return id;
  }

  /// The approval for [approvalId] if it belongs to [deviceId] and is still
  /// fresh; it is removed either way, so it can be used once.
  OwnerApproval? consume(String approvalId, String deviceId) {
    _prune();
    final g = _grants.remove(approvalId);
    if (g == null || g.deviceId != deviceId) return null;
    return g.approval.isFreshAt(clock.nowUtc()) ? g.approval : null;
  }

  void _prune() {
    final now = clock.nowUtc();
    _grants.removeWhere((_, g) => !g.approval.isFreshAt(now));
  }
}

class _Grant {
  const _Grant(this.approval, this.deviceId);
  final OwnerApproval approval;
  final String deviceId;
}
