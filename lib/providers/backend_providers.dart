import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_database/firebase_database.dart'; 
import '../models/device.dart';
import '../models/sensor_data.dart';
import '../services/backend_service.dart';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:rxdart/rxdart.dart';
import 'dart:async';

// Auth state stream
final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

final userDevicesProvider = StreamProvider<List<DeviceModel>>((ref) {
  // Watch auth state — provider rebuilds when user signs in/out
  final user = ref.watch(authStateProvider).valueOrNull;
  
  if (user == null) {
    return Stream.value([]);
  }

  final uid = user.uid;
  print('userDevicesProvider: subscribing to UserDevices/$uid');

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
  }).handleError((e) {
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
final allDevicesSensorProvider = StreamProvider<List<(DeviceModel, SensorData?)>>((ref) {
  late StreamController<List<(DeviceModel, SensorData?)>> controller;
  final subs = <StreamSubscription<void>>[];

  controller = StreamController<List<(DeviceModel, SensorData?)>>.broadcast(
    onListen: () async {
      final devices = await ref.watch(userDevicesProvider.future);

      if (devices.isEmpty) {
        controller.add([]);
        return;
      }

      final latest = List<SensorData?>.filled(devices.length, null);

      for (int i = 0; i < devices.length; i++) {
        final idx = i;
        final sub = BackendService()
            .watchSensorData(devices[idx].deviceId)
            .listen(
              (sensor) {
                latest[idx] = sensor;
                if (!controller.isClosed) {
                  controller.add(
                    List<(DeviceModel, SensorData?)>.generate(
                      devices.length,
                      (j) => (devices[j], latest[j]),
                    ),
                  );
                }
              },
              onError: (e) => controller.addError(e),
            );
        subs.add(sub);
      }
    },
  );

  ref.onDispose(() {
    for (final sub in subs) sub.cancel();
    controller.close();
  });

  return controller.stream;
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

// ══════════════════════════════════════════════════════════════════════════
// MQTT MESSAGE HANDLER
// Listens to all incoming MQTT messages and routes error topics to Firestore
// ══════════════════════════════════════════════════════════════════════════

final mqttMessageHandlerProvider = Provider<void>((ref) {
  // Re-runs whenever devices change (ensures client is ready)
  ref.watch(mqttAutoSubscriptionProvider);

  final client = BackendService().mqttClient;
  if (client == null) return;

  client.updates?.listen((messages) {
    for (final msg in messages) {
      final topic = msg.topic;
      final rawPayload = msg.payload as MqttPublishMessage;
      final payload = MqttPublishPayload.bytesToStringAsString(
        rawPayload.payload.message,
      );
      BackendService().handleIncomingMqttMessage(topic, payload);
    }
  });
});