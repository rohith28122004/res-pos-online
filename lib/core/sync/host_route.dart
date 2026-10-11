import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../network/lan_client.dart';
import '../protocol/protocol.dart';

/// Device credential + staff session presented on every request.
class RouteAuth {
  const RouteAuth({required this.deviceCredential, this.sessionToken});
  final String deviceCredential;
  final String? sessionToken;

  Map<String, String> get headers => {
    'x-cafedesk-device': deviceCredential,
    if (sessionToken != null) HttpHeaders.authorizationHeader: 'Bearer $sessionToken',
  };
}

/// What happened to a command sent over a route.
class Delivery {
  const Delivery({this.result, this.mailboxState});

  /// The host's decision, if it is known.
  final CommandResult? result;

  /// Cloud only: the relay holds the command but the host has not answered
  /// yet (`queued` / `delivered` / `expired` / `quarantined`).
  final String? mailboxState;
}

/// Messages from a live event channel.
sealed class LiveMessage {
  const LiveMessage();
}

class LiveHello extends LiveMessage {
  const LiveHello(this.hostEpoch, this.latestSequence);
  final int hostEpoch;
  final int latestSequence;
}

class LiveEvents extends LiveMessage {
  const LiveEvents(this.events, this.through);
  final List<Map<String, Object?>> events;
  final int through;
}

class LiveSnapshotRequired extends LiveMessage {
  const LiveSnapshotRequired();
}

/// Cloud only: new events are in the cloud ledger; fetch them by cursor.
class LiveEventsAvailable extends LiveMessage {
  const LiveEventsAvailable(this.hostEpoch, this.latestSequence);
  final int hostEpoch;
  final int latestSequence;
}

class LiveHostStatus extends LiveMessage {
  const LiveHostStatus({required this.connected});
  final bool connected;
}

/// Cloud only: one of this phone's relayed commands changed state.
class LiveCommandNotice extends LiveMessage {
  const LiveCommandNotice();
}

/// One way to reach the POS host: the café LAN or the cloud relay. Both carry
/// the same commands, bodies and ids (docs/PROTOCOL.md).
abstract class HostRoute {
  String get name;

  Future<Map<String, Object?>> sealed(Map<String, Object?> sealedBox, RouteAuth auth);
  Future<Map<String, Object?>> snapshot(String scope, RouteAuth auth);
  Future<Delivery> send(Map<String, Object?> command, RouteAuth auth);
  Future<Delivery?> lookup(String commandId, RouteAuth auth);
  Future<Map<String, Object?>> events(int epoch, int after, RouteAuth auth);
  Future<Stream<LiveMessage>> live(int epoch, int after, RouteAuth auth);
  Future<void> signOut(RouteAuth auth);
  void close();
}

class LanRoute implements HostRoute {
  LanRoute(this.client);

  final LanClient client;

  @override
  String get name => 'lan';

  @override
  Future<Map<String, Object?>> sealed(Map<String, Object?> sealedBox, RouteAuth auth) =>
      client.request('POST', '/v1/auth/sealed', body: {'sealed': sealedBox}, headers: auth.headers);

  @override
  Future<Map<String, Object?>> snapshot(String scope, RouteAuth auth) =>
      client.request('GET', '/v1/snapshot', query: {'scope': scope}, headers: auth.headers);

  @override
  Future<Delivery> send(Map<String, Object?> command, RouteAuth auth) async {
    final json = await client.request('POST', '/v1/commands', body: command, headers: auth.headers);
    return Delivery(result: CommandResult.fromJson(json));
  }

  @override
  Future<Delivery?> lookup(String commandId, RouteAuth auth) async {
    try {
      final json = await client.request('GET', '/v1/commands/$commandId', headers: auth.headers);
      return Delivery(result: CommandResult.fromJson(json));
    } on ProtocolException catch (e) {
      if (e.code == ErrorCode.notFound) return null;
      rethrow;
    }
  }

  @override
  Future<Map<String, Object?>> events(int epoch, int after, RouteAuth auth) => client.request(
    'GET',
    '/v1/events',
    query: {'epoch': '$epoch', 'after': '$after'},
    headers: auth.headers,
  );

  @override
  Future<Stream<LiveMessage>> live(int epoch, int after, RouteAuth auth) async {
    final ws = await client.openSocket(
      '/v1/socket',
      headers: auth.headers,
      query: {'epoch': '$epoch', 'after': '$after'},
    );
    return liveStreamOf(ws, _parse);
  }

  static LiveMessage? _parse(Object? j) {
    if (j is! Map) return null;
    switch (j['t']) {
      case 'hello':
        return LiveHello(j['hostEpoch']! as int, j['latestSequence']! as int);
      case 'events':
        return LiveEvents(
          [for (final e in j['events']! as List) (e as Map).cast<String, Object?>()],
          j['through']! as int,
        );
      case 'snapshot_required':
        return const LiveSnapshotRequired();
    }
    return null;
  }

  @override
  Future<void> signOut(RouteAuth auth) => client.request('POST', '/v1/auth/sign-out', headers: auth.headers);

  @override
  void close() => client.close();
}

/// Parsed messages from [ws]; cancelling the subscription closes the socket.
Stream<LiveMessage> liveStreamOf(WebSocket ws, LiveMessage? Function(Object? json) parse) {
  late final StreamController<LiveMessage> out;
  StreamSubscription<Object?>? sub;
  out = StreamController<LiveMessage>(
    onListen: () {
      sub = ws.listen(
        (m) {
          if (m is! String) return;
          final Object? json;
          try {
            json = jsonDecode(m);
          } on FormatException {
            return;
          }
          final msg = parse(json);
          if (msg != null) out.add(msg);
        },
        onError: out.addError,
        onDone: () => unawaited(out.close()),
        cancelOnError: false,
      );
    },
    onCancel: () async {
      await sub?.cancel();
      await ws.close(1000, 'closed by app');
    },
  );
  return out.stream;
}
