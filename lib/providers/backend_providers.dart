import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_database/firebase_database.dart'; 
import '../models/device.dart';
import '../models/sensor_data.dart';
import '../services/backend_service.dart';
import 'package:flutter/material.dart';

// Auth state stream
final authStateProvider = StreamProvider<User?>((ref) {
  return BackendService().authStateChanges;
});

// All devices for current user
final userDevicesProvider = StreamProvider<List<DeviceModel>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value([]);

  return FirebaseDatabase.instance
      .ref('UserDevices/$uid')
      .onValue
      .asyncMap((event) async {
    if (!event.snapshot.exists || event.snapshot.value == null) {
      return <DeviceModel>[];
    }

    final entries = event.snapshot.value as Map<dynamic, dynamic>;
    final deviceIds = entries.keys.cast<String>();

    final devices = <DeviceModel>[];
    for (final deviceId in deviceIds) {
      final deviceSnap = await FirebaseDatabase.instance
          .ref('Devices/$deviceId')
          .get();

      if (deviceSnap.exists && deviceSnap.value != null) {
        final data = deviceSnap.value as Map<dynamic, dynamic>;
        devices.add(DeviceModel.fromRtdb(data, deviceId));
      }
    }
    return devices;
  })
  .handleError((e) {
    debugPrint('userDevicesProvider error: $e');
    return <DeviceModel>[];
  });
});


// Live sensor data per device
final sensorDataProvider =
    StreamProvider.family<SensorData, String>((ref, deviceId) {
  return BackendService().watchSensorData(deviceId);
});

// Device config per device
final deviceConfigProvider =
    StreamProvider.family<DeviceModel, String>((ref, deviceId) {
  return BackendService().watchDeviceConfig(deviceId);
});

// Fetches latest sensor snapshot for all devices once
final allDevicesSensorProvider = FutureProvider<List<(DeviceModel, SensorData?)>>((ref) async {
  final devices = await ref.read(userDevicesProvider.future);
  final results = <(DeviceModel, SensorData?)>[];
  for (final device in devices) {
  try{
    final sensor = await BackendService().fetchLatestSensorData(device.deviceId).timeout(const Duration(seconds: 5));
    results.add((device, sensor));
  } catch (_) {
      // No sensor data yet for this device — show null gracefully
      results.add((device, null));
  }
  }

  return results;
});


final nextWaterProvider = FutureProvider.family<String, String>((ref, deviceId) async {
  // Watch sensor data — this provider rebuilds on every sensor update
  final sensor = await ref.watch(sensorDataProvider(deviceId).future);

  // Record snapshot + predict in one atomic flow
  final prediction = await BackendService().recordMoistureSnapshot(
    deviceId,
    sensor.moisture,
    temperature: sensor.temperature,
    humidity: sensor.humidity,
  );

  return prediction ?? '—';
});


final lastWateredProvider = StreamProvider.family<DateTime?, String>((ref, deviceId) {
  return FirebaseDatabase.instance
      .ref('Devices/$deviceId/control/lastWatered')
      .onValue
      .map((event) {
    final value = event.snapshot.value;
    if (value == null) return null;
    if (value is String) return DateTime.tryParse(value);
    return null;
  });
});

// ══════════════════════════════════════════════════════════════════════════
// MQTT AUTO-SUBSCRIPTION PROVIDER
// Watches userDevicesProvider and auto-subscribes new devices to MQTT
// ══════════════════════════════════════════════════════════════════════════

final mqttAutoSubscriptionProvider = Provider<void>((ref) {
  final devicesAsync = ref.watch(userDevicesProvider);
  devicesAsync.whenData((devices) {
    BackendService().subscribeToAllDevices(devices);
  });
  return;
});