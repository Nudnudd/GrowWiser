class DeviceModel {
  final String deviceId;
  final String name;
  final String location;
  final double moistureThreshold;
  final double moistureUpperLimit;
  final bool scheduleEnabled;
  final String? scheduleTime;
  final String? claimToken;
  final String? ownerId;

  DeviceModel({
    required this.deviceId,
    required this.name,
    required this.location,
    this.moistureThreshold = 40.0,
    this.moistureUpperLimit = 80.0,
    this.scheduleEnabled = false,
    this.scheduleTime,
    this.claimToken,
    this.ownerId,
  });

  /// Parse from Firestore document
  factory DeviceModel.fromFirestore(Map<String, dynamic> map, String id) {
    return DeviceModel(
      deviceId: id,
      name: map['name'] ?? 'Unnamed Device',
      location: map['location'] ?? '',
      moistureThreshold: (map['moistureThreshold'] ?? 40).toDouble(),
      moistureUpperLimit: (map['moistureUpperLimit'] ?? 80).toDouble(),
      scheduleEnabled: map['scheduleEnabled'] ?? false,
      scheduleTime: map['scheduleTime'],
      claimToken: map['claimToken'],
      ownerId: map['claimedBy'] as String?,
    );
  }

  /// Parse from Realtime Database snapshot
  factory DeviceModel.fromRtdb(Map<dynamic, dynamic> map, String id) {
    return DeviceModel(
      deviceId: id,
      name: map['name'] ?? 'Unnamed Device',
      location: map['location'] ?? '',
      moistureThreshold: (map['moistureThreshold'] ?? 40).toDouble(),
      moistureUpperLimit: (map['moistureUpperLimit'] ?? 80).toDouble(),
      scheduleEnabled: map['scheduleEnabled'] ?? false,
      scheduleTime: map['scheduleTime'],
      claimToken: map['claimToken'],
      ownerId: map['ownerId'],
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'location': location,
    'moistureThreshold': moistureThreshold,
    'moistureUpperLimit': moistureUpperLimit,
    'scheduleEnabled': scheduleEnabled,
    'scheduleTime': scheduleTime,
    'claimToken': claimToken,
    'ownerId': ownerId,
  };

  factory DeviceModel.empty() => DeviceModel(
  deviceId: 'no-device',
  name: '—',
  location: '—',
  moistureThreshold: 40.0,
  moistureUpperLimit: 80.0,
  scheduleEnabled: false,
  scheduleTime: null,
  claimToken: null,
  ownerId: null,
);
}