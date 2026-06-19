class SensorData {
  final double moisture;
  final double temperature;
  final double humidity;
  final int? timestamp; // raw milliseconds from RTDB

  SensorData({
    required this.moisture,
    required this.temperature,
    required this.humidity,
    this.timestamp,
  });

  factory SensorData.fromMap(Map<dynamic, dynamic> map) {
    return SensorData(
      moisture: (map['moisture'] ?? 0).toDouble(),
      temperature: (map['temperature'] ?? 0).toDouble(),
      humidity: (map['humidity'] ?? 0).toDouble(),
      timestamp: map['lastUpdated'] as int?,
    );
  }

  DateTime? get lastUpdatedDateTime {
    if (timestamp == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(timestamp!);
  }

  factory SensorData.empty() => SensorData(
  moisture: 0,
  temperature: 0,
  humidity: 0,
  timestamp: null,
);
}