import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math'as math;

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:logger/logger.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:uuid/uuid.dart';

import '../models/device.dart';
import '../models/sensor_data.dart';
import '../utils/irrigation_logic.dart';

// ─── Custom exception so the UI can show a meaningful message ─────────────────
class MqttNotConnectedException implements Exception {
  final String message;
  const MqttNotConnectedException(
      [this.message = 'MQTT broker not connected. Command not sent.']);
  @override
  String toString() => message;
}

class BackendService {
  // ─── Singleton ────────────────────────────────────────────────────────────
  static final BackendService _instance = BackendService._internal();
  factory BackendService() => _instance;
  BackendService._internal();

  // ─── Firebase ─────────────────────────────────────────────────────────────
  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  DatabaseReference get _rtdb => FirebaseDatabase.instance.ref();

  // ─── MQTT ─────────────────────────────────────────────────────────────────
  MqttServerClient? _mqttClient;
  MqttServerClient? get mqttClient => _mqttClient;

  // Reconnect state
  String? _lastBrokerHost;
  int _lastPort = 1883;
  String? _lastMqttUsername;
  String? _lastMqttPassword;
  bool _isReconnecting = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  Timer? _reconnectTimer;
  final Set<String> _pendingSubscriptions = {};

  bool get mqttConnected =>
      _mqttClient?.connectionStatus?.state == MqttConnectionState.connected;

  // ─── Utils ────────────────────────────────────────────────────────────────
  final _logger = Logger();
  final _uuid = const Uuid();

  // ══════════════════════════════════════════════════════════════════════════
  // AUTH
  // ══════════════════════════════════════════════════════════════════════════

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<UserCredential> signIn(String email, String password) async {
    return await _auth.signInWithEmailAndPassword(
        email: email, password: password);
  }

  Future<void> signUp(String email, String password, {
  String? phone,
  String? verificationId,
  String? smsCode,
}) async {
  print(' SIGNUP: Creating auth user...');
  
  final result = await _auth.createUserWithEmailAndPassword(
    email: email, 
    password: password,
  );
  print(' SIGNUP: Auth user created = ${result.user?.uid}');

  // Try to link phone with a timeout — don't let it hang forever
  if (verificationId != null && smsCode != null) {
    print(' SIGNUP: Linking phone...');
    try {
      final phoneCredential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      
      // Add timeout so it doesn't hang
      await result.user
          ?.linkWithCredential(phoneCredential)
          .timeout(const Duration(seconds: 10));
          
      print(' SIGNUP: Phone linked');
    } on TimeoutException {
      print(' SIGNUP: Phone link TIMED OUT');
    } on FirebaseAuthException catch (e) {
      print(' SIGNUP: Phone link FAILED: ${e.code} - ${e.message}');
    }
  }

  final uid = result.user?.uid;
  if (uid == null) {
    print(' SIGNUP: ERROR - user is null after creation!');
    throw Exception('User creation failed');
  }

  print(' SIGNUP: Writing to Firestore users/$uid');
  try {
    await _firestore.collection('users').doc(uid).set({
      'email': email,
      'phone': phone ?? '',
      'role': 'user',
      'createdAt': FieldValue.serverTimestamp(),
    });
    print(' SIGNUP: Firestore write SUCCESS');
  } catch (e) {
    print(' SIGNUP: Firestore write FAILED: $e');
    rethrow;
  }
}

// ══════════════════════════════════════════════════════════════════════════
// MQTT AUTO-SUBSCRIPTION
// ══════════════════════════════════════════════════════════════════════════
/// Subscribes to all user devices. Call after connect + on device list changes.
Future<void> subscribeToAllDevices(List<DeviceModel> devices) async {
  if (!mqttConnected) {
    _logger.w('MQTT not connected — queuing ${devices.length} devices');
    for (final device in devices) {
      _pendingSubscriptions.add(device.deviceId);
    }
    if (_lastBrokerHost != null && !_isReconnecting) {
      _scheduleReconnect();
    }
    return;
  }
  for (final device in devices) {
    _subscribeToDeviceInternal(device.deviceId);
  }
}

/// Subscribe single device. Queues if MQTT is offline.
void subscribeToDevice(String deviceId) {
  if (!mqttConnected) {
    _pendingSubscriptions.add(deviceId);
    _logger.w('MQTT offline — queued subscription for $deviceId');
    return;
  }
  _subscribeToDeviceInternal(deviceId);
}

void _subscribeToDeviceInternal(String deviceId) {
  _mqttClient!.subscribe('growwiser/$deviceId/sensors', MqttQos.atLeastOnce);
  _mqttClient!.subscribe('growwiser/$deviceId/status', MqttQos.atLeastOnce);
  _mqttClient!.subscribe('growwiser/$deviceId/errors', MqttQos.atLeastOnce);
  _logger.i('Subscribed to device $deviceId');
}

void _onMqttConnected() {
 _isIntentionalDisconnect = false;
  _reconnectAttempts = 0;
  _isReconnecting = false;
    _logger.i('MQTT connected');  

  // Drain pending subscriptions
  final pending = _pendingSubscriptions.toList();
  _pendingSubscriptions.clear();
  for (final deviceId in pending) {
    _subscribeToDeviceInternal(deviceId);
  }
}

bool _isIntentionalDisconnect = false;

Future<void> disconnectMqtt() async {
  _isIntentionalDisconnect = true;
  _cancelReconnect();
  _mqttClient?.disconnect();
  _mqttClient = null;
}

void _onMqttDisconnected() {
  // Don't reconnect if this was an intentional disconnect
  if (_isIntentionalDisconnect) {
    _logger.i('MQTT intentionally disconnected — not reconnecting');
    return;
  }
  
  // Don't reconnect if user logged out
  if (_auth.currentUser == null) {
    _logger.i('User logged out — not reconnecting MQTT');
    return;
  }
  
  _logger.w('MQTT disconnected — scheduling reconnect...');
  _scheduleReconnect();
}
/// Call this when a new device is added (e.g. after claim)
void subscribeToDeviceIfConnected(String deviceId) {
  if (mqttConnected) {
    subscribeToDevice(deviceId);
  } else {
    _logger.w('MQTT offline — will subscribe to $deviceId on reconnect');
  }
}




  // ══════════════════════════════════════════════════════════════════════════
  // DEVICE REGISTRATION
  // ══════════════════════════════════════════════════════════════════════════

  Future<String> generateClaimToken(String deviceId) async {
    final token = _uuid.v4();
    await _firestore.collection('devices').doc(deviceId).set(
        {'claimToken': token, 'claimed': false, 'claimedBy' : '',}, SetOptions(merge: true));
    _logger.i('Claim token generated for $deviceId');
    return token;
  }

 Future<void> claimDevice({
  required String deviceId,
  String? token,
  required String name,
  required String location,
}) async {
  final uid = _auth.currentUser?.uid;
  if (uid == null) throw Exception('Not authenticated');

  final deviceRef = _firestore.collection('devices').doc(deviceId);

  await _firestore.runTransaction((tx) async {
    final snap = await tx.get(deviceRef);

    if (!snap.exists) {
      // Manual entry: auto-create registry entry
      if (token != null) {
        throw Exception('Device not found in registry.');
      }
      
      tx.set(deviceRef, {
        'claimToken': _uuid.v4(),
        'claimed': true,
        'claimedBy': uid,
        'claimedAt': FieldValue.serverTimestamp(),
        'name': name,
        'location': location,
        'registeredAt': FieldValue.serverTimestamp(),
      });
    } else {
      final data = snap.data()!;
      
      if (token != null) {
        // QR claim: validate token
        if (data['claimToken'] != token) {
          throw Exception('Invalid device token.');
        }
        if ((data['claimedBy'] as String?)?.isNotEmpty == true) {
          throw Exception('This device is already claimed by another user.');
        }
      } else {
        // Manual entry
        final claimedBy = data['claimedBy'] as String?;
        if (claimedBy != null && claimedBy.isNotEmpty && claimedBy != uid) {
          throw Exception('This device is already claimed by another user.');
        }
      }

      tx.update(deviceRef, {
        'claimedBy': uid,
        'claimedAt': FieldValue.serverTimestamp(),
        'claimed': true,
        'name': name,
        'location': location,
      });
    }

    // Link to user's Firestore subcollection
    final userDeviceRef = _firestore
        .collection('users')
        .doc(uid)
        .collection('devices')
        .doc(deviceId);

    tx.set(userDeviceRef, {'deviceId': deviceId});
  });

  // Mirror to RTDB
try {
  final rtdbDeviceRef = _rtdb.child('Devices/$deviceId');
  final existingSnap = await rtdbDeviceRef.get();

  await rtdbDeviceRef.update({
    'ownerId': uid,  
    'name': name,
    'location': location,
  });

  if (!existingSnap.exists) {
    await rtdbDeviceRef.update({
      'moistureThreshold': 40.0,
      'moistureUpperLimit': 80.0,
      'scheduleEnabled': false,
      'control': {'autoMode': true, 'pumpState': false},
      'sensors': {
        'humidity': 0,
        'lastUpdated': ServerValue.timestamp,
        'moisture': 0,
        'temperature': 0,
      },
    });
  }

  // This is the critical line that links device to user
  await _rtdb.child('UserDevices/$uid/$deviceId').set(true);
  _logger.i('✅ UserDevices link created: UserDevices/$uid/$deviceId = true');

} catch (e, st) {
  _logger.e('❌ RTDB write failed during claim: $e');
  _logger.e('Stack: $st');
  rethrow; // Don't swallow this — let the UI know it failed
}
}

/// Releases device — clears claimedBy so it's claimable again.
Future<void> releaseDevice({required String deviceId}) async {
  final uid = _auth.currentUser?.uid;
  if (uid == null) throw Exception('Not authenticated');

  final deviceRef = _firestore.collection('devices').doc(deviceId);
  final userDeviceRef = _firestore
      .collection('users')
      .doc(uid)
      .collection('devices')
      .doc(deviceId);

  await _firestore.runTransaction((tx) async {
    final snap = await tx.get(deviceRef);
    if (!snap.exists) throw Exception('Device not found.');

    if (snap.data()?['claimedBy'] != uid) {
      throw Exception('You do not own this device.');
    }

    tx.update(deviceRef, {
      'claimedBy': '',
      'claimedAt': null,
      'claimed' : false,
      'name': '',
      'location': '',
    });

    tx.delete(userDeviceRef);
  });

  // ─── RTDB: remove user link and clear owner metadata ─────────────────────
  await FirebaseDatabase.instance.ref('UserDevices/$uid/$deviceId').remove();

  // Clear ownership fields but leave sensor history intact
  await FirebaseDatabase.instance.ref('Devices/$deviceId').update({
    'ownerId': null,
    'name': null,
    'location': null,
  });

  _logger.i('Device $deviceId released in Firestore + unlinked from RTDB');
}

  // ══════════════════════════════════════════════════════════════════════════
  // DEVICE CONFIG
  // ══════════════════════════════════════════════════════════════════════════

  Future<List<DeviceModel>> fetchUserDevices() async {
    final user = FirebaseAuth.instance.currentUser;
    debugPrint('🔍 fetchUserDevices() called');
    debugPrint(
        '   Current user: ${user?.uid ?? "NULL - NOT AUTHENTICATED"}');

    if (user == null) throw Exception('Not authenticated');

    final userDevicesRef =
        FirebaseDatabase.instance.ref('UserDevices/${user.uid}');
    final userDevicesSnap = await userDevicesRef.get();

    if (!userDevicesSnap.exists) {
      debugPrint('   No devices found for user ${user.uid}');
      return [];
    }

    final deviceIds =
        (userDevicesSnap.value as Map).keys.cast<String>();

    final devices = <DeviceModel>[];
    for (final deviceId in deviceIds) {
      final deviceSnap = await FirebaseDatabase.instance
          .ref('Devices/$deviceId')
          .get();
      if (deviceSnap.exists) {
        final data = deviceSnap.value as Map<dynamic, dynamic>;
        devices.add(DeviceModel.fromRtdb(data, deviceId));
      }
    }
    return devices;
  }

  Future<SensorData?> fetchLatestSensorData(String deviceId) async {
    
    try {
      final snapshot = await FirebaseDatabase.instance
          .ref('Devices/$deviceId/sensors')
          .get()
          .timeout(const Duration(seconds: 5));

      if (!snapshot.exists || snapshot.value == null) return null;
      
      final data = snapshot.value as Map<dynamic, dynamic>;
      return SensorData(
        moisture: (data['moisture'] as num?)?.toDouble() ?? 0.0,
        temperature: (data['temperature'] as num?)?.toDouble() ?? 0.0,
        humidity: (data['humidity'] as num?)?.toDouble() ?? 0.0,
        timestamp: data['lastUpdated'] as int?,
      );
    } catch (e) {
      debugPrint('fetchLatestSensorData($deviceId) failed: $e');
      return null;
    }
  }

  
  Stream<DeviceModel> watchDeviceConfig(String deviceId) {
     if (deviceId == 'no-device') {
    return Stream.value(DeviceModel.empty());
  }
    return FirebaseDatabase.instance
        .ref('Devices/$deviceId')
        .onValue
        .map((event) {
      final data =
          event.snapshot.value as Map<dynamic, dynamic>? ?? {};
      return DeviceModel.fromRtdb(data, deviceId);
    });
  }

  Future<void> updateDeviceConfig(
    String deviceId, Map<String, dynamic> updates) async {
  final uid = currentUser?.uid;
  if (uid == null) throw Exception('Not authenticated');


  final ownerSnap = await _rtdb.child('Devices/$deviceId/ownerId').get();
  if (!ownerSnap.exists || ownerSnap.value != uid) {
    throw Exception('You do not own this device.');
  }


  await _rtdb.child('Devices/$deviceId').update(updates);
  _logger.i('Device $deviceId config updated: $updates');
}

  // ══════════════════════════════════════════════════════════════════════════
  // LIVE SENSOR DATA
  // ══════════════════════════════════════════════════════════════════════════

 Stream<SensorData> watchSensorData(String deviceId) {
   if (deviceId == 'no-device') {
    return Stream.value(SensorData.empty());
  }
  return FirebaseDatabase.instance
      .ref('Devices/$deviceId/sensors')
      .onValue
      .map((event) {
        final data = event.snapshot.value as Map<dynamic, dynamic>?;
        if (data == null) {
          return SensorData(
            moisture: 0.0,
            temperature: 0.0,
            humidity: 0.0,
            timestamp: null,
          );
        }
        return SensorData(
          moisture: (data['moisture'] as num?)?.toDouble() ?? 0.0,
          temperature: (data['temperature'] as num?)?.toDouble() ?? 0.0,
          humidity: (data['humidity'] as num?)?.toDouble() ?? 0.0,
          timestamp: data['lastUpdated'] as int?,
        );
      })
      .handleError((e) {
        debugPrint('watchSensorData($deviceId) error: $e');
      });
}

  Stream<Map<dynamic, dynamic>> watchControlState(String deviceId) {
    return _rtdb.child('Devices/$deviceId/control').onValue.map(
        (event) =>
            event.snapshot.value as Map<dynamic, dynamic>? ?? {});
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MQTT
  // ══════════════════════════════════════════════════════════════════════════

  /// Connect to Mosquitto broker.
  /// Saves credentials so _reconnect() can reuse them automatically.
  Future<void> connectMqtt({
    required String brokerHost,
    int port = 1883,
    String? username,
    String? password,
  }) async {
    // Save for reconnect
    _lastBrokerHost = brokerHost;
    _lastPort = port;
    _lastMqttUsername = username;
    _lastMqttPassword = password;
    _reconnectAttempts = 0;

    await _doConnect(
        brokerHost: brokerHost,
        port: port,
        username: username,
        password: password);
  }

String? _stableClientId;

Future<void> _doConnect({
  required String brokerHost,
  int port = 1883,
  String? username,
  String? password,
}) async {
  // Use stable client ID — only generate once per app session
  _stableClientId ??= 'growwiser_${currentUser?.uid ?? _uuid.v4()}';
  
  
  final clientId = _stableClientId!;
  
  _mqttClient = MqttServerClient(brokerHost, clientId)
    ..port = port
    ..keepAlivePeriod = 60
    ..onDisconnected = _onMqttDisconnected
    ..onConnected = _onMqttConnected
    ..logging(on: false);

  if (username != null) {
    _mqttClient!.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)  
        .authenticateAs(username, password ?? '')
        .startClean();
  }

  try {
    await _mqttClient!.connect();
  } on NoConnectionException catch (e) {
    _logger.e('MQTT connection failed: $e');
    rethrow;
  } on SocketException catch (e) {
    _logger.e('MQTT socket error: $e');
    rethrow;
  }
}

  // ─── Exponential backoff reconnect ────────────────────────────────────────
  void _scheduleReconnect() {
    if (_isReconnecting) return;
    if (_lastBrokerHost == null) return;
    if (mqttConnected) {
    _logger.i('Already connected — skipping reconnect');
    return;
  }
    _isReconnecting = true;
    // Backoff: 2s, 4s, 8s, 16s, 32s
    final delay =
        Duration(seconds: (2 << _reconnectAttempts).clamp(2, 32));
    _reconnectAttempts++;

    _logger.i(
        'MQTT reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempts/$_maxReconnectAttempts)...');

    _reconnectTimer = Timer(delay, () async {
      _isReconnecting = false;
      try {
        await _doConnect(
          brokerHost: _lastBrokerHost!,
          port: _lastPort,
          username: _lastMqttUsername,
          password: _lastMqttPassword,
        );
        // Success — reset counter
        _reconnectAttempts = 0;
        _logger.i('MQTT reconnected successfully.');
      } catch (e) {
        _logger.w('MQTT reconnect attempt failed: $e');
        _scheduleReconnect(); // try again
      }
    });
  }

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _isReconnecting = false;
    _reconnectAttempts = 0;
  }

    // ─── SaveDeviceConfiguration ──────────────────────────────────────────────────────

  Future<void> updateDevice({
  required String deviceId,
  required String name,
  required String location,
}) async {
  final uid = _auth.currentUser?.uid;
  if (uid == null) throw Exception('Not authenticated');


  final deviceRef = _firestore.collection('devices').doc(deviceId);
  final snap = await deviceRef.get();

  if (snap.data()?['claimedBy'] != uid) {
    throw Exception('You do not own this device.');
  }

  await deviceRef.update({'name': name, 'location': location});

  await _rtdb.child('Devices/$deviceId').update({
    'name': name,
    'location': location,
  });

  _logger.i('Device $deviceId updated: name="$name", location="$location"');
}

  // ─── sendPumpCommand ──────────────────────────────────────────────────────
  /// Sends pump on/off to ESP32 via MQTT, mirrors to RTDB, logs the event.
  ///
  /// THROWS [MqttNotConnectedException] if broker is not connected so the
  /// UI can show a proper error snackbar instead of a false-positive success.
  Future<void> sendPumpCommand(String deviceId, bool state) async {

     debugPrint('🔴 MQTT State: ${_mqttClient?.connectionStatus?.state}');
  debugPrint('🔴 _mqttClient is null: ${_mqttClient == null}');
  debugPrint('🔴 mqttConnected: $mqttConnected');
    // 1. Guard — surface to UI instead of silently dropping
    if (!mqttConnected) {
      // Kick off background reconnect so next tap may succeed
      _scheduleReconnect();
      throw const MqttNotConnectedException();
    }

    // 2. Publish to ESP32 via MQTT
    _publishMqtt(
      topic: 'growwiser/$deviceId/control',
      payload: '{"pumpState": $state}',
    );

    // 3. Mirror to RTDB for UI sync
    await _rtdb
        .child('Devices/$deviceId/control/pumpState')
        .set(state);

    // 4. Log irrigation event when pump turns ON
    if (state == true) {
      final sensorSnap = await fetchLatestSensorData(deviceId);
      await logIrrigation(
        deviceId: deviceId,
        mode: 'manual',
        soilMoisture: sensorSnap?.moisture ?? 0.0,
      );
    }
  }

  Future<void> setAutoMode(String deviceId, bool enabled) async {
    // Best-effort — auto mode is also stored in RTDB so ESP32 picks it
    // up on next sync even if MQTT is momentarily down.
    if (mqttConnected) {
      _publishMqtt(
        topic: 'growwiser/$deviceId/control',
        payload: '{"autoMode": $enabled}',
      );
    } else {
      _logger.w(
          'MQTT offline — autoMode will sync via RTDB only for $deviceId');
    }
    await _rtdb
        .child('Devices/$deviceId/control/autoMode')
        .set(enabled);
  }

  

  // ── Weather cache ─────────────────────────────────────────────────────────────
// Reads cached weather JSON from RTDB at users/{uid}/weatherCache
// Returns null if no cache exists or user is not signed in.

Future<Map<String, dynamic>?> getWeatherCache() async {
  final uid = _auth.currentUser?.uid;
  if (uid == null) return null;
  final snap = await _rtdb.child('users/$uid/weatherCache').get();
  if (!snap.exists || snap.value == null) return null;
  return Map<String, dynamic>.from(snap.value as Map);
}

// Saves weather JSON to RTDB at users/{uid}/weatherCache
// Also stores the lat/lon that produced it (for manual location edits).
Future<void> saveWeatherCache({
  required Map<String, dynamic> data,
  required double lat,
  required double lon,
  required String locationName,
}) async {
  final uid = _auth.currentUser?.uid;
  if (uid == null) return;
  await _rtdb.child('users/$uid/weatherCache').set({
    ...data,
    'lat': lat,
    'lon': lon,
    'locationName': locationName,
    'cachedAt': DateTime.now().toIso8601String(),
  });
}

// Fetches city coordinates from Nominatim search by city name.
// Returns {lat, lon, displayName} or null on failure.
Future<Map<String, dynamic>?> geocodeCity(String cityName) async {
  try {
    final res = await http.get(
      Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeComponent(cityName)}&format=json&limit=1',
      ),
      headers: {'User-Agent': 'GrowWiser/1.0'},
    ).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return null;
    final list = jsonDecode(res.body) as List;
    if (list.isEmpty) return null;
    final first = list.first as Map<String, dynamic>;
    return {
      'lat': double.parse(first['lat'] as String),
      'lon': double.parse(first['lon'] as String),
      'displayName': (first['display_name'] as String).split(',').first.trim(),
    };
  } catch (_) {
    return null;
  }
}


  // ══════════════════════════════════════════════════════════════════════════
  // IRRIGATION LOGIC
  // ══════════════════════════════════════════════════════════════════════════

  IrrigationMode getIrrigationMode(
      double moisture, DeviceModel config) {
    return IrrigationLogic.evaluate(
      moisture: moisture,
      lowerThreshold: config.moistureThreshold,
      upperThreshold: config.moistureUpperLimit,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ADMIN
  // ══════════════════════════════════════════════════════════════════════════

  Future<bool> isAdmin() async {
    final uid = currentUser?.uid;
    if (uid == null) return false;
    try {
      final doc =
          await _firestore.collection('users').doc(uid).get();
      return doc.data()?['role'] == 'admin';
    } on Exception catch (e) {
      _logger.e('isAdmin check failed: $e');
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // IRRIGATION LOGGING
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> logIrrigation({
    required String deviceId,
    required String mode,
    required double soilMoisture,
  }) async {
    final uid = currentUser?.uid;
    if (uid == null) return;

    await _firestore
        .collection('users')
        .doc(uid)
        .collection('irrigationLogs')
        .add({
      'device_id': deviceId,
      'user_id': uid,
      'end_time': FieldValue.serverTimestamp(),
      'mode': mode,
      'soil_moisture': soilMoisture,
    });

    await _rtdb
        .child('Devices/$deviceId/control/lastWatered')
        .set(DateTime.now().toIso8601String());

    _logger.i('Irrigation logged for $deviceId — mode: $mode');
  }

  Future<List<Map<String, dynamic>>> fetchIrrigationLogs(
      String deviceId) async {
    final uid = currentUser?.uid;
    if (uid == null) return [];

    final snap = await _firestore
        .collection('users')
        .doc(uid)
        .collection('irrigationLogs')
        .where('device_id', isEqualTo: deviceId)
        .orderBy('end_time', descending: true)
        .limit(20)
        .get();

    return snap.docs.map((d) => d.data()).toList();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ERROR LOGGING
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> logDeviceError({
    required String deviceId,
    required String errorCode,
     String detail = '—',
  String severity = 'warning',
  }) async {
    final uid = currentUser?.uid;
    if (uid == null) return;

     final ownerSnap = await _rtdb.child('Devices/$deviceId/ownerId').get();
    final ownerId = ownerSnap.value as String? ?? uid;

    await _firestore
        .collection('users')
        .doc(ownerId)
        .collection('devices')
        .doc(deviceId)
        .collection('errors')
        .add({
      'device_id': deviceId,
      'error_code': errorCode,
      'detail': detail,
    'severity': severity,
      'resolved': false,
      'created_at': FieldValue.serverTimestamp(),
    });

     await _rtdb.child('Devices/$deviceId/lastError').set({
    'code': errorCode,
    'detail': detail,
    'severity': severity,
    'timestamp': ServerValue.timestamp,
     });

  _logger.w('Error logged for $deviceId: $errorCode — $detail');
  }

  Future<bool> isPhoneRegistered(String phone) async {
    final snap = await _firestore
        .collection('users')
        .where('phone', isEqualTo: phone)
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  Future<bool> isEmailRegistered(String email) async {
    final snap = await _firestore
        .collection('users')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PRIVATE HELPERS
  // ══════════════════════════════════════════════════════════════════════════

  /// Throws if not connected (callers that need guaranteed delivery use this).
  void _publishMqtt(
      {required String topic, required String payload}) {
    if (!mqttConnected) {
      // Should not reach here from sendPumpCommand — guard is above.
      // For any other caller, log and throw.
      _logger.w('MQTT not connected — publish aborted: $topic');
      throw const MqttNotConnectedException();
    }
    final builder = MqttClientPayloadBuilder()..addString(payload);
    _mqttClient!
        .publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
    _logger.d('MQTT publish [$topic]: $payload');
  }

 

// ══════════════════════════════════════════════════════════════════════════
// MOISTURE BASED NEXT WATER CALCULATIONS AND SNAPSHOT
// ══════════════════════════════════════════════════════════════════════════

final Map<String, DateTime> _lastSnapshotTime = {};
final Map<String, double> _lastRecordedMoisture = {};
static const double _minMoistureChange = 2.0; // only record if changed by 2%
static const int _minSnapshotIntervalMinutes = 30; // or record eevry 30 mins

Future<String?> recordMoistureSnapshot(
  String deviceId,
  double moisture, {
  double? temperature,
  double? humidity,
}) async {
  final uid = _auth.currentUser?.uid;
  if (uid == null) return null;

  final now = DateTime.now();

  // Throttle: skip if too soon and moisture barely changed
  if (_lastSnapshotTime.containsKey(deviceId)) {
    final minutesSinceLast = now.difference(_lastSnapshotTime[deviceId]!).inMinutes;
    final moistureChanged = !_lastRecordedMoisture.containsKey(deviceId) ||
        (moisture - _lastRecordedMoisture[deviceId]!).abs() >= _minMoistureChange;

    if (minutesSinceLast < _minSnapshotIntervalMinutes && !moistureChanged) {
  debugPrint('⏭ Snapshot throttled for $deviceId: ${minutesSinceLast}min, moisture $moisture (last: ${_lastRecordedMoisture[deviceId]})');
  return predictNextWaterTime(deviceId);
}
  }

  _lastSnapshotTime[deviceId] = now;
  _lastRecordedMoisture[deviceId] = moisture;


  final historyRef = _rtdb.child('Devices/$deviceId/moistureHistory');
  final sensorsRef = _rtdb.child('Devices/$deviceId/sensors');

  // Read lastUpdated from sensors as reference timestamp
  final sensorsSnap = await sensorsRef.get();
  final timestamp = sensorsSnap.exists && sensorsSnap.value != null
      ? (sensorsSnap.value as Map)['lastUpdated'] as int? ?? DateTime.now().millisecondsSinceEpoch
      : DateTime.now().millisecondsSinceEpoch;

  // Push history record using the sensor's timestamp
  await historyRef.push().set({
    'moisture': moisture,
    'temperature': temperature ?? 0.0,
    'humidity': humidity ?? 0.0,
    'timestamp': timestamp,
  });

  // Prune: keep only last 10 snapshots
  final snap = await historyRef.orderByChild('timestamp').limitToLast(11).get();
  if (snap.exists && snap.value != null) {
    final entries = (snap.value as Map).entries.toList()
      ..sort((a, b) => (a.value['timestamp'] as int)
          .compareTo(b.value['timestamp'] as int));
    if (entries.length > 10) {
      for (int i = 0; i < entries.length - 10; i++) {
        await historyRef.child(entries[i].key).remove();
      }
    }
  }

  return predictNextWaterTime(deviceId);
}

Future<String?> predictNextWaterTime(String deviceId) async {
  try {
    debugPrint(' predictNextWaterTime() called for $deviceId');

    final snap = await _rtdb
        .child('Devices/$deviceId/moistureHistory')
        .orderByChild('timestamp')
        .limitToLast(12)
        .get();

    debugPrint(' snap.exists: ${snap.exists}, type: ${snap.value?.runtimeType}');

    if (!snap.exists || snap.value == null) {
      debugPrint(' No history data');
      return null;
    }

    // Extract entries with proper null checking
    final List<Map<String, dynamic>> entries = [];
    
    if (snap.value is Map) {
      final map = snap.value as Map<dynamic, dynamic>;
      for (final entry in map.entries) {
        debugPrint(' Key: ${entry.key}, Value type: ${entry.value?.runtimeType}');
        
        if (entry.value is! Map) {
          debugPrint(' Skipping non-Map entry: ${entry.value}');
          continue;
        }
        
        final value = entry.value as Map<dynamic, dynamic>;
        entries.add({
          'moisture': (value['moisture'] as num?)?.toDouble() ?? 0.0,
          'temperature': (value['temperature'] as num?)?.toDouble() ?? 25.0,
          'humidity': (value['humidity'] as num?)?.toDouble() ?? 60.0,
          'timestamp': (value['timestamp'] as num?)?.toInt() ?? 0,
        });
      }
    } else if (snap.value is List) {
      final list = snap.value as List;
      for (int i = 0; i < list.length; i++) {
        final item = list[i];
        debugPrint(' List[$i] type: ${item?.runtimeType}');
        
        if (item is! Map) continue;
        
        entries.add({
          'moisture': (item['moisture'] as num?)?.toDouble() ?? 0.0,
          'temperature': (item['temperature'] as num?)?.toDouble() ?? 25.0,
          'humidity': (item['humidity'] as num?)?.toDouble() ?? 60.0,
          'timestamp': (item['timestamp'] as num?)?.toInt() ?? 0,
        });
      }
    } else {
      debugPrint(' Unknown data type: ${snap.value.runtimeType}');
      return null;
    }

    debugPrint(' Parsed entries: ${entries.length}');

    if (entries.length < 2) {
      debugPrint(' Need 2+ entries, have ${entries.length}');
      return null;
    }

    entries.sort((a, b) => (a['timestamp'] as int).compareTo(b['timestamp'] as int));

    // Current conditions from the latest snapshot
    final currentMoisture = entries.last['moisture'] as double;
    final currentTemp = entries.last['temperature'] as double;
    final currentHumidity = entries.last['humidity'] as double;

    const threshold = 40.0;
    if (currentMoisture <= threshold) return 'NOW';

    // Build weighted drying rates from consecutive pairs
    double weightedRateSum = 0;
    double totalWeight = 0;

    for (int i = 1; i < entries.length; i++) {
      final prev = entries[i - 1];
      final curr = entries[i];

      final dtHours =
          ((curr['timestamp'] as int) - (prev['timestamp'] as int)) /
              3600000.0;
      if (dtHours < 0.05) continue;

      final dMoisture =
          (prev['moisture'] as double) - (curr['moisture'] as double);
      if (dMoisture < 0) continue;

      final rate = dMoisture / dtHours;
      final effectiveRate = rate <= 0 ? 0.05 : rate;

      final intervalTemp =
          ((prev['temperature'] as double) + (curr['temperature'] as double)) / 2;
      final intervalHumidity =
          ((prev['humidity'] as double) + (curr['humidity'] as double)) / 2;

      final tempDiff = (intervalTemp - currentTemp).abs();
      final humidDiff = (intervalHumidity - currentHumidity).abs();
      final weight = math.exp(-(tempDiff * tempDiff) / 50.0) *
                     math.exp(-(humidDiff * humidDiff) / 800.0);

      weightedRateSum += effectiveRate * weight;
      totalWeight += weight;
    }

    debugPrint(' weightedRateSum: $weightedRateSum, totalWeight: $totalWeight');

    if (totalWeight == 0 || weightedRateSum == 0) {
      debugPrint(' No valid drying intervals');
      return null;
    }


    final tempFactor = math.exp((currentTemp - 25.0) / 15.0);
    final humidFactor = math.max(0.2, 1.0 - (currentHumidity - 60.0) / 200.0);
    final conditionScale = tempFactor * humidFactor;

    final baseRate = weightedRateSum / totalWeight;
    final adjustedRate = baseRate * conditionScale;

    debugPrint(' adjustedRate: $adjustedRate');

    const minRealRate = 0.1; 
if (baseRate <= minRealRate) {
  debugPrint('Drying rate too low ($baseRate), not enough real drying data');
  return 'SOON'; // or null
}

    if (adjustedRate <= 0) return null;

    final hoursUntil = (currentMoisture - threshold) / adjustedRate;

    final projected = DateTime.now().add(
      Duration(minutes: (hoursUntil * 60).round()),
    );
    final now = DateTime.now();

    final isToday = projected.day == now.day &&
        projected.month == now.month &&
        projected.year == now.year;
    final isTomorrow = projected.difference(now).inHours < 48 &&
        projected.day != now.day;

    final hour = projected.hour;
    final suffix = hour >= 12 ? 'P.M' : 'A.M';
    final display = hour % 12 == 0 ? 12 : hour % 12;
    final timeStr = '$display $suffix';

    final result = hoursUntil < 1 ? '< 1 HR' :
                   isToday ? timeStr :
                   isTomorrow ? 'TMR $timeStr' :
                   '+${hoursUntil.round()}H';

    debugPrint(' Prediction: $result');
    return result;
  } catch (e, st) {
    debugPrint(' predictNextWaterTime error: $e');
    debugPrint(' Stack: $st');
    return null;
  }
}

void subscribeToDeviceErrors(String deviceId) {
  if (!mqttConnected) {
    _pendingSubscriptions.add('$deviceId/errors');
    return;
  }
  _mqttClient!.subscribe(
    'growwiser/$deviceId/errors',
    MqttQos.atLeastOnce,
  );
  _logger.i('Subscribed to errors for $deviceId');
}

Future<void> handleIncomingMqttMessage(String topic, String payload) async {
  // Check if this is an error topic
  final errorMatch = RegExp(r'growwiser/(.+)/errors').firstMatch(topic);
  if (errorMatch != null) {
    final deviceId = errorMatch.group(1)!;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      await logDeviceError(
        deviceId: deviceId,
        errorCode: data['code'] as String? ?? 'UNKNOWN',
        detail: data['detail'] as String? ?? '—',
        severity: data['severity'] as String? ?? 'warning',
      );
    } catch (e) {
      _logger.e('Failed to parse error payload: $e');
    }
  }
}

}