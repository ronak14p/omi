import 'package:flutter/services.dart';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:omi/backend/preferences.dart';
import 'package:omi/services/devices/device_connection.dart';
import 'package:omi/services/devices/discovery/device_locator.dart';
import 'package:omi/services/devices/models.dart';
import 'package:omi/services/devices/omi_connection.dart';
import 'package:omi/services/devices/omiglass_connection.dart';
import 'package:omi/utils/logger.dart';

enum ImageOrientation {
  orientation0,
  orientation90,
  orientation180,
  orientation270;

  factory ImageOrientation.fromValue(int value) {
    switch (value) {
      case 0:
        return ImageOrientation.orientation0;
      case 1:
        return ImageOrientation.orientation90;
      case 2:
        return ImageOrientation.orientation180;
      case 3:
        return ImageOrientation.orientation270;
      default:
        return ImageOrientation.orientation0;
    }
  }
}

enum BleAudioCodec {
  pcm16,
  pcm8,
  mulaw16,
  mulaw8,
  opus,
  opusFS320,
  aac,
  lc3FS1030,
  unknown;

  @override
  String toString() => mapCodecToName(this);

  bool isOpusSupported() {
    return this == BleAudioCodec.opusFS320 || this == BleAudioCodec.opus;
  }

  String toFormattedString() {
    switch (this) {
      case BleAudioCodec.opusFS320:
        return 'OPUS (320)';
      case BleAudioCodec.opus:
        return 'OPUS';
      case BleAudioCodec.pcm16:
        return 'PCM (16kHz)';
      case BleAudioCodec.pcm8:
        return 'PCM (8kHz)';
      case BleAudioCodec.aac:
        return 'AAC';
      case BleAudioCodec.lc3FS1030:
        return 'LC3 (10ms/30B)';
      default:
        return toString().split('.').last.toUpperCase();
    }
  }

  int getFramesPerSecond() {
    return this == BleAudioCodec.opusFS320 ? 50 : 100;
  }

  int getFramesLengthInBytes() {
    return this == BleAudioCodec.opusFS320 ? 160 : 80;
  }

  int getFrameSize() {
    return this == BleAudioCodec.opusFS320 ? 320 : 160;
  }

  bool get isCustomSttSupported {
    return this == BleAudioCodec.pcm8 ||
        this == BleAudioCodec.pcm16 ||
        this == BleAudioCodec.opus ||
        this == BleAudioCodec.opusFS320;
  }

  String get customSttUnsupportedReason {
    switch (this) {
      case BleAudioCodec.mulaw8:
      case BleAudioCodec.mulaw16:
        return 'µ-law audio format';
      case BleAudioCodec.aac:
        return 'AAC audio format';
      case BleAudioCodec.lc3FS1030:
        return 'LC3 audio format';
      case BleAudioCodec.unknown:
        return 'unknown audio format';
      default:
        return 'this audio format';
    }
  }
}

String mapCodecToName(BleAudioCodec codec) {
  switch (codec) {
    case BleAudioCodec.opusFS320:
      return 'opus_fs320';
    case BleAudioCodec.opus:
      return 'opus';
    case BleAudioCodec.pcm16:
      return 'pcm16';
    case BleAudioCodec.pcm8:
      return 'pcm8';
    case BleAudioCodec.aac:
      return 'aac';
    case BleAudioCodec.lc3FS1030:
      return 'lc3_fs1030';
    default:
      return 'pcm8';
  }
}

BleAudioCodec mapNameToCodec(String codec) {
  switch (codec) {
    case 'opus_fs320':
      return BleAudioCodec.opusFS320;
    case 'opus':
      return BleAudioCodec.opus;
    case 'pcm16':
      return BleAudioCodec.pcm16;
    case 'pcm8':
      return BleAudioCodec.pcm8;
    case 'aac':
      return BleAudioCodec.aac;
    case 'lc3_fs1030':
      return BleAudioCodec.lc3FS1030;
    default:
      return BleAudioCodec.pcm8;
  }
}

int mapCodecToSampleRate(BleAudioCodec codec) {
  switch (codec) {
    case BleAudioCodec.opusFS320:
    case BleAudioCodec.opus:
    case BleAudioCodec.pcm16:
    case BleAudioCodec.pcm8:
    case BleAudioCodec.lc3FS1030:
    default:
      return 16000;
  }
}

int mapCodecToBitDepth(BleAudioCodec codec) {
  switch (codec) {
    case BleAudioCodec.opusFS320:
    case BleAudioCodec.opus:
    case BleAudioCodec.pcm16:
    case BleAudioCodec.lc3FS1030:
      return 16;
    case BleAudioCodec.pcm8:
      return 8;
    default:
      return 16;
  }
}

Future<DeviceType?> getTypeOfBluetoothDevice(BluetoothDevice device) async {
  if (cachedDevicesMap.containsKey(device.remoteId.toString())) {
    return cachedDevicesMap[device.remoteId.toString()];
  }

  DeviceType? deviceType;
  await device.discoverServices();

  if (BtDevice.isOmiDeviceFromDevice(device)) {
    final hasImageStream = device.servicesList
        .where((s) => s.uuid == Guid.fromString(omiServiceUuid))
        .expand((s) => s.characteristics)
        .any((c) => c.uuid.toString().toLowerCase() == imageDataStreamCharacteristicUuid.toLowerCase());
    final isOpenGlassByName =
        device.platformName.toLowerCase().contains('openglass') || device.platformName.toLowerCase().contains('glass');
    deviceType = (hasImageStream || isOpenGlassByName) ? DeviceType.openglass : DeviceType.omi;
  }

  if (deviceType != null) {
    cachedDevicesMap[device.remoteId.toString()] = deviceType;
  }

  return deviceType;
}

enum DeviceType {
  omi,
  openglass,
}

Map<String, DeviceType> cachedDevicesMap = {};

class BtDevice {
  String name;
  String id;
  DeviceType type;
  int rssi;
  final DeviceLocator? locator;
  String? _modelNumber;
  String? _firmwareRevision;
  String? _hardwareRevision;
  String? _manufacturerName;
  String? _serialNumber;

  BtDevice({
    required this.name,
    required this.id,
    required this.type,
    required this.rssi,
    this.locator,
    String? modelNumber,
    String? firmwareRevision,
    String? hardwareRevision,
    String? manufacturerName,
    String? serialNumber,
  }) {
    _modelNumber = modelNumber;
    _firmwareRevision = firmwareRevision;
    _hardwareRevision = hardwareRevision;
    _manufacturerName = manufacturerName;
    _serialNumber = serialNumber;
  }

  BtDevice.empty()
      : name = '',
        id = '',
        type = DeviceType.omi,
        rssi = 0,
        locator = null,
        _modelNumber = '',
        _firmwareRevision = '',
        _hardwareRevision = '',
        _manufacturerName = '',
        _serialNumber = '';

  String get modelNumber => _modelNumber ?? 'Unknown';
  String get firmwareRevision => _firmwareRevision ?? 'Unknown';
  String get hardwareRevision => _hardwareRevision ?? 'Unknown';
  String get manufacturerName => _manufacturerName ?? 'Unknown';
  String? get serialNumber => _serialNumber;

  set modelNumber(String modelNumber) => _modelNumber = modelNumber;
  set firmwareRevision(String firmwareRevision) => _firmwareRevision = firmwareRevision;
  set hardwareRevision(String hardwareRevision) => _hardwareRevision = hardwareRevision;
  set manufacturerName(String manufacturerName) => _manufacturerName = manufacturerName;
  set serialNumber(String? serialNumber) => _serialNumber = serialNumber;

  String getShortId() => BtDevice.shortId(id);

  static String shortId(String id) {
    try {
      return id.replaceAll(':', '').split('-').last.substring(0, 6);
    } catch (e) {
      return id.length > 6 ? id.substring(0, 6) : id;
    }
  }

  BtDevice copyWith({
    String? name,
    String? id,
    DeviceType? type,
    int? rssi,
    DeviceLocator? locator,
    String? modelNumber,
    String? firmwareRevision,
    String? hardwareRevision,
    String? manufacturerName,
    String? serialNumber,
  }) {
    return BtDevice(
      name: name ?? this.name,
      id: id ?? this.id,
      type: type ?? this.type,
      rssi: rssi ?? this.rssi,
      locator: locator ?? this.locator,
      modelNumber: modelNumber ?? _modelNumber,
      firmwareRevision: firmwareRevision ?? _firmwareRevision,
      hardwareRevision: hardwareRevision ?? _hardwareRevision,
      manufacturerName: manufacturerName ?? _manufacturerName,
      serialNumber: serialNumber ?? _serialNumber,
    );
  }

  Future<BtDevice> updateDeviceInfo(DeviceConnection? conn) async {
    return getDeviceInfo(conn);
  }

  Future<BtDevice> getDeviceInfo(DeviceConnection? conn) async {
    if (conn == null) {
      if (SharedPreferencesUtil().btDevice.id.isNotEmpty) {
        var device = SharedPreferencesUtil().btDevice;
        return copyWith(
          id: device.id,
          name: device.name,
          type: device.type,
          rssi: device.rssi,
          modelNumber: device.modelNumber,
          firmwareRevision: device.firmwareRevision,
          hardwareRevision: device.hardwareRevision,
          manufacturerName: device.manufacturerName,
          serialNumber: device.serialNumber,
        );
      }
      return BtDevice.empty();
    }

    return _getDeviceInfoFromOmi(conn);
  }

  Future<BtDevice> _getDeviceInfoFromOmi(DeviceConnection conn) async {
    var modelNumber = 'Omi';
    var firmwareRevision = '1.0.2';
    var hardwareRevision = 'Seeed Xiao BLE Sense';
    var manufacturerName = 'Based Hardware';
    String? serialNumber;
    var resolvedType = DeviceType.omi;

    try {
      Map<String, dynamic>? deviceInfo;

      if (conn is OmiGlassConnection) {
        deviceInfo = await conn.getDeviceInfo();
        resolvedType = DeviceType.openglass;
      } else if (conn is OmiDeviceConnection) {
        deviceInfo = await conn.getDeviceInfo();

        if (type == DeviceType.openglass || deviceInfo['hasImageStream'] == 'true') {
          resolvedType = DeviceType.openglass;
        }
      }

      if (deviceInfo != null) {
        modelNumber = deviceInfo['modelNumber'] ?? modelNumber;
        firmwareRevision = deviceInfo['firmwareRevision'] ?? firmwareRevision;
        hardwareRevision = deviceInfo['hardwareRevision'] ?? hardwareRevision;
        manufacturerName = deviceInfo['manufacturerName'] ?? manufacturerName;
        serialNumber = deviceInfo['serialNumber'];
      }
    } on PlatformException catch (e) {
      Logger.error('Device disconnected while getting device info: $e');
    } catch (e) {
      Logger.error('Error getting Omi device info: $e');
    }

    return copyWith(
      modelNumber: modelNumber,
      firmwareRevision: firmwareRevision,
      hardwareRevision: hardwareRevision,
      manufacturerName: manufacturerName,
      serialNumber: serialNumber,
      type: resolvedType,
    );
  }

  String getFirmwareWarningTitle() {
    return '';
  }

  String getFirmwareWarningMessage() {
    return '';
  }

  static Future<BtDevice> fromBluetoothDevice(BluetoothDevice device) async {
    var currentRssi = await device.readRssi();
    return BtDevice(
      name: device.platformName,
      id: device.remoteId.str,
      type: DeviceType.omi,
      rssi: currentRssi,
    );
  }

  static bool isSupportedDevice(ScanResult result) {
    return isOmiDevice(result);
  }

  static bool isOmiDevice(ScanResult result) {
    return result.advertisementData.serviceUuids.contains(Guid(omiServiceUuid));
  }

  static bool isOmiDeviceFromDevice(BluetoothDevice device) {
    return device.servicesList.any((s) => s.uuid == Guid(omiServiceUuid));
  }

  static BtDevice fromScanResult(ScanResult result) {
    DeviceType? deviceType;

    if (isOmiDevice(result)) {
      deviceType = DeviceType.omi;
    }

    if (deviceType != null) {
      cachedDevicesMap[result.device.remoteId.toString()] = deviceType;
    } else if (cachedDevicesMap.containsKey(result.device.remoteId.toString())) {
      deviceType = cachedDevicesMap[result.device.remoteId.toString()];
    }

    return BtDevice(
      name: result.device.platformName,
      id: result.device.remoteId.str,
      type: deviceType ?? DeviceType.omi,
      rssi: result.rssi,
      locator: DeviceLocator.bluetooth(deviceId: result.device.remoteId.str),
    );
  }

  static DeviceType _parseDeviceType(dynamic raw) {
    if (raw is int) {
      if (raw == DeviceType.openglass.index) return DeviceType.openglass;
      return DeviceType.omi;
    }

    if (raw is String) {
      if (raw.toLowerCase() == DeviceType.openglass.name) {
        return DeviceType.openglass;
      }
      return DeviceType.omi;
    }

    return DeviceType.omi;
  }

  static BtDevice fromJson(Map<String, dynamic> json) {
    return BtDevice(
      name: json['name'] ?? '',
      id: json['id'] ?? '',
      type: _parseDeviceType(json['type']),
      rssi: json['rssi'] ?? 0,
      locator: json['locator'] != null ? DeviceLocator.fromJson(json['locator']) : null,
      modelNumber: json['modelNumber'],
      firmwareRevision: json['firmwareRevision'],
      hardwareRevision: json['hardwareRevision'],
      manufacturerName: json['manufacturerName'],
      serialNumber: json['serialNumber'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'id': id,
      'type': type.index,
      'rssi': rssi,
      'locator': locator?.toJson(),
      'modelNumber': modelNumber,
      'firmwareRevision': firmwareRevision,
      'hardwareRevision': hardwareRevision,
      'manufacturerName': manufacturerName,
      'serialNumber': _serialNumber,
    };
  }
}
