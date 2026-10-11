// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'client_database.dart';

// ignore_for_file: type=lint
class $ClientLinkTable extends ClientLink with TableInfo<$ClientLinkTable, ClientLinkRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ClientLinkTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _singletonMeta = const VerificationMeta(
    'singleton',
  );
  @override
  late final GeneratedColumn<int> singleton = GeneratedColumn<int>(
    'singleton',
    aliasedName,
    false,
    check: () => singleton.equals(1),
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceNameMeta = const VerificationMeta(
    'deviceName',
  );
  @override
  late final GeneratedColumn<String> deviceName = GeneratedColumn<String>(
    'device_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _restaurantIdMeta = const VerificationMeta(
    'restaurantId',
  );
  @override
  late final GeneratedColumn<String> restaurantId = GeneratedColumn<String>(
    'restaurant_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _restaurantNameMeta = const VerificationMeta(
    'restaurantName',
  );
  @override
  late final GeneratedColumn<String> restaurantName = GeneratedColumn<String>(
    'restaurant_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hostDeviceIdMeta = const VerificationMeta(
    'hostDeviceId',
  );
  @override
  late final GeneratedColumn<String> hostDeviceId = GeneratedColumn<String>(
    'host_device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hostEpochMeta = const VerificationMeta(
    'hostEpoch',
  );
  @override
  late final GeneratedColumn<int> hostEpoch = GeneratedColumn<int>(
    'host_epoch',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hostAddressesJsonMeta = const VerificationMeta(
    'hostAddressesJson',
  );
  @override
  late final GeneratedColumn<String> hostAddressesJson = GeneratedColumn<String>(
    'host_addresses_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hostPortMeta = const VerificationMeta(
    'hostPort',
  );
  @override
  late final GeneratedColumn<int> hostPort = GeneratedColumn<int>(
    'host_port',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _certSha256Meta = const VerificationMeta(
    'certSha256',
  );
  @override
  late final GeneratedColumn<String> certSha256 = GeneratedColumn<String>(
    'cert_sha256',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _signingPublicKeyMeta = const VerificationMeta(
    'signingPublicKey',
  );
  @override
  late final GeneratedColumn<String> signingPublicKey = GeneratedColumn<String>(
    'signing_public_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sealPublicKeyMeta = const VerificationMeta(
    'sealPublicKey',
  );
  @override
  late final GeneratedColumn<String> sealPublicKey = GeneratedColumn<String>(
    'seal_public_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cloudUrlMeta = const VerificationMeta(
    'cloudUrl',
  );
  @override
  late final GeneratedColumn<String> cloudUrl = GeneratedColumn<String>(
    'cloud_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pairedAtMeta = const VerificationMeta(
    'pairedAt',
  );
  @override
  late final GeneratedColumn<int> pairedAt = GeneratedColumn<int>(
    'paired_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cursorEpochMeta = const VerificationMeta(
    'cursorEpoch',
  );
  @override
  late final GeneratedColumn<int> cursorEpoch = GeneratedColumn<int>(
    'cursor_epoch',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _cursorSequenceMeta = const VerificationMeta(
    'cursorSequence',
  );
  @override
  late final GeneratedColumn<int> cursorSequence = GeneratedColumn<int>(
    'cursor_sequence',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastLiveAtMeta = const VerificationMeta(
    'lastLiveAt',
  );
  @override
  late final GeneratedColumn<int> lastLiveAt = GeneratedColumn<int>(
    'last_live_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    singleton,
    deviceId,
    role,
    deviceName,
    restaurantId,
    restaurantName,
    hostDeviceId,
    hostEpoch,
    hostAddressesJson,
    hostPort,
    certSha256,
    signingPublicKey,
    sealPublicKey,
    cloudUrl,
    pairedAt,
    cursorEpoch,
    cursorSequence,
    lastLiveAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'client_link';
  @override
  VerificationContext validateIntegrity(
    Insertable<ClientLinkRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('singleton')) {
      context.handle(
        _singletonMeta,
        singleton.isAcceptableOrUnknown(data['singleton']!, _singletonMeta),
      );
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('device_name')) {
      context.handle(
        _deviceNameMeta,
        deviceName.isAcceptableOrUnknown(data['device_name']!, _deviceNameMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceNameMeta);
    }
    if (data.containsKey('restaurant_id')) {
      context.handle(
        _restaurantIdMeta,
        restaurantId.isAcceptableOrUnknown(
          data['restaurant_id']!,
          _restaurantIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_restaurantIdMeta);
    }
    if (data.containsKey('restaurant_name')) {
      context.handle(
        _restaurantNameMeta,
        restaurantName.isAcceptableOrUnknown(
          data['restaurant_name']!,
          _restaurantNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_restaurantNameMeta);
    }
    if (data.containsKey('host_device_id')) {
      context.handle(
        _hostDeviceIdMeta,
        hostDeviceId.isAcceptableOrUnknown(
          data['host_device_id']!,
          _hostDeviceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_hostDeviceIdMeta);
    }
    if (data.containsKey('host_epoch')) {
      context.handle(
        _hostEpochMeta,
        hostEpoch.isAcceptableOrUnknown(data['host_epoch']!, _hostEpochMeta),
      );
    } else if (isInserting) {
      context.missing(_hostEpochMeta);
    }
    if (data.containsKey('host_addresses_json')) {
      context.handle(
        _hostAddressesJsonMeta,
        hostAddressesJson.isAcceptableOrUnknown(
          data['host_addresses_json']!,
          _hostAddressesJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_hostAddressesJsonMeta);
    }
    if (data.containsKey('host_port')) {
      context.handle(
        _hostPortMeta,
        hostPort.isAcceptableOrUnknown(data['host_port']!, _hostPortMeta),
      );
    } else if (isInserting) {
      context.missing(_hostPortMeta);
    }
    if (data.containsKey('cert_sha256')) {
      context.handle(
        _certSha256Meta,
        certSha256.isAcceptableOrUnknown(data['cert_sha256']!, _certSha256Meta),
      );
    } else if (isInserting) {
      context.missing(_certSha256Meta);
    }
    if (data.containsKey('signing_public_key')) {
      context.handle(
        _signingPublicKeyMeta,
        signingPublicKey.isAcceptableOrUnknown(
          data['signing_public_key']!,
          _signingPublicKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_signingPublicKeyMeta);
    }
    if (data.containsKey('seal_public_key')) {
      context.handle(
        _sealPublicKeyMeta,
        sealPublicKey.isAcceptableOrUnknown(
          data['seal_public_key']!,
          _sealPublicKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sealPublicKeyMeta);
    }
    if (data.containsKey('cloud_url')) {
      context.handle(
        _cloudUrlMeta,
        cloudUrl.isAcceptableOrUnknown(data['cloud_url']!, _cloudUrlMeta),
      );
    }
    if (data.containsKey('paired_at')) {
      context.handle(
        _pairedAtMeta,
        pairedAt.isAcceptableOrUnknown(data['paired_at']!, _pairedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_pairedAtMeta);
    }
    if (data.containsKey('cursor_epoch')) {
      context.handle(
        _cursorEpochMeta,
        cursorEpoch.isAcceptableOrUnknown(
          data['cursor_epoch']!,
          _cursorEpochMeta,
        ),
      );
    }
    if (data.containsKey('cursor_sequence')) {
      context.handle(
        _cursorSequenceMeta,
        cursorSequence.isAcceptableOrUnknown(
          data['cursor_sequence']!,
          _cursorSequenceMeta,
        ),
      );
    }
    if (data.containsKey('last_live_at')) {
      context.handle(
        _lastLiveAtMeta,
        lastLiveAt.isAcceptableOrUnknown(
          data['last_live_at']!,
          _lastLiveAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {singleton};
  @override
  ClientLinkRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ClientLinkRow(
      singleton: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}singleton'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      deviceName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_name'],
      )!,
      restaurantId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}restaurant_id'],
      )!,
      restaurantName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}restaurant_name'],
      )!,
      hostDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host_device_id'],
      )!,
      hostEpoch: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}host_epoch'],
      )!,
      hostAddressesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host_addresses_json'],
      )!,
      hostPort: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}host_port'],
      )!,
      certSha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cert_sha256'],
      )!,
      signingPublicKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}signing_public_key'],
      )!,
      sealPublicKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}seal_public_key'],
      )!,
      cloudUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cloud_url'],
      ),
      pairedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}paired_at'],
      )!,
      cursorEpoch: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cursor_epoch'],
      )!,
      cursorSequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cursor_sequence'],
      )!,
      lastLiveAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_live_at'],
      ),
    );
  }

  @override
  $ClientLinkTable createAlias(String alias) {
    return $ClientLinkTable(attachedDatabase, alias);
  }
}

class ClientLinkRow extends DataClass implements Insertable<ClientLinkRow> {
  final int singleton;
  final String deviceId;

  /// 'waiter' or 'kitchen'.
  final String role;
  final String deviceName;
  final String restaurantId;
  final String restaurantName;
  final String hostDeviceId;
  final int hostEpoch;
  final String hostAddressesJson;
  final int hostPort;
  final String certSha256;
  final String signingPublicKey;
  final String sealPublicKey;
  final String? cloudUrl;
  final int pairedAt;

  /// Event cursor: last host epoch/sequence applied to the cache.
  final int cursorEpoch;
  final int cursorSequence;

  /// When the cache was last confirmed current by the host (LAN or cloud).
  final int? lastLiveAt;
  const ClientLinkRow({
    required this.singleton,
    required this.deviceId,
    required this.role,
    required this.deviceName,
    required this.restaurantId,
    required this.restaurantName,
    required this.hostDeviceId,
    required this.hostEpoch,
    required this.hostAddressesJson,
    required this.hostPort,
    required this.certSha256,
    required this.signingPublicKey,
    required this.sealPublicKey,
    this.cloudUrl,
    required this.pairedAt,
    required this.cursorEpoch,
    required this.cursorSequence,
    this.lastLiveAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['singleton'] = Variable<int>(singleton);
    map['device_id'] = Variable<String>(deviceId);
    map['role'] = Variable<String>(role);
    map['device_name'] = Variable<String>(deviceName);
    map['restaurant_id'] = Variable<String>(restaurantId);
    map['restaurant_name'] = Variable<String>(restaurantName);
    map['host_device_id'] = Variable<String>(hostDeviceId);
    map['host_epoch'] = Variable<int>(hostEpoch);
    map['host_addresses_json'] = Variable<String>(hostAddressesJson);
    map['host_port'] = Variable<int>(hostPort);
    map['cert_sha256'] = Variable<String>(certSha256);
    map['signing_public_key'] = Variable<String>(signingPublicKey);
    map['seal_public_key'] = Variable<String>(sealPublicKey);
    if (!nullToAbsent || cloudUrl != null) {
      map['cloud_url'] = Variable<String>(cloudUrl);
    }
    map['paired_at'] = Variable<int>(pairedAt);
    map['cursor_epoch'] = Variable<int>(cursorEpoch);
    map['cursor_sequence'] = Variable<int>(cursorSequence);
    if (!nullToAbsent || lastLiveAt != null) {
      map['last_live_at'] = Variable<int>(lastLiveAt);
    }
    return map;
  }

  ClientLinkCompanion toCompanion(bool nullToAbsent) {
    return ClientLinkCompanion(
      singleton: Value(singleton),
      deviceId: Value(deviceId),
      role: Value(role),
      deviceName: Value(deviceName),
      restaurantId: Value(restaurantId),
      restaurantName: Value(restaurantName),
      hostDeviceId: Value(hostDeviceId),
      hostEpoch: Value(hostEpoch),
      hostAddressesJson: Value(hostAddressesJson),
      hostPort: Value(hostPort),
      certSha256: Value(certSha256),
      signingPublicKey: Value(signingPublicKey),
      sealPublicKey: Value(sealPublicKey),
      cloudUrl: cloudUrl == null && nullToAbsent ? const Value.absent() : Value(cloudUrl),
      pairedAt: Value(pairedAt),
      cursorEpoch: Value(cursorEpoch),
      cursorSequence: Value(cursorSequence),
      lastLiveAt: lastLiveAt == null && nullToAbsent ? const Value.absent() : Value(lastLiveAt),
    );
  }

  factory ClientLinkRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ClientLinkRow(
      singleton: serializer.fromJson<int>(json['singleton']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      role: serializer.fromJson<String>(json['role']),
      deviceName: serializer.fromJson<String>(json['deviceName']),
      restaurantId: serializer.fromJson<String>(json['restaurantId']),
      restaurantName: serializer.fromJson<String>(json['restaurantName']),
      hostDeviceId: serializer.fromJson<String>(json['hostDeviceId']),
      hostEpoch: serializer.fromJson<int>(json['hostEpoch']),
      hostAddressesJson: serializer.fromJson<String>(json['hostAddressesJson']),
      hostPort: serializer.fromJson<int>(json['hostPort']),
      certSha256: serializer.fromJson<String>(json['certSha256']),
      signingPublicKey: serializer.fromJson<String>(json['signingPublicKey']),
      sealPublicKey: serializer.fromJson<String>(json['sealPublicKey']),
      cloudUrl: serializer.fromJson<String?>(json['cloudUrl']),
      pairedAt: serializer.fromJson<int>(json['pairedAt']),
      cursorEpoch: serializer.fromJson<int>(json['cursorEpoch']),
      cursorSequence: serializer.fromJson<int>(json['cursorSequence']),
      lastLiveAt: serializer.fromJson<int?>(json['lastLiveAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'singleton': serializer.toJson<int>(singleton),
      'deviceId': serializer.toJson<String>(deviceId),
      'role': serializer.toJson<String>(role),
      'deviceName': serializer.toJson<String>(deviceName),
      'restaurantId': serializer.toJson<String>(restaurantId),
      'restaurantName': serializer.toJson<String>(restaurantName),
      'hostDeviceId': serializer.toJson<String>(hostDeviceId),
      'hostEpoch': serializer.toJson<int>(hostEpoch),
      'hostAddressesJson': serializer.toJson<String>(hostAddressesJson),
      'hostPort': serializer.toJson<int>(hostPort),
      'certSha256': serializer.toJson<String>(certSha256),
      'signingPublicKey': serializer.toJson<String>(signingPublicKey),
      'sealPublicKey': serializer.toJson<String>(sealPublicKey),
      'cloudUrl': serializer.toJson<String?>(cloudUrl),
      'pairedAt': serializer.toJson<int>(pairedAt),
      'cursorEpoch': serializer.toJson<int>(cursorEpoch),
      'cursorSequence': serializer.toJson<int>(cursorSequence),
      'lastLiveAt': serializer.toJson<int?>(lastLiveAt),
    };
  }

  ClientLinkRow copyWith({
    int? singleton,
    String? deviceId,
    String? role,
    String? deviceName,
    String? restaurantId,
    String? restaurantName,
    String? hostDeviceId,
    int? hostEpoch,
    String? hostAddressesJson,
    int? hostPort,
    String? certSha256,
    String? signingPublicKey,
    String? sealPublicKey,
    Value<String?> cloudUrl = const Value.absent(),
    int? pairedAt,
    int? cursorEpoch,
    int? cursorSequence,
    Value<int?> lastLiveAt = const Value.absent(),
  }) => ClientLinkRow(
    singleton: singleton ?? this.singleton,
    deviceId: deviceId ?? this.deviceId,
    role: role ?? this.role,
    deviceName: deviceName ?? this.deviceName,
    restaurantId: restaurantId ?? this.restaurantId,
    restaurantName: restaurantName ?? this.restaurantName,
    hostDeviceId: hostDeviceId ?? this.hostDeviceId,
    hostEpoch: hostEpoch ?? this.hostEpoch,
    hostAddressesJson: hostAddressesJson ?? this.hostAddressesJson,
    hostPort: hostPort ?? this.hostPort,
    certSha256: certSha256 ?? this.certSha256,
    signingPublicKey: signingPublicKey ?? this.signingPublicKey,
    sealPublicKey: sealPublicKey ?? this.sealPublicKey,
    cloudUrl: cloudUrl.present ? cloudUrl.value : this.cloudUrl,
    pairedAt: pairedAt ?? this.pairedAt,
    cursorEpoch: cursorEpoch ?? this.cursorEpoch,
    cursorSequence: cursorSequence ?? this.cursorSequence,
    lastLiveAt: lastLiveAt.present ? lastLiveAt.value : this.lastLiveAt,
  );
  ClientLinkRow copyWithCompanion(ClientLinkCompanion data) {
    return ClientLinkRow(
      singleton: data.singleton.present ? data.singleton.value : this.singleton,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      role: data.role.present ? data.role.value : this.role,
      deviceName: data.deviceName.present ? data.deviceName.value : this.deviceName,
      restaurantId: data.restaurantId.present ? data.restaurantId.value : this.restaurantId,
      restaurantName: data.restaurantName.present ? data.restaurantName.value : this.restaurantName,
      hostDeviceId: data.hostDeviceId.present ? data.hostDeviceId.value : this.hostDeviceId,
      hostEpoch: data.hostEpoch.present ? data.hostEpoch.value : this.hostEpoch,
      hostAddressesJson: data.hostAddressesJson.present ? data.hostAddressesJson.value : this.hostAddressesJson,
      hostPort: data.hostPort.present ? data.hostPort.value : this.hostPort,
      certSha256: data.certSha256.present ? data.certSha256.value : this.certSha256,
      signingPublicKey: data.signingPublicKey.present ? data.signingPublicKey.value : this.signingPublicKey,
      sealPublicKey: data.sealPublicKey.present ? data.sealPublicKey.value : this.sealPublicKey,
      cloudUrl: data.cloudUrl.present ? data.cloudUrl.value : this.cloudUrl,
      pairedAt: data.pairedAt.present ? data.pairedAt.value : this.pairedAt,
      cursorEpoch: data.cursorEpoch.present ? data.cursorEpoch.value : this.cursorEpoch,
      cursorSequence: data.cursorSequence.present ? data.cursorSequence.value : this.cursorSequence,
      lastLiveAt: data.lastLiveAt.present ? data.lastLiveAt.value : this.lastLiveAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ClientLinkRow(')
          ..write('singleton: $singleton, ')
          ..write('deviceId: $deviceId, ')
          ..write('role: $role, ')
          ..write('deviceName: $deviceName, ')
          ..write('restaurantId: $restaurantId, ')
          ..write('restaurantName: $restaurantName, ')
          ..write('hostDeviceId: $hostDeviceId, ')
          ..write('hostEpoch: $hostEpoch, ')
          ..write('hostAddressesJson: $hostAddressesJson, ')
          ..write('hostPort: $hostPort, ')
          ..write('certSha256: $certSha256, ')
          ..write('signingPublicKey: $signingPublicKey, ')
          ..write('sealPublicKey: $sealPublicKey, ')
          ..write('cloudUrl: $cloudUrl, ')
          ..write('pairedAt: $pairedAt, ')
          ..write('cursorEpoch: $cursorEpoch, ')
          ..write('cursorSequence: $cursorSequence, ')
          ..write('lastLiveAt: $lastLiveAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    singleton,
    deviceId,
    role,
    deviceName,
    restaurantId,
    restaurantName,
    hostDeviceId,
    hostEpoch,
    hostAddressesJson,
    hostPort,
    certSha256,
    signingPublicKey,
    sealPublicKey,
    cloudUrl,
    pairedAt,
    cursorEpoch,
    cursorSequence,
    lastLiveAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ClientLinkRow &&
          other.singleton == this.singleton &&
          other.deviceId == this.deviceId &&
          other.role == this.role &&
          other.deviceName == this.deviceName &&
          other.restaurantId == this.restaurantId &&
          other.restaurantName == this.restaurantName &&
          other.hostDeviceId == this.hostDeviceId &&
          other.hostEpoch == this.hostEpoch &&
          other.hostAddressesJson == this.hostAddressesJson &&
          other.hostPort == this.hostPort &&
          other.certSha256 == this.certSha256 &&
          other.signingPublicKey == this.signingPublicKey &&
          other.sealPublicKey == this.sealPublicKey &&
          other.cloudUrl == this.cloudUrl &&
          other.pairedAt == this.pairedAt &&
          other.cursorEpoch == this.cursorEpoch &&
          other.cursorSequence == this.cursorSequence &&
          other.lastLiveAt == this.lastLiveAt);
}

class ClientLinkCompanion extends UpdateCompanion<ClientLinkRow> {
  final Value<int> singleton;
  final Value<String> deviceId;
  final Value<String> role;
  final Value<String> deviceName;
  final Value<String> restaurantId;
  final Value<String> restaurantName;
  final Value<String> hostDeviceId;
  final Value<int> hostEpoch;
  final Value<String> hostAddressesJson;
  final Value<int> hostPort;
  final Value<String> certSha256;
  final Value<String> signingPublicKey;
  final Value<String> sealPublicKey;
  final Value<String?> cloudUrl;
  final Value<int> pairedAt;
  final Value<int> cursorEpoch;
  final Value<int> cursorSequence;
  final Value<int?> lastLiveAt;
  const ClientLinkCompanion({
    this.singleton = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.role = const Value.absent(),
    this.deviceName = const Value.absent(),
    this.restaurantId = const Value.absent(),
    this.restaurantName = const Value.absent(),
    this.hostDeviceId = const Value.absent(),
    this.hostEpoch = const Value.absent(),
    this.hostAddressesJson = const Value.absent(),
    this.hostPort = const Value.absent(),
    this.certSha256 = const Value.absent(),
    this.signingPublicKey = const Value.absent(),
    this.sealPublicKey = const Value.absent(),
    this.cloudUrl = const Value.absent(),
    this.pairedAt = const Value.absent(),
    this.cursorEpoch = const Value.absent(),
    this.cursorSequence = const Value.absent(),
    this.lastLiveAt = const Value.absent(),
  });
  ClientLinkCompanion.insert({
    this.singleton = const Value.absent(),
    required String deviceId,
    required String role,
    required String deviceName,
    required String restaurantId,
    required String restaurantName,
    required String hostDeviceId,
    required int hostEpoch,
    required String hostAddressesJson,
    required int hostPort,
    required String certSha256,
    required String signingPublicKey,
    required String sealPublicKey,
    this.cloudUrl = const Value.absent(),
    required int pairedAt,
    this.cursorEpoch = const Value.absent(),
    this.cursorSequence = const Value.absent(),
    this.lastLiveAt = const Value.absent(),
  }) : deviceId = Value(deviceId),
       role = Value(role),
       deviceName = Value(deviceName),
       restaurantId = Value(restaurantId),
       restaurantName = Value(restaurantName),
       hostDeviceId = Value(hostDeviceId),
       hostEpoch = Value(hostEpoch),
       hostAddressesJson = Value(hostAddressesJson),
       hostPort = Value(hostPort),
       certSha256 = Value(certSha256),
       signingPublicKey = Value(signingPublicKey),
       sealPublicKey = Value(sealPublicKey),
       pairedAt = Value(pairedAt);
  static Insertable<ClientLinkRow> custom({
    Expression<int>? singleton,
    Expression<String>? deviceId,
    Expression<String>? role,
    Expression<String>? deviceName,
    Expression<String>? restaurantId,
    Expression<String>? restaurantName,
    Expression<String>? hostDeviceId,
    Expression<int>? hostEpoch,
    Expression<String>? hostAddressesJson,
    Expression<int>? hostPort,
    Expression<String>? certSha256,
    Expression<String>? signingPublicKey,
    Expression<String>? sealPublicKey,
    Expression<String>? cloudUrl,
    Expression<int>? pairedAt,
    Expression<int>? cursorEpoch,
    Expression<int>? cursorSequence,
    Expression<int>? lastLiveAt,
  }) {
    return RawValuesInsertable({
      if (singleton != null) 'singleton': singleton,
      if (deviceId != null) 'device_id': deviceId,
      if (role != null) 'role': role,
      if (deviceName != null) 'device_name': deviceName,
      if (restaurantId != null) 'restaurant_id': restaurantId,
      if (restaurantName != null) 'restaurant_name': restaurantName,
      if (hostDeviceId != null) 'host_device_id': hostDeviceId,
      if (hostEpoch != null) 'host_epoch': hostEpoch,
      if (hostAddressesJson != null) 'host_addresses_json': hostAddressesJson,
      if (hostPort != null) 'host_port': hostPort,
      if (certSha256 != null) 'cert_sha256': certSha256,
      if (signingPublicKey != null) 'signing_public_key': signingPublicKey,
      if (sealPublicKey != null) 'seal_public_key': sealPublicKey,
      if (cloudUrl != null) 'cloud_url': cloudUrl,
      if (pairedAt != null) 'paired_at': pairedAt,
      if (cursorEpoch != null) 'cursor_epoch': cursorEpoch,
      if (cursorSequence != null) 'cursor_sequence': cursorSequence,
      if (lastLiveAt != null) 'last_live_at': lastLiveAt,
    });
  }

  ClientLinkCompanion copyWith({
    Value<int>? singleton,
    Value<String>? deviceId,
    Value<String>? role,
    Value<String>? deviceName,
    Value<String>? restaurantId,
    Value<String>? restaurantName,
    Value<String>? hostDeviceId,
    Value<int>? hostEpoch,
    Value<String>? hostAddressesJson,
    Value<int>? hostPort,
    Value<String>? certSha256,
    Value<String>? signingPublicKey,
    Value<String>? sealPublicKey,
    Value<String?>? cloudUrl,
    Value<int>? pairedAt,
    Value<int>? cursorEpoch,
    Value<int>? cursorSequence,
    Value<int?>? lastLiveAt,
  }) {
    return ClientLinkCompanion(
      singleton: singleton ?? this.singleton,
      deviceId: deviceId ?? this.deviceId,
      role: role ?? this.role,
      deviceName: deviceName ?? this.deviceName,
      restaurantId: restaurantId ?? this.restaurantId,
      restaurantName: restaurantName ?? this.restaurantName,
      hostDeviceId: hostDeviceId ?? this.hostDeviceId,
      hostEpoch: hostEpoch ?? this.hostEpoch,
      hostAddressesJson: hostAddressesJson ?? this.hostAddressesJson,
      hostPort: hostPort ?? this.hostPort,
      certSha256: certSha256 ?? this.certSha256,
      signingPublicKey: signingPublicKey ?? this.signingPublicKey,
      sealPublicKey: sealPublicKey ?? this.sealPublicKey,
      cloudUrl: cloudUrl ?? this.cloudUrl,
      pairedAt: pairedAt ?? this.pairedAt,
      cursorEpoch: cursorEpoch ?? this.cursorEpoch,
      cursorSequence: cursorSequence ?? this.cursorSequence,
      lastLiveAt: lastLiveAt ?? this.lastLiveAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (singleton.present) {
      map['singleton'] = Variable<int>(singleton.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (deviceName.present) {
      map['device_name'] = Variable<String>(deviceName.value);
    }
    if (restaurantId.present) {
      map['restaurant_id'] = Variable<String>(restaurantId.value);
    }
    if (restaurantName.present) {
      map['restaurant_name'] = Variable<String>(restaurantName.value);
    }
    if (hostDeviceId.present) {
      map['host_device_id'] = Variable<String>(hostDeviceId.value);
    }
    if (hostEpoch.present) {
      map['host_epoch'] = Variable<int>(hostEpoch.value);
    }
    if (hostAddressesJson.present) {
      map['host_addresses_json'] = Variable<String>(hostAddressesJson.value);
    }
    if (hostPort.present) {
      map['host_port'] = Variable<int>(hostPort.value);
    }
    if (certSha256.present) {
      map['cert_sha256'] = Variable<String>(certSha256.value);
    }
    if (signingPublicKey.present) {
      map['signing_public_key'] = Variable<String>(signingPublicKey.value);
    }
    if (sealPublicKey.present) {
      map['seal_public_key'] = Variable<String>(sealPublicKey.value);
    }
    if (cloudUrl.present) {
      map['cloud_url'] = Variable<String>(cloudUrl.value);
    }
    if (pairedAt.present) {
      map['paired_at'] = Variable<int>(pairedAt.value);
    }
    if (cursorEpoch.present) {
      map['cursor_epoch'] = Variable<int>(cursorEpoch.value);
    }
    if (cursorSequence.present) {
      map['cursor_sequence'] = Variable<int>(cursorSequence.value);
    }
    if (lastLiveAt.present) {
      map['last_live_at'] = Variable<int>(lastLiveAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ClientLinkCompanion(')
          ..write('singleton: $singleton, ')
          ..write('deviceId: $deviceId, ')
          ..write('role: $role, ')
          ..write('deviceName: $deviceName, ')
          ..write('restaurantId: $restaurantId, ')
          ..write('restaurantName: $restaurantName, ')
          ..write('hostDeviceId: $hostDeviceId, ')
          ..write('hostEpoch: $hostEpoch, ')
          ..write('hostAddressesJson: $hostAddressesJson, ')
          ..write('hostPort: $hostPort, ')
          ..write('certSha256: $certSha256, ')
          ..write('signingPublicKey: $signingPublicKey, ')
          ..write('sealPublicKey: $sealPublicKey, ')
          ..write('cloudUrl: $cloudUrl, ')
          ..write('pairedAt: $pairedAt, ')
          ..write('cursorEpoch: $cursorEpoch, ')
          ..write('cursorSequence: $cursorSequence, ')
          ..write('lastLiveAt: $lastLiveAt')
          ..write(')'))
        .toString();
  }
}

class $ClientSessionsTable extends ClientSessions with TableInfo<$ClientSessionsTable, ClientSessionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ClientSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _singletonMeta = const VerificationMeta(
    'singleton',
  );
  @override
  late final GeneratedColumn<int> singleton = GeneratedColumn<int>(
    'singleton',
    aliasedName,
    false,
    check: () => singleton.equals(1),
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _staffIdMeta = const VerificationMeta(
    'staffId',
  );
  @override
  late final GeneratedColumn<String> staffId = GeneratedColumn<String>(
    'staff_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _expiresAtMeta = const VerificationMeta(
    'expiresAt',
  );
  @override
  late final GeneratedColumn<int> expiresAt = GeneratedColumn<int>(
    'expires_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    singleton,
    staffId,
    name,
    role,
    expiresAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'client_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<ClientSessionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('singleton')) {
      context.handle(
        _singletonMeta,
        singleton.isAcceptableOrUnknown(data['singleton']!, _singletonMeta),
      );
    }
    if (data.containsKey('staff_id')) {
      context.handle(
        _staffIdMeta,
        staffId.isAcceptableOrUnknown(data['staff_id']!, _staffIdMeta),
      );
    } else if (isInserting) {
      context.missing(_staffIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('expires_at')) {
      context.handle(
        _expiresAtMeta,
        expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta),
      );
    } else if (isInserting) {
      context.missing(_expiresAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {singleton};
  @override
  ClientSessionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ClientSessionRow(
      singleton: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}singleton'],
      )!,
      staffId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}staff_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      expiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expires_at'],
      )!,
    );
  }

  @override
  $ClientSessionsTable createAlias(String alias) {
    return $ClientSessionsTable(attachedDatabase, alias);
  }
}

class ClientSessionRow extends DataClass implements Insertable<ClientSessionRow> {
  final int singleton;
  final String staffId;
  final String name;
  final String role;
  final int expiresAt;
  const ClientSessionRow({
    required this.singleton,
    required this.staffId,
    required this.name,
    required this.role,
    required this.expiresAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['singleton'] = Variable<int>(singleton);
    map['staff_id'] = Variable<String>(staffId);
    map['name'] = Variable<String>(name);
    map['role'] = Variable<String>(role);
    map['expires_at'] = Variable<int>(expiresAt);
    return map;
  }

  ClientSessionsCompanion toCompanion(bool nullToAbsent) {
    return ClientSessionsCompanion(
      singleton: Value(singleton),
      staffId: Value(staffId),
      name: Value(name),
      role: Value(role),
      expiresAt: Value(expiresAt),
    );
  }

  factory ClientSessionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ClientSessionRow(
      singleton: serializer.fromJson<int>(json['singleton']),
      staffId: serializer.fromJson<String>(json['staffId']),
      name: serializer.fromJson<String>(json['name']),
      role: serializer.fromJson<String>(json['role']),
      expiresAt: serializer.fromJson<int>(json['expiresAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'singleton': serializer.toJson<int>(singleton),
      'staffId': serializer.toJson<String>(staffId),
      'name': serializer.toJson<String>(name),
      'role': serializer.toJson<String>(role),
      'expiresAt': serializer.toJson<int>(expiresAt),
    };
  }

  ClientSessionRow copyWith({
    int? singleton,
    String? staffId,
    String? name,
    String? role,
    int? expiresAt,
  }) => ClientSessionRow(
    singleton: singleton ?? this.singleton,
    staffId: staffId ?? this.staffId,
    name: name ?? this.name,
    role: role ?? this.role,
    expiresAt: expiresAt ?? this.expiresAt,
  );
  ClientSessionRow copyWithCompanion(ClientSessionsCompanion data) {
    return ClientSessionRow(
      singleton: data.singleton.present ? data.singleton.value : this.singleton,
      staffId: data.staffId.present ? data.staffId.value : this.staffId,
      name: data.name.present ? data.name.value : this.name,
      role: data.role.present ? data.role.value : this.role,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ClientSessionRow(')
          ..write('singleton: $singleton, ')
          ..write('staffId: $staffId, ')
          ..write('name: $name, ')
          ..write('role: $role, ')
          ..write('expiresAt: $expiresAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(singleton, staffId, name, role, expiresAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ClientSessionRow &&
          other.singleton == this.singleton &&
          other.staffId == this.staffId &&
          other.name == this.name &&
          other.role == this.role &&
          other.expiresAt == this.expiresAt);
}

class ClientSessionsCompanion extends UpdateCompanion<ClientSessionRow> {
  final Value<int> singleton;
  final Value<String> staffId;
  final Value<String> name;
  final Value<String> role;
  final Value<int> expiresAt;
  const ClientSessionsCompanion({
    this.singleton = const Value.absent(),
    this.staffId = const Value.absent(),
    this.name = const Value.absent(),
    this.role = const Value.absent(),
    this.expiresAt = const Value.absent(),
  });
  ClientSessionsCompanion.insert({
    this.singleton = const Value.absent(),
    required String staffId,
    required String name,
    required String role,
    required int expiresAt,
  }) : staffId = Value(staffId),
       name = Value(name),
       role = Value(role),
       expiresAt = Value(expiresAt);
  static Insertable<ClientSessionRow> custom({
    Expression<int>? singleton,
    Expression<String>? staffId,
    Expression<String>? name,
    Expression<String>? role,
    Expression<int>? expiresAt,
  }) {
    return RawValuesInsertable({
      if (singleton != null) 'singleton': singleton,
      if (staffId != null) 'staff_id': staffId,
      if (name != null) 'name': name,
      if (role != null) 'role': role,
      if (expiresAt != null) 'expires_at': expiresAt,
    });
  }

  ClientSessionsCompanion copyWith({
    Value<int>? singleton,
    Value<String>? staffId,
    Value<String>? name,
    Value<String>? role,
    Value<int>? expiresAt,
  }) {
    return ClientSessionsCompanion(
      singleton: singleton ?? this.singleton,
      staffId: staffId ?? this.staffId,
      name: name ?? this.name,
      role: role ?? this.role,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (singleton.present) {
      map['singleton'] = Variable<int>(singleton.value);
    }
    if (staffId.present) {
      map['staff_id'] = Variable<String>(staffId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<int>(expiresAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ClientSessionsCompanion(')
          ..write('singleton: $singleton, ')
          ..write('staffId: $staffId, ')
          ..write('name: $name, ')
          ..write('role: $role, ')
          ..write('expiresAt: $expiresAt')
          ..write(')'))
        .toString();
  }
}

class $PendingCommandsTable extends PendingCommands with TableInfo<$PendingCommandsTable, PendingCommandRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingCommandsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _commandIdMeta = const VerificationMeta(
    'commandId',
  );
  @override
  late final GeneratedColumn<String> commandId = GeneratedColumn<String>(
    'command_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _staffIdMeta = const VerificationMeta(
    'staffId',
  );
  @override
  late final GeneratedColumn<String> staffId = GeneratedColumn<String>(
    'staff_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actionMeta = const VerificationMeta('action');
  @override
  late final GeneratedColumn<String> action = GeneratedColumn<String>(
    'action',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _aggregateIdMeta = const VerificationMeta(
    'aggregateId',
  );
  @override
  late final GeneratedColumn<String> aggregateId = GeneratedColumn<String>(
    'aggregate_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bodyJsonMeta = const VerificationMeta(
    'bodyJson',
  );
  @override
  late final GeneratedColumn<String> bodyJson = GeneratedColumn<String>(
    'body_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _summaryMeta = const VerificationMeta(
    'summary',
  );
  @override
  late final GeneratedColumn<String> summary = GeneratedColumn<String>(
    'summary',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _nextAttemptAtMeta = const VerificationMeta(
    'nextAttemptAt',
  );
  @override
  late final GeneratedColumn<int> nextAttemptAt = GeneratedColumn<int>(
    'next_attempt_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastRouteMeta = const VerificationMeta(
    'lastRoute',
  );
  @override
  late final GeneratedColumn<String> lastRoute = GeneratedColumn<String>(
    'last_route',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mailboxStateMeta = const VerificationMeta(
    'mailboxState',
  );
  @override
  late final GeneratedColumn<String> mailboxState = GeneratedColumn<String>(
    'mailbox_state',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _resultJsonMeta = const VerificationMeta(
    'resultJson',
  );
  @override
  late final GeneratedColumn<String> resultJson = GeneratedColumn<String>(
    'result_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _errorCodeMeta = const VerificationMeta(
    'errorCode',
  );
  @override
  late final GeneratedColumn<String> errorCode = GeneratedColumn<String>(
    'error_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _errorMessageMeta = const VerificationMeta(
    'errorMessage',
  );
  @override
  late final GeneratedColumn<String> errorMessage = GeneratedColumn<String>(
    'error_message',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    commandId,
    staffId,
    action,
    aggregateId,
    bodyJson,
    summary,
    state,
    createdAt,
    updatedAt,
    attempts,
    nextAttemptAt,
    lastRoute,
    mailboxState,
    resultJson,
    errorCode,
    errorMessage,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_commands';
  @override
  VerificationContext validateIntegrity(
    Insertable<PendingCommandRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('command_id')) {
      context.handle(
        _commandIdMeta,
        commandId.isAcceptableOrUnknown(data['command_id']!, _commandIdMeta),
      );
    } else if (isInserting) {
      context.missing(_commandIdMeta);
    }
    if (data.containsKey('staff_id')) {
      context.handle(
        _staffIdMeta,
        staffId.isAcceptableOrUnknown(data['staff_id']!, _staffIdMeta),
      );
    } else if (isInserting) {
      context.missing(_staffIdMeta);
    }
    if (data.containsKey('action')) {
      context.handle(
        _actionMeta,
        action.isAcceptableOrUnknown(data['action']!, _actionMeta),
      );
    } else if (isInserting) {
      context.missing(_actionMeta);
    }
    if (data.containsKey('aggregate_id')) {
      context.handle(
        _aggregateIdMeta,
        aggregateId.isAcceptableOrUnknown(
          data['aggregate_id']!,
          _aggregateIdMeta,
        ),
      );
    }
    if (data.containsKey('body_json')) {
      context.handle(
        _bodyJsonMeta,
        bodyJson.isAcceptableOrUnknown(data['body_json']!, _bodyJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyJsonMeta);
    }
    if (data.containsKey('summary')) {
      context.handle(
        _summaryMeta,
        summary.isAcceptableOrUnknown(data['summary']!, _summaryMeta),
      );
    } else if (isInserting) {
      context.missing(_summaryMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
        _nextAttemptAtMeta,
        nextAttemptAt.isAcceptableOrUnknown(
          data['next_attempt_at']!,
          _nextAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('last_route')) {
      context.handle(
        _lastRouteMeta,
        lastRoute.isAcceptableOrUnknown(data['last_route']!, _lastRouteMeta),
      );
    }
    if (data.containsKey('mailbox_state')) {
      context.handle(
        _mailboxStateMeta,
        mailboxState.isAcceptableOrUnknown(
          data['mailbox_state']!,
          _mailboxStateMeta,
        ),
      );
    }
    if (data.containsKey('result_json')) {
      context.handle(
        _resultJsonMeta,
        resultJson.isAcceptableOrUnknown(data['result_json']!, _resultJsonMeta),
      );
    }
    if (data.containsKey('error_code')) {
      context.handle(
        _errorCodeMeta,
        errorCode.isAcceptableOrUnknown(data['error_code']!, _errorCodeMeta),
      );
    }
    if (data.containsKey('error_message')) {
      context.handle(
        _errorMessageMeta,
        errorMessage.isAcceptableOrUnknown(
          data['error_message']!,
          _errorMessageMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {commandId};
  @override
  PendingCommandRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingCommandRow(
      commandId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}command_id'],
      )!,
      staffId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}staff_id'],
      )!,
      action: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action'],
      )!,
      aggregateId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}aggregate_id'],
      ),
      bodyJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body_json'],
      )!,
      summary: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}summary'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      nextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}next_attempt_at'],
      )!,
      lastRoute: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_route'],
      ),
      mailboxState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mailbox_state'],
      ),
      resultJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}result_json'],
      ),
      errorCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_code'],
      ),
      errorMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_message'],
      ),
    );
  }

  @override
  $PendingCommandsTable createAlias(String alias) {
    return $PendingCommandsTable(attachedDatabase, alias);
  }
}

class PendingCommandRow extends DataClass implements Insertable<PendingCommandRow> {
  final String commandId;
  final String staffId;
  final String action;
  final String? aggregateId;
  final String bodyJson;

  /// Short human description ("T4: 2 items").
  final String summary;

  /// queued → sending → accepted | rejected | needs_review | discarded.
  final String state;
  final int createdAt;
  final int updatedAt;
  final int attempts;
  final int nextAttemptAt;

  /// 'lan' or 'cloud' (last route tried) and, for the cloud, the mailbox state.
  final String? lastRoute;
  final String? mailboxState;
  final String? resultJson;
  final String? errorCode;
  final String? errorMessage;
  const PendingCommandRow({
    required this.commandId,
    required this.staffId,
    required this.action,
    this.aggregateId,
    required this.bodyJson,
    required this.summary,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
    required this.attempts,
    required this.nextAttemptAt,
    this.lastRoute,
    this.mailboxState,
    this.resultJson,
    this.errorCode,
    this.errorMessage,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['command_id'] = Variable<String>(commandId);
    map['staff_id'] = Variable<String>(staffId);
    map['action'] = Variable<String>(action);
    if (!nullToAbsent || aggregateId != null) {
      map['aggregate_id'] = Variable<String>(aggregateId);
    }
    map['body_json'] = Variable<String>(bodyJson);
    map['summary'] = Variable<String>(summary);
    map['state'] = Variable<String>(state);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    map['attempts'] = Variable<int>(attempts);
    map['next_attempt_at'] = Variable<int>(nextAttemptAt);
    if (!nullToAbsent || lastRoute != null) {
      map['last_route'] = Variable<String>(lastRoute);
    }
    if (!nullToAbsent || mailboxState != null) {
      map['mailbox_state'] = Variable<String>(mailboxState);
    }
    if (!nullToAbsent || resultJson != null) {
      map['result_json'] = Variable<String>(resultJson);
    }
    if (!nullToAbsent || errorCode != null) {
      map['error_code'] = Variable<String>(errorCode);
    }
    if (!nullToAbsent || errorMessage != null) {
      map['error_message'] = Variable<String>(errorMessage);
    }
    return map;
  }

  PendingCommandsCompanion toCompanion(bool nullToAbsent) {
    return PendingCommandsCompanion(
      commandId: Value(commandId),
      staffId: Value(staffId),
      action: Value(action),
      aggregateId: aggregateId == null && nullToAbsent ? const Value.absent() : Value(aggregateId),
      bodyJson: Value(bodyJson),
      summary: Value(summary),
      state: Value(state),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      attempts: Value(attempts),
      nextAttemptAt: Value(nextAttemptAt),
      lastRoute: lastRoute == null && nullToAbsent ? const Value.absent() : Value(lastRoute),
      mailboxState: mailboxState == null && nullToAbsent ? const Value.absent() : Value(mailboxState),
      resultJson: resultJson == null && nullToAbsent ? const Value.absent() : Value(resultJson),
      errorCode: errorCode == null && nullToAbsent ? const Value.absent() : Value(errorCode),
      errorMessage: errorMessage == null && nullToAbsent ? const Value.absent() : Value(errorMessage),
    );
  }

  factory PendingCommandRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingCommandRow(
      commandId: serializer.fromJson<String>(json['commandId']),
      staffId: serializer.fromJson<String>(json['staffId']),
      action: serializer.fromJson<String>(json['action']),
      aggregateId: serializer.fromJson<String?>(json['aggregateId']),
      bodyJson: serializer.fromJson<String>(json['bodyJson']),
      summary: serializer.fromJson<String>(json['summary']),
      state: serializer.fromJson<String>(json['state']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      attempts: serializer.fromJson<int>(json['attempts']),
      nextAttemptAt: serializer.fromJson<int>(json['nextAttemptAt']),
      lastRoute: serializer.fromJson<String?>(json['lastRoute']),
      mailboxState: serializer.fromJson<String?>(json['mailboxState']),
      resultJson: serializer.fromJson<String?>(json['resultJson']),
      errorCode: serializer.fromJson<String?>(json['errorCode']),
      errorMessage: serializer.fromJson<String?>(json['errorMessage']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'commandId': serializer.toJson<String>(commandId),
      'staffId': serializer.toJson<String>(staffId),
      'action': serializer.toJson<String>(action),
      'aggregateId': serializer.toJson<String?>(aggregateId),
      'bodyJson': serializer.toJson<String>(bodyJson),
      'summary': serializer.toJson<String>(summary),
      'state': serializer.toJson<String>(state),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'attempts': serializer.toJson<int>(attempts),
      'nextAttemptAt': serializer.toJson<int>(nextAttemptAt),
      'lastRoute': serializer.toJson<String?>(lastRoute),
      'mailboxState': serializer.toJson<String?>(mailboxState),
      'resultJson': serializer.toJson<String?>(resultJson),
      'errorCode': serializer.toJson<String?>(errorCode),
      'errorMessage': serializer.toJson<String?>(errorMessage),
    };
  }

  PendingCommandRow copyWith({
    String? commandId,
    String? staffId,
    String? action,
    Value<String?> aggregateId = const Value.absent(),
    String? bodyJson,
    String? summary,
    String? state,
    int? createdAt,
    int? updatedAt,
    int? attempts,
    int? nextAttemptAt,
    Value<String?> lastRoute = const Value.absent(),
    Value<String?> mailboxState = const Value.absent(),
    Value<String?> resultJson = const Value.absent(),
    Value<String?> errorCode = const Value.absent(),
    Value<String?> errorMessage = const Value.absent(),
  }) => PendingCommandRow(
    commandId: commandId ?? this.commandId,
    staffId: staffId ?? this.staffId,
    action: action ?? this.action,
    aggregateId: aggregateId.present ? aggregateId.value : this.aggregateId,
    bodyJson: bodyJson ?? this.bodyJson,
    summary: summary ?? this.summary,
    state: state ?? this.state,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    attempts: attempts ?? this.attempts,
    nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
    lastRoute: lastRoute.present ? lastRoute.value : this.lastRoute,
    mailboxState: mailboxState.present ? mailboxState.value : this.mailboxState,
    resultJson: resultJson.present ? resultJson.value : this.resultJson,
    errorCode: errorCode.present ? errorCode.value : this.errorCode,
    errorMessage: errorMessage.present ? errorMessage.value : this.errorMessage,
  );
  PendingCommandRow copyWithCompanion(PendingCommandsCompanion data) {
    return PendingCommandRow(
      commandId: data.commandId.present ? data.commandId.value : this.commandId,
      staffId: data.staffId.present ? data.staffId.value : this.staffId,
      action: data.action.present ? data.action.value : this.action,
      aggregateId: data.aggregateId.present ? data.aggregateId.value : this.aggregateId,
      bodyJson: data.bodyJson.present ? data.bodyJson.value : this.bodyJson,
      summary: data.summary.present ? data.summary.value : this.summary,
      state: data.state.present ? data.state.value : this.state,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      nextAttemptAt: data.nextAttemptAt.present ? data.nextAttemptAt.value : this.nextAttemptAt,
      lastRoute: data.lastRoute.present ? data.lastRoute.value : this.lastRoute,
      mailboxState: data.mailboxState.present ? data.mailboxState.value : this.mailboxState,
      resultJson: data.resultJson.present ? data.resultJson.value : this.resultJson,
      errorCode: data.errorCode.present ? data.errorCode.value : this.errorCode,
      errorMessage: data.errorMessage.present ? data.errorMessage.value : this.errorMessage,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingCommandRow(')
          ..write('commandId: $commandId, ')
          ..write('staffId: $staffId, ')
          ..write('action: $action, ')
          ..write('aggregateId: $aggregateId, ')
          ..write('bodyJson: $bodyJson, ')
          ..write('summary: $summary, ')
          ..write('state: $state, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastRoute: $lastRoute, ')
          ..write('mailboxState: $mailboxState, ')
          ..write('resultJson: $resultJson, ')
          ..write('errorCode: $errorCode, ')
          ..write('errorMessage: $errorMessage')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    commandId,
    staffId,
    action,
    aggregateId,
    bodyJson,
    summary,
    state,
    createdAt,
    updatedAt,
    attempts,
    nextAttemptAt,
    lastRoute,
    mailboxState,
    resultJson,
    errorCode,
    errorMessage,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingCommandRow &&
          other.commandId == this.commandId &&
          other.staffId == this.staffId &&
          other.action == this.action &&
          other.aggregateId == this.aggregateId &&
          other.bodyJson == this.bodyJson &&
          other.summary == this.summary &&
          other.state == this.state &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.attempts == this.attempts &&
          other.nextAttemptAt == this.nextAttemptAt &&
          other.lastRoute == this.lastRoute &&
          other.mailboxState == this.mailboxState &&
          other.resultJson == this.resultJson &&
          other.errorCode == this.errorCode &&
          other.errorMessage == this.errorMessage);
}

class PendingCommandsCompanion extends UpdateCompanion<PendingCommandRow> {
  final Value<String> commandId;
  final Value<String> staffId;
  final Value<String> action;
  final Value<String?> aggregateId;
  final Value<String> bodyJson;
  final Value<String> summary;
  final Value<String> state;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> attempts;
  final Value<int> nextAttemptAt;
  final Value<String?> lastRoute;
  final Value<String?> mailboxState;
  final Value<String?> resultJson;
  final Value<String?> errorCode;
  final Value<String?> errorMessage;
  final Value<int> rowid;
  const PendingCommandsCompanion({
    this.commandId = const Value.absent(),
    this.staffId = const Value.absent(),
    this.action = const Value.absent(),
    this.aggregateId = const Value.absent(),
    this.bodyJson = const Value.absent(),
    this.summary = const Value.absent(),
    this.state = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastRoute = const Value.absent(),
    this.mailboxState = const Value.absent(),
    this.resultJson = const Value.absent(),
    this.errorCode = const Value.absent(),
    this.errorMessage = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PendingCommandsCompanion.insert({
    required String commandId,
    required String staffId,
    required String action,
    this.aggregateId = const Value.absent(),
    required String bodyJson,
    required String summary,
    required String state,
    required int createdAt,
    required int updatedAt,
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastRoute = const Value.absent(),
    this.mailboxState = const Value.absent(),
    this.resultJson = const Value.absent(),
    this.errorCode = const Value.absent(),
    this.errorMessage = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : commandId = Value(commandId),
       staffId = Value(staffId),
       action = Value(action),
       bodyJson = Value(bodyJson),
       summary = Value(summary),
       state = Value(state),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<PendingCommandRow> custom({
    Expression<String>? commandId,
    Expression<String>? staffId,
    Expression<String>? action,
    Expression<String>? aggregateId,
    Expression<String>? bodyJson,
    Expression<String>? summary,
    Expression<String>? state,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? attempts,
    Expression<int>? nextAttemptAt,
    Expression<String>? lastRoute,
    Expression<String>? mailboxState,
    Expression<String>? resultJson,
    Expression<String>? errorCode,
    Expression<String>? errorMessage,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (commandId != null) 'command_id': commandId,
      if (staffId != null) 'staff_id': staffId,
      if (action != null) 'action': action,
      if (aggregateId != null) 'aggregate_id': aggregateId,
      if (bodyJson != null) 'body_json': bodyJson,
      if (summary != null) 'summary': summary,
      if (state != null) 'state': state,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (attempts != null) 'attempts': attempts,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (lastRoute != null) 'last_route': lastRoute,
      if (mailboxState != null) 'mailbox_state': mailboxState,
      if (resultJson != null) 'result_json': resultJson,
      if (errorCode != null) 'error_code': errorCode,
      if (errorMessage != null) 'error_message': errorMessage,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PendingCommandsCompanion copyWith({
    Value<String>? commandId,
    Value<String>? staffId,
    Value<String>? action,
    Value<String?>? aggregateId,
    Value<String>? bodyJson,
    Value<String>? summary,
    Value<String>? state,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int>? attempts,
    Value<int>? nextAttemptAt,
    Value<String?>? lastRoute,
    Value<String?>? mailboxState,
    Value<String?>? resultJson,
    Value<String?>? errorCode,
    Value<String?>? errorMessage,
    Value<int>? rowid,
  }) {
    return PendingCommandsCompanion(
      commandId: commandId ?? this.commandId,
      staffId: staffId ?? this.staffId,
      action: action ?? this.action,
      aggregateId: aggregateId ?? this.aggregateId,
      bodyJson: bodyJson ?? this.bodyJson,
      summary: summary ?? this.summary,
      state: state ?? this.state,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      attempts: attempts ?? this.attempts,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      lastRoute: lastRoute ?? this.lastRoute,
      mailboxState: mailboxState ?? this.mailboxState,
      resultJson: resultJson ?? this.resultJson,
      errorCode: errorCode ?? this.errorCode,
      errorMessage: errorMessage ?? this.errorMessage,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (commandId.present) {
      map['command_id'] = Variable<String>(commandId.value);
    }
    if (staffId.present) {
      map['staff_id'] = Variable<String>(staffId.value);
    }
    if (action.present) {
      map['action'] = Variable<String>(action.value);
    }
    if (aggregateId.present) {
      map['aggregate_id'] = Variable<String>(aggregateId.value);
    }
    if (bodyJson.present) {
      map['body_json'] = Variable<String>(bodyJson.value);
    }
    if (summary.present) {
      map['summary'] = Variable<String>(summary.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<int>(nextAttemptAt.value);
    }
    if (lastRoute.present) {
      map['last_route'] = Variable<String>(lastRoute.value);
    }
    if (mailboxState.present) {
      map['mailbox_state'] = Variable<String>(mailboxState.value);
    }
    if (resultJson.present) {
      map['result_json'] = Variable<String>(resultJson.value);
    }
    if (errorCode.present) {
      map['error_code'] = Variable<String>(errorCode.value);
    }
    if (errorMessage.present) {
      map['error_message'] = Variable<String>(errorMessage.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingCommandsCompanion(')
          ..write('commandId: $commandId, ')
          ..write('staffId: $staffId, ')
          ..write('action: $action, ')
          ..write('aggregateId: $aggregateId, ')
          ..write('bodyJson: $bodyJson, ')
          ..write('summary: $summary, ')
          ..write('state: $state, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastRoute: $lastRoute, ')
          ..write('mailboxState: $mailboxState, ')
          ..write('resultJson: $resultJson, ')
          ..write('errorCode: $errorCode, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DraftsTable extends Drafts with TableInfo<$DraftsTable, DraftRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DraftsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _staffIdMeta = const VerificationMeta(
    'staffId',
  );
  @override
  late final GeneratedColumn<String> staffId = GeneratedColumn<String>(
    'staff_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _orderTypeMeta = const VerificationMeta(
    'orderType',
  );
  @override
  late final GeneratedColumn<String> orderType = GeneratedColumn<String>(
    'order_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tableIdMeta = const VerificationMeta(
    'tableId',
  );
  @override
  late final GeneratedColumn<String> tableId = GeneratedColumn<String>(
    'table_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tableLabelMeta = const VerificationMeta(
    'tableLabel',
  );
  @override
  late final GeneratedColumn<String> tableLabel = GeneratedColumn<String>(
    'table_label',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _orderIdMeta = const VerificationMeta(
    'orderId',
  );
  @override
  late final GeneratedColumn<String> orderId = GeneratedColumn<String>(
    'order_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _guestCountMeta = const VerificationMeta(
    'guestCount',
  );
  @override
  late final GeneratedColumn<int> guestCount = GeneratedColumn<int>(
    'guest_count',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _linesJsonMeta = const VerificationMeta(
    'linesJson',
  );
  @override
  late final GeneratedColumn<String> linesJson = GeneratedColumn<String>(
    'lines_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    staffId,
    orderType,
    tableId,
    tableLabel,
    orderId,
    guestCount,
    linesJson,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'drafts';
  @override
  VerificationContext validateIntegrity(
    Insertable<DraftRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('staff_id')) {
      context.handle(
        _staffIdMeta,
        staffId.isAcceptableOrUnknown(data['staff_id']!, _staffIdMeta),
      );
    } else if (isInserting) {
      context.missing(_staffIdMeta);
    }
    if (data.containsKey('order_type')) {
      context.handle(
        _orderTypeMeta,
        orderType.isAcceptableOrUnknown(data['order_type']!, _orderTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_orderTypeMeta);
    }
    if (data.containsKey('table_id')) {
      context.handle(
        _tableIdMeta,
        tableId.isAcceptableOrUnknown(data['table_id']!, _tableIdMeta),
      );
    }
    if (data.containsKey('table_label')) {
      context.handle(
        _tableLabelMeta,
        tableLabel.isAcceptableOrUnknown(data['table_label']!, _tableLabelMeta),
      );
    }
    if (data.containsKey('order_id')) {
      context.handle(
        _orderIdMeta,
        orderId.isAcceptableOrUnknown(data['order_id']!, _orderIdMeta),
      );
    }
    if (data.containsKey('guest_count')) {
      context.handle(
        _guestCountMeta,
        guestCount.isAcceptableOrUnknown(data['guest_count']!, _guestCountMeta),
      );
    }
    if (data.containsKey('lines_json')) {
      context.handle(
        _linesJsonMeta,
        linesJson.isAcceptableOrUnknown(data['lines_json']!, _linesJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_linesJsonMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DraftRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DraftRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      staffId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}staff_id'],
      )!,
      orderType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}order_type'],
      )!,
      tableId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}table_id'],
      ),
      tableLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}table_label'],
      ),
      orderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}order_id'],
      ),
      guestCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}guest_count'],
      ),
      linesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lines_json'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $DraftsTable createAlias(String alias) {
    return $DraftsTable(attachedDatabase, alias);
  }
}

class DraftRow extends DataClass implements Insertable<DraftRow> {
  final String id;
  final String staffId;

  /// 'dine_in' or 'takeaway'.
  final String orderType;
  final String? tableId;
  final String? tableLabel;

  /// Set when adding to an order the POS already accepted.
  final String? orderId;
  final int? guestCount;
  final String linesJson;
  final int createdAt;
  final int updatedAt;
  const DraftRow({
    required this.id,
    required this.staffId,
    required this.orderType,
    this.tableId,
    this.tableLabel,
    this.orderId,
    this.guestCount,
    required this.linesJson,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['staff_id'] = Variable<String>(staffId);
    map['order_type'] = Variable<String>(orderType);
    if (!nullToAbsent || tableId != null) {
      map['table_id'] = Variable<String>(tableId);
    }
    if (!nullToAbsent || tableLabel != null) {
      map['table_label'] = Variable<String>(tableLabel);
    }
    if (!nullToAbsent || orderId != null) {
      map['order_id'] = Variable<String>(orderId);
    }
    if (!nullToAbsent || guestCount != null) {
      map['guest_count'] = Variable<int>(guestCount);
    }
    map['lines_json'] = Variable<String>(linesJson);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  DraftsCompanion toCompanion(bool nullToAbsent) {
    return DraftsCompanion(
      id: Value(id),
      staffId: Value(staffId),
      orderType: Value(orderType),
      tableId: tableId == null && nullToAbsent ? const Value.absent() : Value(tableId),
      tableLabel: tableLabel == null && nullToAbsent ? const Value.absent() : Value(tableLabel),
      orderId: orderId == null && nullToAbsent ? const Value.absent() : Value(orderId),
      guestCount: guestCount == null && nullToAbsent ? const Value.absent() : Value(guestCount),
      linesJson: Value(linesJson),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory DraftRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DraftRow(
      id: serializer.fromJson<String>(json['id']),
      staffId: serializer.fromJson<String>(json['staffId']),
      orderType: serializer.fromJson<String>(json['orderType']),
      tableId: serializer.fromJson<String?>(json['tableId']),
      tableLabel: serializer.fromJson<String?>(json['tableLabel']),
      orderId: serializer.fromJson<String?>(json['orderId']),
      guestCount: serializer.fromJson<int?>(json['guestCount']),
      linesJson: serializer.fromJson<String>(json['linesJson']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'staffId': serializer.toJson<String>(staffId),
      'orderType': serializer.toJson<String>(orderType),
      'tableId': serializer.toJson<String?>(tableId),
      'tableLabel': serializer.toJson<String?>(tableLabel),
      'orderId': serializer.toJson<String?>(orderId),
      'guestCount': serializer.toJson<int?>(guestCount),
      'linesJson': serializer.toJson<String>(linesJson),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  DraftRow copyWith({
    String? id,
    String? staffId,
    String? orderType,
    Value<String?> tableId = const Value.absent(),
    Value<String?> tableLabel = const Value.absent(),
    Value<String?> orderId = const Value.absent(),
    Value<int?> guestCount = const Value.absent(),
    String? linesJson,
    int? createdAt,
    int? updatedAt,
  }) => DraftRow(
    id: id ?? this.id,
    staffId: staffId ?? this.staffId,
    orderType: orderType ?? this.orderType,
    tableId: tableId.present ? tableId.value : this.tableId,
    tableLabel: tableLabel.present ? tableLabel.value : this.tableLabel,
    orderId: orderId.present ? orderId.value : this.orderId,
    guestCount: guestCount.present ? guestCount.value : this.guestCount,
    linesJson: linesJson ?? this.linesJson,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  DraftRow copyWithCompanion(DraftsCompanion data) {
    return DraftRow(
      id: data.id.present ? data.id.value : this.id,
      staffId: data.staffId.present ? data.staffId.value : this.staffId,
      orderType: data.orderType.present ? data.orderType.value : this.orderType,
      tableId: data.tableId.present ? data.tableId.value : this.tableId,
      tableLabel: data.tableLabel.present ? data.tableLabel.value : this.tableLabel,
      orderId: data.orderId.present ? data.orderId.value : this.orderId,
      guestCount: data.guestCount.present ? data.guestCount.value : this.guestCount,
      linesJson: data.linesJson.present ? data.linesJson.value : this.linesJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DraftRow(')
          ..write('id: $id, ')
          ..write('staffId: $staffId, ')
          ..write('orderType: $orderType, ')
          ..write('tableId: $tableId, ')
          ..write('tableLabel: $tableLabel, ')
          ..write('orderId: $orderId, ')
          ..write('guestCount: $guestCount, ')
          ..write('linesJson: $linesJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    staffId,
    orderType,
    tableId,
    tableLabel,
    orderId,
    guestCount,
    linesJson,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DraftRow &&
          other.id == this.id &&
          other.staffId == this.staffId &&
          other.orderType == this.orderType &&
          other.tableId == this.tableId &&
          other.tableLabel == this.tableLabel &&
          other.orderId == this.orderId &&
          other.guestCount == this.guestCount &&
          other.linesJson == this.linesJson &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class DraftsCompanion extends UpdateCompanion<DraftRow> {
  final Value<String> id;
  final Value<String> staffId;
  final Value<String> orderType;
  final Value<String?> tableId;
  final Value<String?> tableLabel;
  final Value<String?> orderId;
  final Value<int?> guestCount;
  final Value<String> linesJson;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const DraftsCompanion({
    this.id = const Value.absent(),
    this.staffId = const Value.absent(),
    this.orderType = const Value.absent(),
    this.tableId = const Value.absent(),
    this.tableLabel = const Value.absent(),
    this.orderId = const Value.absent(),
    this.guestCount = const Value.absent(),
    this.linesJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DraftsCompanion.insert({
    required String id,
    required String staffId,
    required String orderType,
    this.tableId = const Value.absent(),
    this.tableLabel = const Value.absent(),
    this.orderId = const Value.absent(),
    this.guestCount = const Value.absent(),
    required String linesJson,
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       staffId = Value(staffId),
       orderType = Value(orderType),
       linesJson = Value(linesJson),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<DraftRow> custom({
    Expression<String>? id,
    Expression<String>? staffId,
    Expression<String>? orderType,
    Expression<String>? tableId,
    Expression<String>? tableLabel,
    Expression<String>? orderId,
    Expression<int>? guestCount,
    Expression<String>? linesJson,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (staffId != null) 'staff_id': staffId,
      if (orderType != null) 'order_type': orderType,
      if (tableId != null) 'table_id': tableId,
      if (tableLabel != null) 'table_label': tableLabel,
      if (orderId != null) 'order_id': orderId,
      if (guestCount != null) 'guest_count': guestCount,
      if (linesJson != null) 'lines_json': linesJson,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DraftsCompanion copyWith({
    Value<String>? id,
    Value<String>? staffId,
    Value<String>? orderType,
    Value<String?>? tableId,
    Value<String?>? tableLabel,
    Value<String?>? orderId,
    Value<int?>? guestCount,
    Value<String>? linesJson,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return DraftsCompanion(
      id: id ?? this.id,
      staffId: staffId ?? this.staffId,
      orderType: orderType ?? this.orderType,
      tableId: tableId ?? this.tableId,
      tableLabel: tableLabel ?? this.tableLabel,
      orderId: orderId ?? this.orderId,
      guestCount: guestCount ?? this.guestCount,
      linesJson: linesJson ?? this.linesJson,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (staffId.present) {
      map['staff_id'] = Variable<String>(staffId.value);
    }
    if (orderType.present) {
      map['order_type'] = Variable<String>(orderType.value);
    }
    if (tableId.present) {
      map['table_id'] = Variable<String>(tableId.value);
    }
    if (tableLabel.present) {
      map['table_label'] = Variable<String>(tableLabel.value);
    }
    if (orderId.present) {
      map['order_id'] = Variable<String>(orderId.value);
    }
    if (guestCount.present) {
      map['guest_count'] = Variable<int>(guestCount.value);
    }
    if (linesJson.present) {
      map['lines_json'] = Variable<String>(linesJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DraftsCompanion(')
          ..write('id: $id, ')
          ..write('staffId: $staffId, ')
          ..write('orderType: $orderType, ')
          ..write('tableId: $tableId, ')
          ..write('tableLabel: $tableLabel, ')
          ..write('orderId: $orderId, ')
          ..write('guestCount: $guestCount, ')
          ..write('linesJson: $linesJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CacheEntriesTable extends CacheEntries with TableInfo<$CacheEntriesTable, CacheEntryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CacheEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, kind, json, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cache_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<CacheEntryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  CacheEntryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CacheEntryRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CacheEntriesTable createAlias(String alias) {
    return $CacheEntriesTable(attachedDatabase, alias);
  }
}

class CacheEntryRow extends DataClass implements Insertable<CacheEntryRow> {
  final String key;
  final String kind;
  final String json;
  final int updatedAt;
  const CacheEntryRow({
    required this.key,
    required this.kind,
    required this.json,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['kind'] = Variable<String>(kind);
    map['json'] = Variable<String>(json);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  CacheEntriesCompanion toCompanion(bool nullToAbsent) {
    return CacheEntriesCompanion(
      key: Value(key),
      kind: Value(kind),
      json: Value(json),
      updatedAt: Value(updatedAt),
    );
  }

  factory CacheEntryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CacheEntryRow(
      key: serializer.fromJson<String>(json['key']),
      kind: serializer.fromJson<String>(json['kind']),
      json: serializer.fromJson<String>(json['json']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'kind': serializer.toJson<String>(kind),
      'json': serializer.toJson<String>(json),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  CacheEntryRow copyWith({
    String? key,
    String? kind,
    String? json,
    int? updatedAt,
  }) => CacheEntryRow(
    key: key ?? this.key,
    kind: kind ?? this.kind,
    json: json ?? this.json,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  CacheEntryRow copyWithCompanion(CacheEntriesCompanion data) {
    return CacheEntryRow(
      key: data.key.present ? data.key.value : this.key,
      kind: data.kind.present ? data.kind.value : this.kind,
      json: data.json.present ? data.json.value : this.json,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CacheEntryRow(')
          ..write('key: $key, ')
          ..write('kind: $kind, ')
          ..write('json: $json, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, kind, json, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CacheEntryRow &&
          other.key == this.key &&
          other.kind == this.kind &&
          other.json == this.json &&
          other.updatedAt == this.updatedAt);
}

class CacheEntriesCompanion extends UpdateCompanion<CacheEntryRow> {
  final Value<String> key;
  final Value<String> kind;
  final Value<String> json;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const CacheEntriesCompanion({
    this.key = const Value.absent(),
    this.kind = const Value.absent(),
    this.json = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CacheEntriesCompanion.insert({
    required String key,
    required String kind,
    required String json,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       kind = Value(kind),
       json = Value(json),
       updatedAt = Value(updatedAt);
  static Insertable<CacheEntryRow> custom({
    Expression<String>? key,
    Expression<String>? kind,
    Expression<String>? json,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (kind != null) 'kind': kind,
      if (json != null) 'json': json,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CacheEntriesCompanion copyWith({
    Value<String>? key,
    Value<String>? kind,
    Value<String>? json,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return CacheEntriesCompanion(
      key: key ?? this.key,
      kind: kind ?? this.kind,
      json: json ?? this.json,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CacheEntriesCompanion(')
          ..write('key: $key, ')
          ..write('kind: $kind, ')
          ..write('json: $json, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TicketAlertsTable extends TicketAlerts with TableInfo<$TicketAlertsTable, TicketAlertRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TicketAlertsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ticketIdMeta = const VerificationMeta(
    'ticketId',
  );
  @override
  late final GeneratedColumn<String> ticketId = GeneratedColumn<String>(
    'ticket_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _alertedAtMeta = const VerificationMeta(
    'alertedAt',
  );
  @override
  late final GeneratedColumn<int> alertedAt = GeneratedColumn<int>(
    'alerted_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _soundedMeta = const VerificationMeta(
    'sounded',
  );
  @override
  late final GeneratedColumn<bool> sounded = GeneratedColumn<bool>(
    'sounded',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("sounded" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [ticketId, alertedAt, sounded];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ticket_alerts';
  @override
  VerificationContext validateIntegrity(
    Insertable<TicketAlertRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('ticket_id')) {
      context.handle(
        _ticketIdMeta,
        ticketId.isAcceptableOrUnknown(data['ticket_id']!, _ticketIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ticketIdMeta);
    }
    if (data.containsKey('alerted_at')) {
      context.handle(
        _alertedAtMeta,
        alertedAt.isAcceptableOrUnknown(data['alerted_at']!, _alertedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_alertedAtMeta);
    }
    if (data.containsKey('sounded')) {
      context.handle(
        _soundedMeta,
        sounded.isAcceptableOrUnknown(data['sounded']!, _soundedMeta),
      );
    } else if (isInserting) {
      context.missing(_soundedMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ticketId};
  @override
  TicketAlertRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TicketAlertRow(
      ticketId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ticket_id'],
      )!,
      alertedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}alerted_at'],
      )!,
      sounded: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}sounded'],
      )!,
    );
  }

  @override
  $TicketAlertsTable createAlias(String alias) {
    return $TicketAlertsTable(attachedDatabase, alias);
  }
}

class TicketAlertRow extends DataClass implements Insertable<TicketAlertRow> {
  final String ticketId;
  final int alertedAt;

  /// False when recorded silently (already on the board when first loaded).
  final bool sounded;
  const TicketAlertRow({
    required this.ticketId,
    required this.alertedAt,
    required this.sounded,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['ticket_id'] = Variable<String>(ticketId);
    map['alerted_at'] = Variable<int>(alertedAt);
    map['sounded'] = Variable<bool>(sounded);
    return map;
  }

  TicketAlertsCompanion toCompanion(bool nullToAbsent) {
    return TicketAlertsCompanion(
      ticketId: Value(ticketId),
      alertedAt: Value(alertedAt),
      sounded: Value(sounded),
    );
  }

  factory TicketAlertRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TicketAlertRow(
      ticketId: serializer.fromJson<String>(json['ticketId']),
      alertedAt: serializer.fromJson<int>(json['alertedAt']),
      sounded: serializer.fromJson<bool>(json['sounded']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ticketId': serializer.toJson<String>(ticketId),
      'alertedAt': serializer.toJson<int>(alertedAt),
      'sounded': serializer.toJson<bool>(sounded),
    };
  }

  TicketAlertRow copyWith({String? ticketId, int? alertedAt, bool? sounded}) => TicketAlertRow(
    ticketId: ticketId ?? this.ticketId,
    alertedAt: alertedAt ?? this.alertedAt,
    sounded: sounded ?? this.sounded,
  );
  TicketAlertRow copyWithCompanion(TicketAlertsCompanion data) {
    return TicketAlertRow(
      ticketId: data.ticketId.present ? data.ticketId.value : this.ticketId,
      alertedAt: data.alertedAt.present ? data.alertedAt.value : this.alertedAt,
      sounded: data.sounded.present ? data.sounded.value : this.sounded,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TicketAlertRow(')
          ..write('ticketId: $ticketId, ')
          ..write('alertedAt: $alertedAt, ')
          ..write('sounded: $sounded')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(ticketId, alertedAt, sounded);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TicketAlertRow &&
          other.ticketId == this.ticketId &&
          other.alertedAt == this.alertedAt &&
          other.sounded == this.sounded);
}

class TicketAlertsCompanion extends UpdateCompanion<TicketAlertRow> {
  final Value<String> ticketId;
  final Value<int> alertedAt;
  final Value<bool> sounded;
  final Value<int> rowid;
  const TicketAlertsCompanion({
    this.ticketId = const Value.absent(),
    this.alertedAt = const Value.absent(),
    this.sounded = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TicketAlertsCompanion.insert({
    required String ticketId,
    required int alertedAt,
    required bool sounded,
    this.rowid = const Value.absent(),
  }) : ticketId = Value(ticketId),
       alertedAt = Value(alertedAt),
       sounded = Value(sounded);
  static Insertable<TicketAlertRow> custom({
    Expression<String>? ticketId,
    Expression<int>? alertedAt,
    Expression<bool>? sounded,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ticketId != null) 'ticket_id': ticketId,
      if (alertedAt != null) 'alerted_at': alertedAt,
      if (sounded != null) 'sounded': sounded,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TicketAlertsCompanion copyWith({
    Value<String>? ticketId,
    Value<int>? alertedAt,
    Value<bool>? sounded,
    Value<int>? rowid,
  }) {
    return TicketAlertsCompanion(
      ticketId: ticketId ?? this.ticketId,
      alertedAt: alertedAt ?? this.alertedAt,
      sounded: sounded ?? this.sounded,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ticketId.present) {
      map['ticket_id'] = Variable<String>(ticketId.value);
    }
    if (alertedAt.present) {
      map['alerted_at'] = Variable<int>(alertedAt.value);
    }
    if (sounded.present) {
      map['sounded'] = Variable<bool>(sounded.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TicketAlertsCompanion(')
          ..write('ticketId: $ticketId, ')
          ..write('alertedAt: $alertedAt, ')
          ..write('sounded: $sounded, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$ClientDatabase extends GeneratedDatabase {
  _$ClientDatabase(QueryExecutor e) : super(e);
  $ClientDatabaseManager get managers => $ClientDatabaseManager(this);
  late final $ClientLinkTable clientLink = $ClientLinkTable(this);
  late final $ClientSessionsTable clientSessions = $ClientSessionsTable(this);
  late final $PendingCommandsTable pendingCommands = $PendingCommandsTable(
    this,
  );
  late final $DraftsTable drafts = $DraftsTable(this);
  late final $CacheEntriesTable cacheEntries = $CacheEntriesTable(this);
  late final $TicketAlertsTable ticketAlerts = $TicketAlertsTable(this);
  late final Index pendingCommandsStaffState = Index(
    'pending_commands_staff_state',
    'CREATE INDEX pending_commands_staff_state ON pending_commands (staff_id, state)',
  );
  late final Index draftsStaff = Index(
    'drafts_staff',
    'CREATE INDEX drafts_staff ON drafts (staff_id)',
  );
  late final Index cacheEntriesKind = Index(
    'cache_entries_kind',
    'CREATE INDEX cache_entries_kind ON cache_entries (kind)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    clientLink,
    clientSessions,
    pendingCommands,
    drafts,
    cacheEntries,
    ticketAlerts,
    pendingCommandsStaffState,
    draftsStaff,
    cacheEntriesKind,
  ];
}

typedef $$ClientLinkTableCreateCompanionBuilder =
    ClientLinkCompanion Function({
      Value<int> singleton,
      required String deviceId,
      required String role,
      required String deviceName,
      required String restaurantId,
      required String restaurantName,
      required String hostDeviceId,
      required int hostEpoch,
      required String hostAddressesJson,
      required int hostPort,
      required String certSha256,
      required String signingPublicKey,
      required String sealPublicKey,
      Value<String?> cloudUrl,
      required int pairedAt,
      Value<int> cursorEpoch,
      Value<int> cursorSequence,
      Value<int?> lastLiveAt,
    });
typedef $$ClientLinkTableUpdateCompanionBuilder =
    ClientLinkCompanion Function({
      Value<int> singleton,
      Value<String> deviceId,
      Value<String> role,
      Value<String> deviceName,
      Value<String> restaurantId,
      Value<String> restaurantName,
      Value<String> hostDeviceId,
      Value<int> hostEpoch,
      Value<String> hostAddressesJson,
      Value<int> hostPort,
      Value<String> certSha256,
      Value<String> signingPublicKey,
      Value<String> sealPublicKey,
      Value<String?> cloudUrl,
      Value<int> pairedAt,
      Value<int> cursorEpoch,
      Value<int> cursorSequence,
      Value<int?> lastLiveAt,
    });

class $$ClientLinkTableFilterComposer extends Composer<_$ClientDatabase, $ClientLinkTable> {
  $$ClientLinkTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get singleton => $composableBuilder(
    column: $table.singleton,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceName => $composableBuilder(
    column: $table.deviceName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get restaurantId => $composableBuilder(
    column: $table.restaurantId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get restaurantName => $composableBuilder(
    column: $table.restaurantName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hostDeviceId => $composableBuilder(
    column: $table.hostDeviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get hostEpoch => $composableBuilder(
    column: $table.hostEpoch,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hostAddressesJson => $composableBuilder(
    column: $table.hostAddressesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get hostPort => $composableBuilder(
    column: $table.hostPort,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get certSha256 => $composableBuilder(
    column: $table.certSha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get signingPublicKey => $composableBuilder(
    column: $table.signingPublicKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sealPublicKey => $composableBuilder(
    column: $table.sealPublicKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cloudUrl => $composableBuilder(
    column: $table.cloudUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pairedAt => $composableBuilder(
    column: $table.pairedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cursorEpoch => $composableBuilder(
    column: $table.cursorEpoch,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cursorSequence => $composableBuilder(
    column: $table.cursorSequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastLiveAt => $composableBuilder(
    column: $table.lastLiveAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ClientLinkTableOrderingComposer extends Composer<_$ClientDatabase, $ClientLinkTable> {
  $$ClientLinkTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get singleton => $composableBuilder(
    column: $table.singleton,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceName => $composableBuilder(
    column: $table.deviceName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get restaurantId => $composableBuilder(
    column: $table.restaurantId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get restaurantName => $composableBuilder(
    column: $table.restaurantName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hostDeviceId => $composableBuilder(
    column: $table.hostDeviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get hostEpoch => $composableBuilder(
    column: $table.hostEpoch,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hostAddressesJson => $composableBuilder(
    column: $table.hostAddressesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get hostPort => $composableBuilder(
    column: $table.hostPort,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get certSha256 => $composableBuilder(
    column: $table.certSha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get signingPublicKey => $composableBuilder(
    column: $table.signingPublicKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sealPublicKey => $composableBuilder(
    column: $table.sealPublicKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cloudUrl => $composableBuilder(
    column: $table.cloudUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pairedAt => $composableBuilder(
    column: $table.pairedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cursorEpoch => $composableBuilder(
    column: $table.cursorEpoch,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cursorSequence => $composableBuilder(
    column: $table.cursorSequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastLiveAt => $composableBuilder(
    column: $table.lastLiveAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ClientLinkTableAnnotationComposer extends Composer<_$ClientDatabase, $ClientLinkTable> {
  $$ClientLinkTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get singleton => $composableBuilder(column: $table.singleton, builder: (column) => column);

  GeneratedColumn<String> get deviceId => $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get role => $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get deviceName => $composableBuilder(
    column: $table.deviceName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get restaurantId => $composableBuilder(
    column: $table.restaurantId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get restaurantName => $composableBuilder(
    column: $table.restaurantName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get hostDeviceId => $composableBuilder(
    column: $table.hostDeviceId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get hostEpoch => $composableBuilder(column: $table.hostEpoch, builder: (column) => column);

  GeneratedColumn<String> get hostAddressesJson => $composableBuilder(
    column: $table.hostAddressesJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get hostPort => $composableBuilder(column: $table.hostPort, builder: (column) => column);

  GeneratedColumn<String> get certSha256 => $composableBuilder(
    column: $table.certSha256,
    builder: (column) => column,
  );

  GeneratedColumn<String> get signingPublicKey => $composableBuilder(
    column: $table.signingPublicKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sealPublicKey => $composableBuilder(
    column: $table.sealPublicKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cloudUrl => $composableBuilder(column: $table.cloudUrl, builder: (column) => column);

  GeneratedColumn<int> get pairedAt => $composableBuilder(column: $table.pairedAt, builder: (column) => column);

  GeneratedColumn<int> get cursorEpoch => $composableBuilder(
    column: $table.cursorEpoch,
    builder: (column) => column,
  );

  GeneratedColumn<int> get cursorSequence => $composableBuilder(
    column: $table.cursorSequence,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastLiveAt => $composableBuilder(
    column: $table.lastLiveAt,
    builder: (column) => column,
  );
}

class $$ClientLinkTableTableManager
    extends
        RootTableManager<
          _$ClientDatabase,
          $ClientLinkTable,
          ClientLinkRow,
          $$ClientLinkTableFilterComposer,
          $$ClientLinkTableOrderingComposer,
          $$ClientLinkTableAnnotationComposer,
          $$ClientLinkTableCreateCompanionBuilder,
          $$ClientLinkTableUpdateCompanionBuilder,
          (
            ClientLinkRow,
            BaseReferences<_$ClientDatabase, $ClientLinkTable, ClientLinkRow>,
          ),
          ClientLinkRow,
          PrefetchHooks Function()
        > {
  $$ClientLinkTableTableManager(_$ClientDatabase db, $ClientLinkTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$ClientLinkTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$ClientLinkTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () => $$ClientLinkTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> singleton = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<String> deviceName = const Value.absent(),
                Value<String> restaurantId = const Value.absent(),
                Value<String> restaurantName = const Value.absent(),
                Value<String> hostDeviceId = const Value.absent(),
                Value<int> hostEpoch = const Value.absent(),
                Value<String> hostAddressesJson = const Value.absent(),
                Value<int> hostPort = const Value.absent(),
                Value<String> certSha256 = const Value.absent(),
                Value<String> signingPublicKey = const Value.absent(),
                Value<String> sealPublicKey = const Value.absent(),
                Value<String?> cloudUrl = const Value.absent(),
                Value<int> pairedAt = const Value.absent(),
                Value<int> cursorEpoch = const Value.absent(),
                Value<int> cursorSequence = const Value.absent(),
                Value<int?> lastLiveAt = const Value.absent(),
              }) => ClientLinkCompanion(
                singleton: singleton,
                deviceId: deviceId,
                role: role,
                deviceName: deviceName,
                restaurantId: restaurantId,
                restaurantName: restaurantName,
                hostDeviceId: hostDeviceId,
                hostEpoch: hostEpoch,
                hostAddressesJson: hostAddressesJson,
                hostPort: hostPort,
                certSha256: certSha256,
                signingPublicKey: signingPublicKey,
                sealPublicKey: sealPublicKey,
                cloudUrl: cloudUrl,
                pairedAt: pairedAt,
                cursorEpoch: cursorEpoch,
                cursorSequence: cursorSequence,
                lastLiveAt: lastLiveAt,
              ),
          createCompanionCallback:
              ({
                Value<int> singleton = const Value.absent(),
                required String deviceId,
                required String role,
                required String deviceName,
                required String restaurantId,
                required String restaurantName,
                required String hostDeviceId,
                required int hostEpoch,
                required String hostAddressesJson,
                required int hostPort,
                required String certSha256,
                required String signingPublicKey,
                required String sealPublicKey,
                Value<String?> cloudUrl = const Value.absent(),
                required int pairedAt,
                Value<int> cursorEpoch = const Value.absent(),
                Value<int> cursorSequence = const Value.absent(),
                Value<int?> lastLiveAt = const Value.absent(),
              }) => ClientLinkCompanion.insert(
                singleton: singleton,
                deviceId: deviceId,
                role: role,
                deviceName: deviceName,
                restaurantId: restaurantId,
                restaurantName: restaurantName,
                hostDeviceId: hostDeviceId,
                hostEpoch: hostEpoch,
                hostAddressesJson: hostAddressesJson,
                hostPort: hostPort,
                certSha256: certSha256,
                signingPublicKey: signingPublicKey,
                sealPublicKey: sealPublicKey,
                cloudUrl: cloudUrl,
                pairedAt: pairedAt,
                cursorEpoch: cursorEpoch,
                cursorSequence: cursorSequence,
                lastLiveAt: lastLiveAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ClientLinkTable, ClientLinkRow>(table),
                  BaseReferences<_$ClientDatabase, $ClientLinkTable, ClientLinkRow>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ClientLinkTableProcessedTableManager =
    ProcessedTableManager<
      _$ClientDatabase,
      $ClientLinkTable,
      ClientLinkRow,
      $$ClientLinkTableFilterComposer,
      $$ClientLinkTableOrderingComposer,
      $$ClientLinkTableAnnotationComposer,
      $$ClientLinkTableCreateCompanionBuilder,
      $$ClientLinkTableUpdateCompanionBuilder,
      (
        ClientLinkRow,
        BaseReferences<_$ClientDatabase, $ClientLinkTable, ClientLinkRow>,
      ),
      ClientLinkRow,
      PrefetchHooks Function()
    >;
typedef $$ClientSessionsTableCreateCompanionBuilder =
    ClientSessionsCompanion Function({
      Value<int> singleton,
      required String staffId,
      required String name,
      required String role,
      required int expiresAt,
    });
typedef $$ClientSessionsTableUpdateCompanionBuilder =
    ClientSessionsCompanion Function({
      Value<int> singleton,
      Value<String> staffId,
      Value<String> name,
      Value<String> role,
      Value<int> expiresAt,
    });

class $$ClientSessionsTableFilterComposer extends Composer<_$ClientDatabase, $ClientSessionsTable> {
  $$ClientSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get singleton => $composableBuilder(
    column: $table.singleton,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get staffId => $composableBuilder(
    column: $table.staffId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ClientSessionsTableOrderingComposer extends Composer<_$ClientDatabase, $ClientSessionsTable> {
  $$ClientSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get singleton => $composableBuilder(
    column: $table.singleton,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get staffId => $composableBuilder(
    column: $table.staffId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ClientSessionsTableAnnotationComposer extends Composer<_$ClientDatabase, $ClientSessionsTable> {
  $$ClientSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get singleton => $composableBuilder(column: $table.singleton, builder: (column) => column);

  GeneratedColumn<String> get staffId => $composableBuilder(column: $table.staffId, builder: (column) => column);

  GeneratedColumn<String> get name => $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get role => $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<int> get expiresAt => $composableBuilder(column: $table.expiresAt, builder: (column) => column);
}

class $$ClientSessionsTableTableManager
    extends
        RootTableManager<
          _$ClientDatabase,
          $ClientSessionsTable,
          ClientSessionRow,
          $$ClientSessionsTableFilterComposer,
          $$ClientSessionsTableOrderingComposer,
          $$ClientSessionsTableAnnotationComposer,
          $$ClientSessionsTableCreateCompanionBuilder,
          $$ClientSessionsTableUpdateCompanionBuilder,
          (
            ClientSessionRow,
            BaseReferences<_$ClientDatabase, $ClientSessionsTable, ClientSessionRow>,
          ),
          ClientSessionRow,
          PrefetchHooks Function()
        > {
  $$ClientSessionsTableTableManager(
    _$ClientDatabase db,
    $ClientSessionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$ClientSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$ClientSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () => $$ClientSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> singleton = const Value.absent(),
                Value<String> staffId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<int> expiresAt = const Value.absent(),
              }) => ClientSessionsCompanion(
                singleton: singleton,
                staffId: staffId,
                name: name,
                role: role,
                expiresAt: expiresAt,
              ),
          createCompanionCallback:
              ({
                Value<int> singleton = const Value.absent(),
                required String staffId,
                required String name,
                required String role,
                required int expiresAt,
              }) => ClientSessionsCompanion.insert(
                singleton: singleton,
                staffId: staffId,
                name: name,
                role: role,
                expiresAt: expiresAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ClientSessionsTable, ClientSessionRow>(table),
                  BaseReferences<_$ClientDatabase, $ClientSessionsTable, ClientSessionRow>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ClientSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$ClientDatabase,
      $ClientSessionsTable,
      ClientSessionRow,
      $$ClientSessionsTableFilterComposer,
      $$ClientSessionsTableOrderingComposer,
      $$ClientSessionsTableAnnotationComposer,
      $$ClientSessionsTableCreateCompanionBuilder,
      $$ClientSessionsTableUpdateCompanionBuilder,
      (
        ClientSessionRow,
        BaseReferences<_$ClientDatabase, $ClientSessionsTable, ClientSessionRow>,
      ),
      ClientSessionRow,
      PrefetchHooks Function()
    >;
typedef $$PendingCommandsTableCreateCompanionBuilder =
    PendingCommandsCompanion Function({
      required String commandId,
      required String staffId,
      required String action,
      Value<String?> aggregateId,
      required String bodyJson,
      required String summary,
      required String state,
      required int createdAt,
      required int updatedAt,
      Value<int> attempts,
      Value<int> nextAttemptAt,
      Value<String?> lastRoute,
      Value<String?> mailboxState,
      Value<String?> resultJson,
      Value<String?> errorCode,
      Value<String?> errorMessage,
      Value<int> rowid,
    });
typedef $$PendingCommandsTableUpdateCompanionBuilder =
    PendingCommandsCompanion Function({
      Value<String> commandId,
      Value<String> staffId,
      Value<String> action,
      Value<String?> aggregateId,
      Value<String> bodyJson,
      Value<String> summary,
      Value<String> state,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int> attempts,
      Value<int> nextAttemptAt,
      Value<String?> lastRoute,
      Value<String?> mailboxState,
      Value<String?> resultJson,
      Value<String?> errorCode,
      Value<String?> errorMessage,
      Value<int> rowid,
    });

class $$PendingCommandsTableFilterComposer extends Composer<_$ClientDatabase, $PendingCommandsTable> {
  $$PendingCommandsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get commandId => $composableBuilder(
    column: $table.commandId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get staffId => $composableBuilder(
    column: $table.staffId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get aggregateId => $composableBuilder(
    column: $table.aggregateId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bodyJson => $composableBuilder(
    column: $table.bodyJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get summary => $composableBuilder(
    column: $table.summary,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastRoute => $composableBuilder(
    column: $table.lastRoute,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mailboxState => $composableBuilder(
    column: $table.mailboxState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get resultJson => $composableBuilder(
    column: $table.resultJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get errorCode => $composableBuilder(
    column: $table.errorCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PendingCommandsTableOrderingComposer extends Composer<_$ClientDatabase, $PendingCommandsTable> {
  $$PendingCommandsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get commandId => $composableBuilder(
    column: $table.commandId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get staffId => $composableBuilder(
    column: $table.staffId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get aggregateId => $composableBuilder(
    column: $table.aggregateId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bodyJson => $composableBuilder(
    column: $table.bodyJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get summary => $composableBuilder(
    column: $table.summary,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastRoute => $composableBuilder(
    column: $table.lastRoute,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mailboxState => $composableBuilder(
    column: $table.mailboxState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get resultJson => $composableBuilder(
    column: $table.resultJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorCode => $composableBuilder(
    column: $table.errorCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PendingCommandsTableAnnotationComposer extends Composer<_$ClientDatabase, $PendingCommandsTable> {
  $$PendingCommandsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get commandId => $composableBuilder(column: $table.commandId, builder: (column) => column);

  GeneratedColumn<String> get staffId => $composableBuilder(column: $table.staffId, builder: (column) => column);

  GeneratedColumn<String> get action => $composableBuilder(column: $table.action, builder: (column) => column);

  GeneratedColumn<String> get aggregateId => $composableBuilder(
    column: $table.aggregateId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get bodyJson => $composableBuilder(column: $table.bodyJson, builder: (column) => column);

  GeneratedColumn<String> get summary => $composableBuilder(column: $table.summary, builder: (column) => column);

  GeneratedColumn<String> get state => $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get createdAt => $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt => $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get attempts => $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<int> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastRoute => $composableBuilder(column: $table.lastRoute, builder: (column) => column);

  GeneratedColumn<String> get mailboxState => $composableBuilder(
    column: $table.mailboxState,
    builder: (column) => column,
  );

  GeneratedColumn<String> get resultJson => $composableBuilder(
    column: $table.resultJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get errorCode => $composableBuilder(column: $table.errorCode, builder: (column) => column);

  GeneratedColumn<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => column,
  );
}

class $$PendingCommandsTableTableManager
    extends
        RootTableManager<
          _$ClientDatabase,
          $PendingCommandsTable,
          PendingCommandRow,
          $$PendingCommandsTableFilterComposer,
          $$PendingCommandsTableOrderingComposer,
          $$PendingCommandsTableAnnotationComposer,
          $$PendingCommandsTableCreateCompanionBuilder,
          $$PendingCommandsTableUpdateCompanionBuilder,
          (
            PendingCommandRow,
            BaseReferences<_$ClientDatabase, $PendingCommandsTable, PendingCommandRow>,
          ),
          PendingCommandRow,
          PrefetchHooks Function()
        > {
  $$PendingCommandsTableTableManager(
    _$ClientDatabase db,
    $PendingCommandsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$PendingCommandsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$PendingCommandsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () => $$PendingCommandsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> commandId = const Value.absent(),
                Value<String> staffId = const Value.absent(),
                Value<String> action = const Value.absent(),
                Value<String?> aggregateId = const Value.absent(),
                Value<String> bodyJson = const Value.absent(),
                Value<String> summary = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<int> nextAttemptAt = const Value.absent(),
                Value<String?> lastRoute = const Value.absent(),
                Value<String?> mailboxState = const Value.absent(),
                Value<String?> resultJson = const Value.absent(),
                Value<String?> errorCode = const Value.absent(),
                Value<String?> errorMessage = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PendingCommandsCompanion(
                commandId: commandId,
                staffId: staffId,
                action: action,
                aggregateId: aggregateId,
                bodyJson: bodyJson,
                summary: summary,
                state: state,
                createdAt: createdAt,
                updatedAt: updatedAt,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
                lastRoute: lastRoute,
                mailboxState: mailboxState,
                resultJson: resultJson,
                errorCode: errorCode,
                errorMessage: errorMessage,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String commandId,
                required String staffId,
                required String action,
                Value<String?> aggregateId = const Value.absent(),
                required String bodyJson,
                required String summary,
                required String state,
                required int createdAt,
                required int updatedAt,
                Value<int> attempts = const Value.absent(),
                Value<int> nextAttemptAt = const Value.absent(),
                Value<String?> lastRoute = const Value.absent(),
                Value<String?> mailboxState = const Value.absent(),
                Value<String?> resultJson = const Value.absent(),
                Value<String?> errorCode = const Value.absent(),
                Value<String?> errorMessage = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PendingCommandsCompanion.insert(
                commandId: commandId,
                staffId: staffId,
                action: action,
                aggregateId: aggregateId,
                bodyJson: bodyJson,
                summary: summary,
                state: state,
                createdAt: createdAt,
                updatedAt: updatedAt,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
                lastRoute: lastRoute,
                mailboxState: mailboxState,
                resultJson: resultJson,
                errorCode: errorCode,
                errorMessage: errorMessage,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PendingCommandsTable, PendingCommandRow>(table),
                  BaseReferences<_$ClientDatabase, $PendingCommandsTable, PendingCommandRow>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PendingCommandsTableProcessedTableManager =
    ProcessedTableManager<
      _$ClientDatabase,
      $PendingCommandsTable,
      PendingCommandRow,
      $$PendingCommandsTableFilterComposer,
      $$PendingCommandsTableOrderingComposer,
      $$PendingCommandsTableAnnotationComposer,
      $$PendingCommandsTableCreateCompanionBuilder,
      $$PendingCommandsTableUpdateCompanionBuilder,
      (
        PendingCommandRow,
        BaseReferences<_$ClientDatabase, $PendingCommandsTable, PendingCommandRow>,
      ),
      PendingCommandRow,
      PrefetchHooks Function()
    >;
typedef $$DraftsTableCreateCompanionBuilder =
    DraftsCompanion Function({
      required String id,
      required String staffId,
      required String orderType,
      Value<String?> tableId,
      Value<String?> tableLabel,
      Value<String?> orderId,
      Value<int?> guestCount,
      required String linesJson,
      required int createdAt,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $$DraftsTableUpdateCompanionBuilder =
    DraftsCompanion Function({
      Value<String> id,
      Value<String> staffId,
      Value<String> orderType,
      Value<String?> tableId,
      Value<String?> tableLabel,
      Value<String?> orderId,
      Value<int?> guestCount,
      Value<String> linesJson,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });

class $$DraftsTableFilterComposer extends Composer<_$ClientDatabase, $DraftsTable> {
  $$DraftsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get staffId => $composableBuilder(
    column: $table.staffId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get orderType => $composableBuilder(
    column: $table.orderType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tableId => $composableBuilder(
    column: $table.tableId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tableLabel => $composableBuilder(
    column: $table.tableLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get orderId => $composableBuilder(
    column: $table.orderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get guestCount => $composableBuilder(
    column: $table.guestCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get linesJson => $composableBuilder(
    column: $table.linesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DraftsTableOrderingComposer extends Composer<_$ClientDatabase, $DraftsTable> {
  $$DraftsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get staffId => $composableBuilder(
    column: $table.staffId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get orderType => $composableBuilder(
    column: $table.orderType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tableId => $composableBuilder(
    column: $table.tableId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tableLabel => $composableBuilder(
    column: $table.tableLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get orderId => $composableBuilder(
    column: $table.orderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get guestCount => $composableBuilder(
    column: $table.guestCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get linesJson => $composableBuilder(
    column: $table.linesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DraftsTableAnnotationComposer extends Composer<_$ClientDatabase, $DraftsTable> {
  $$DraftsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id => $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get staffId => $composableBuilder(column: $table.staffId, builder: (column) => column);

  GeneratedColumn<String> get orderType => $composableBuilder(column: $table.orderType, builder: (column) => column);

  GeneratedColumn<String> get tableId => $composableBuilder(column: $table.tableId, builder: (column) => column);

  GeneratedColumn<String> get tableLabel => $composableBuilder(
    column: $table.tableLabel,
    builder: (column) => column,
  );

  GeneratedColumn<String> get orderId => $composableBuilder(column: $table.orderId, builder: (column) => column);

  GeneratedColumn<int> get guestCount => $composableBuilder(
    column: $table.guestCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get linesJson => $composableBuilder(column: $table.linesJson, builder: (column) => column);

  GeneratedColumn<int> get createdAt => $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt => $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$DraftsTableTableManager
    extends
        RootTableManager<
          _$ClientDatabase,
          $DraftsTable,
          DraftRow,
          $$DraftsTableFilterComposer,
          $$DraftsTableOrderingComposer,
          $$DraftsTableAnnotationComposer,
          $$DraftsTableCreateCompanionBuilder,
          $$DraftsTableUpdateCompanionBuilder,
          (DraftRow, BaseReferences<_$ClientDatabase, $DraftsTable, DraftRow>),
          DraftRow,
          PrefetchHooks Function()
        > {
  $$DraftsTableTableManager(_$ClientDatabase db, $DraftsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$DraftsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$DraftsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () => $$DraftsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> staffId = const Value.absent(),
                Value<String> orderType = const Value.absent(),
                Value<String?> tableId = const Value.absent(),
                Value<String?> tableLabel = const Value.absent(),
                Value<String?> orderId = const Value.absent(),
                Value<int?> guestCount = const Value.absent(),
                Value<String> linesJson = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DraftsCompanion(
                id: id,
                staffId: staffId,
                orderType: orderType,
                tableId: tableId,
                tableLabel: tableLabel,
                orderId: orderId,
                guestCount: guestCount,
                linesJson: linesJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String staffId,
                required String orderType,
                Value<String?> tableId = const Value.absent(),
                Value<String?> tableLabel = const Value.absent(),
                Value<String?> orderId = const Value.absent(),
                Value<int?> guestCount = const Value.absent(),
                required String linesJson,
                required int createdAt,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => DraftsCompanion.insert(
                id: id,
                staffId: staffId,
                orderType: orderType,
                tableId: tableId,
                tableLabel: tableLabel,
                orderId: orderId,
                guestCount: guestCount,
                linesJson: linesJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DraftsTable, DraftRow>(table),
                  BaseReferences<_$ClientDatabase, $DraftsTable, DraftRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DraftsTableProcessedTableManager =
    ProcessedTableManager<
      _$ClientDatabase,
      $DraftsTable,
      DraftRow,
      $$DraftsTableFilterComposer,
      $$DraftsTableOrderingComposer,
      $$DraftsTableAnnotationComposer,
      $$DraftsTableCreateCompanionBuilder,
      $$DraftsTableUpdateCompanionBuilder,
      (DraftRow, BaseReferences<_$ClientDatabase, $DraftsTable, DraftRow>),
      DraftRow,
      PrefetchHooks Function()
    >;
typedef $$CacheEntriesTableCreateCompanionBuilder =
    CacheEntriesCompanion Function({
      required String key,
      required String kind,
      required String json,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $$CacheEntriesTableUpdateCompanionBuilder =
    CacheEntriesCompanion Function({
      Value<String> key,
      Value<String> kind,
      Value<String> json,
      Value<int> updatedAt,
      Value<int> rowid,
    });

class $$CacheEntriesTableFilterComposer extends Composer<_$ClientDatabase, $CacheEntriesTable> {
  $$CacheEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CacheEntriesTableOrderingComposer extends Composer<_$ClientDatabase, $CacheEntriesTable> {
  $$CacheEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CacheEntriesTableAnnotationComposer extends Composer<_$ClientDatabase, $CacheEntriesTable> {
  $$CacheEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key => $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get kind => $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get json => $composableBuilder(column: $table.json, builder: (column) => column);

  GeneratedColumn<int> get updatedAt => $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CacheEntriesTableTableManager
    extends
        RootTableManager<
          _$ClientDatabase,
          $CacheEntriesTable,
          CacheEntryRow,
          $$CacheEntriesTableFilterComposer,
          $$CacheEntriesTableOrderingComposer,
          $$CacheEntriesTableAnnotationComposer,
          $$CacheEntriesTableCreateCompanionBuilder,
          $$CacheEntriesTableUpdateCompanionBuilder,
          (
            CacheEntryRow,
            BaseReferences<_$ClientDatabase, $CacheEntriesTable, CacheEntryRow>,
          ),
          CacheEntryRow,
          PrefetchHooks Function()
        > {
  $$CacheEntriesTableTableManager(_$ClientDatabase db, $CacheEntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$CacheEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$CacheEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () => $$CacheEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> json = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CacheEntriesCompanion(
                key: key,
                kind: kind,
                json: json,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String kind,
                required String json,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => CacheEntriesCompanion.insert(
                key: key,
                kind: kind,
                json: json,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CacheEntriesTable, CacheEntryRow>(table),
                  BaseReferences<_$ClientDatabase, $CacheEntriesTable, CacheEntryRow>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CacheEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$ClientDatabase,
      $CacheEntriesTable,
      CacheEntryRow,
      $$CacheEntriesTableFilterComposer,
      $$CacheEntriesTableOrderingComposer,
      $$CacheEntriesTableAnnotationComposer,
      $$CacheEntriesTableCreateCompanionBuilder,
      $$CacheEntriesTableUpdateCompanionBuilder,
      (
        CacheEntryRow,
        BaseReferences<_$ClientDatabase, $CacheEntriesTable, CacheEntryRow>,
      ),
      CacheEntryRow,
      PrefetchHooks Function()
    >;
typedef $$TicketAlertsTableCreateCompanionBuilder =
    TicketAlertsCompanion Function({
      required String ticketId,
      required int alertedAt,
      required bool sounded,
      Value<int> rowid,
    });
typedef $$TicketAlertsTableUpdateCompanionBuilder =
    TicketAlertsCompanion Function({
      Value<String> ticketId,
      Value<int> alertedAt,
      Value<bool> sounded,
      Value<int> rowid,
    });

class $$TicketAlertsTableFilterComposer extends Composer<_$ClientDatabase, $TicketAlertsTable> {
  $$TicketAlertsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ticketId => $composableBuilder(
    column: $table.ticketId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get alertedAt => $composableBuilder(
    column: $table.alertedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get sounded => $composableBuilder(
    column: $table.sounded,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TicketAlertsTableOrderingComposer extends Composer<_$ClientDatabase, $TicketAlertsTable> {
  $$TicketAlertsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ticketId => $composableBuilder(
    column: $table.ticketId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get alertedAt => $composableBuilder(
    column: $table.alertedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get sounded => $composableBuilder(
    column: $table.sounded,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TicketAlertsTableAnnotationComposer extends Composer<_$ClientDatabase, $TicketAlertsTable> {
  $$TicketAlertsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ticketId => $composableBuilder(column: $table.ticketId, builder: (column) => column);

  GeneratedColumn<int> get alertedAt => $composableBuilder(column: $table.alertedAt, builder: (column) => column);

  GeneratedColumn<bool> get sounded => $composableBuilder(column: $table.sounded, builder: (column) => column);
}

class $$TicketAlertsTableTableManager
    extends
        RootTableManager<
          _$ClientDatabase,
          $TicketAlertsTable,
          TicketAlertRow,
          $$TicketAlertsTableFilterComposer,
          $$TicketAlertsTableOrderingComposer,
          $$TicketAlertsTableAnnotationComposer,
          $$TicketAlertsTableCreateCompanionBuilder,
          $$TicketAlertsTableUpdateCompanionBuilder,
          (
            TicketAlertRow,
            BaseReferences<_$ClientDatabase, $TicketAlertsTable, TicketAlertRow>,
          ),
          TicketAlertRow,
          PrefetchHooks Function()
        > {
  $$TicketAlertsTableTableManager(_$ClientDatabase db, $TicketAlertsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$TicketAlertsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$TicketAlertsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () => $$TicketAlertsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> ticketId = const Value.absent(),
                Value<int> alertedAt = const Value.absent(),
                Value<bool> sounded = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TicketAlertsCompanion(
                ticketId: ticketId,
                alertedAt: alertedAt,
                sounded: sounded,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ticketId,
                required int alertedAt,
                required bool sounded,
                Value<int> rowid = const Value.absent(),
              }) => TicketAlertsCompanion.insert(
                ticketId: ticketId,
                alertedAt: alertedAt,
                sounded: sounded,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TicketAlertsTable, TicketAlertRow>(table),
                  BaseReferences<_$ClientDatabase, $TicketAlertsTable, TicketAlertRow>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TicketAlertsTableProcessedTableManager =
    ProcessedTableManager<
      _$ClientDatabase,
      $TicketAlertsTable,
      TicketAlertRow,
      $$TicketAlertsTableFilterComposer,
      $$TicketAlertsTableOrderingComposer,
      $$TicketAlertsTableAnnotationComposer,
      $$TicketAlertsTableCreateCompanionBuilder,
      $$TicketAlertsTableUpdateCompanionBuilder,
      (
        TicketAlertRow,
        BaseReferences<_$ClientDatabase, $TicketAlertsTable, TicketAlertRow>,
      ),
      TicketAlertRow,
      PrefetchHooks Function()
    >;

class $ClientDatabaseManager {
  final _$ClientDatabase _db;
  $ClientDatabaseManager(this._db);
  $$ClientLinkTableTableManager get clientLink => $$ClientLinkTableTableManager(_db, _db.clientLink);
  $$ClientSessionsTableTableManager get clientSessions => $$ClientSessionsTableTableManager(_db, _db.clientSessions);
  $$PendingCommandsTableTableManager get pendingCommands =>
      $$PendingCommandsTableTableManager(_db, _db.pendingCommands);
  $$DraftsTableTableManager get drafts => $$DraftsTableTableManager(_db, _db.drafts);
  $$CacheEntriesTableTableManager get cacheEntries => $$CacheEntriesTableTableManager(_db, _db.cacheEntries);
  $$TicketAlertsTableTableManager get ticketAlerts => $$TicketAlertsTableTableManager(_db, _db.ticketAlerts);
}
