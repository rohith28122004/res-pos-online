import 'package:cafedesk/core/database/app_database.dart';
import 'package:cafedesk/core/host/command_dispatcher.dart';
import 'package:cafedesk/core/printing/queue/print_job_writer.dart';
import 'package:cafedesk/core/printing/transports/transport.dart';
import 'package:cafedesk/core/protocol/protocol.dart';
import 'package:cafedesk/core/security/permissions.dart';
import 'package:cafedesk/features/settings/application/printer_service.dart';
import 'package:drift/drift.dart';

import 'harness.dart';

const testRestaurantId = 'rest-1';
const testHostDeviceId = 'host-1';

/// A host identity row with placeholder certificate/keys (dispatcher tests do
/// not use TLS). Real identities come from HostIdentityService.
Future<void> installHostIdentity(Harness h, {int epoch = 1}) async {
  final now = h.ctx.nowMs();
  await h.db
      .into(h.db.hostIdentity)
      .insertOnConflictUpdate(
        HostIdentityCompanion.insert(
          singleton: const Value(1),
          restaurantId: testRestaurantId,
          hostDeviceId: testHostDeviceId,
          hostEpoch: epoch,
          epochStartSequence: 1,
          epochStartedAt: now,
          tlsCertPem: 'test-cert',
          tlsCertSha256: 'test-cert-sha256',
          signingPublicKey: 'test-signing-key',
          sealPublicKey: 'test-seal-key',
          createdAt: now,
          updatedAt: now,
        ),
      );
}

Future<String> pairDeviceRow(Harness h, String role, {String? id}) async {
  final deviceId = id ?? h.ctx.ids.newId();
  await h.db
      .into(h.db.pairedDevices)
      .insert(
        PairedDevicesCompanion.insert(
          id: deviceId,
          role: role,
          name: '$role phone',
          credentialHash: 'hash-$deviceId',
          createdAt: h.ctx.nowMs(),
          pairedBy: h.owner.staffId,
          pairedByName: h.owner.name,
        ),
      );
  return deviceId;
}

Future<Actor> addStaff(Harness h, String name, StaffRole role) async {
  final email = '${name.toLowerCase().replaceAll(' ', '.')}@test.cafe';
  final id = await h.auth.createStaff(
    h.owner,
    name: name,
    email: email,
    role: role,
    password: 'password-$name',
    mustChangePassword: false,
  );
  return Actor(staffId: id, name: name, role: role);
}

Future<void> addKotPrinter(Harness h) async {
  final p = PrinterProfileInput.defaults(paperWidthMm: 58, transport: TransportType.tcp);
  await PrinterService(h.ctx).saveProfile(
    h.owner,
    PrinterProfileInput(
      name: 'Kitchen',
      role: PrinterRole.kot,
      paperWidthMm: p.paperWidthMm,
      dotsWidth: p.dotsWidth,
      charsPerLine: p.charsPerLine,
      codePage: p.codePage,
      renderMode: p.renderMode,
      cutter: p.cutter,
      drawerPulse: false,
      transport: TransportType.tcp,
      endpoint: '10.0.0.9',
      port: 9100,
    ),
  );
}

RemoteCaller caller(String deviceId, String deviceRole, Actor actor) =>
    RemoteCaller(deviceId: deviceId, deviceRole: deviceRole, actor: actor, sessionId: 'session-$deviceId');

Map<String, Object?> command(
  Harness h, {
  required String deviceId,
  required Actor actor,
  required String action,
  String? aggregateId,
  int? expectedRevision,
  Map<String, Object?> payload = const {},
  String? commandId,
  int epoch = 1,
}) => Command.build(
  commandId: commandId ?? h.ctx.ids.newId(),
  restaurantId: testRestaurantId,
  deviceId: deviceId,
  staffId: actor.staffId,
  hostEpoch: epoch,
  action: action,
  aggregateId: aggregateId,
  expectedRevision: expectedRevision,
  issuedAt: h.ctx.nowMs(),
  payload: payload,
);

Map<String, Object?> line(
  String itemId,
  int expectedUnitPrice, {
  int quantity = 1,
  String? variantId,
  List<String> modifierIds = const [],
  String? note,
}) => {
  'itemId': itemId,
  'variantId': variantId,
  'modifierIds': modifierIds,
  'quantity': quantity,
  'note': note,
  'expectedUnitPrice': expectedUnitPrice,
};

Future<List<HostEventRow>> events(Harness h) =>
    (h.db.select(h.db.hostEvents)..orderBy([(e) => OrderingTerm(expression: e.sequence)])).get();
