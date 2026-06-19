import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../theme/app_theme.dart';
import '../services/backend_service.dart';
import '../providers/backend_providers.dart';
import '../models/device.dart';
import 'dart:convert';

// ══════════════════════════════════════════════════════════════════════════
// DEVICES PAGE
// ══════════════════════════════════════════════════════════════════════════

class DevicesPage extends ConsumerStatefulWidget {
  const DevicesPage({super.key});

  @override
  ConsumerState<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends ConsumerState<DevicesPage> {
  final int _currentIndex = 2;
  bool _isAdmin = false;
  bool _isClaiming = false;

  @override
  void initState() {
    super.initState();
    _loadAdminStatus();
  }

  Future<void> _loadAdminStatus() async {
    final admin = await BackendService().isAdmin();
    if (mounted) setState(() => _isAdmin = admin);
  }

  void _onNavTap(int index) {
    final isLogout = _isAdmin ? index == 1 : index == 3;
    if (isLogout) {
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }
    if (!_isAdmin) {
      final routes = ['/home', '/command', '/devices'];
      Navigator.pushReplacementNamed(context, routes[index]);
    } else {
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // QR SCAN FLOW
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _startQrScan() async {
    final scanned = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _QrScannerPage()),
    );

    if (scanned == null || !mounted) return;

    Map<String, dynamic> qrData;
    try {
      qrData = _parseQr(scanned);
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invalid QR code. Please scan a GrowWiser device.',
                style: AppTextStyles.mono(12, Colors.white)),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    final deviceId = qrData['deviceId'] as String?;
    final token = qrData['token'] as String?;

    if (deviceId == null || deviceId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('QR missing device info.',
                style: AppTextStyles.mono(12, Colors.white)),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    // Ask user for name and location
    final details = await _showDeviceDetailsDialog();
    if (details == null || !mounted) return;

    // Claim the device (token can be null for manual entry)
    setState(() => _isClaiming = true);
    try {
      await BackendService().claimDevice(
        deviceId: deviceId,
        token: token,
        name: details['name']!,
        location: details['location']!,
      );
      ref.invalidate(userDevicesProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${details['name']} added successfully!',
                style: AppTextStyles.mono(12, Colors.white)),
            backgroundColor: AppColors.deepGreen,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add device: $e',
                style: AppTextStyles.mono(12, Colors.white)),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isClaiming = false);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MANUAL ENTRY FLOW
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _startManualEntry() async {
    final deviceId = await _showManualEntryDialog();
    if (deviceId == null || !mounted) return;

    final details = await _showDeviceDetailsDialog();
    if (details == null || !mounted) return;

    setState(() => _isClaiming = true);
    try {
      await BackendService().claimDevice(
        deviceId: deviceId,
        token: null, // manual entry — no QR token
        name: details['name']!,
        location: details['location']!,
      );

      ref.invalidate(userDevicesProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${details['name']} added successfully!',
                style: AppTextStyles.mono(12, Colors.white)),
            backgroundColor: AppColors.deepGreen,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add device: $e',
                style: AppTextStyles.mono(12, Colors.white)),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isClaiming = false);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DIALOGS
  // ══════════════════════════════════════════════════════════════════════════

  Future<String?> _showManualEntryDialog() async {
    final ctrl = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.deepGreen,
        title: Text('Enter Device ID',
            style: AppTextStyles.headline(18, AppColors.textPrimary,
                weight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          style: AppTextStyles.mono(14, AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'e.g. ESP32_ABC123',
            hintStyle: AppTextStyles.mono(14,
                AppColors.textPrimary.withValues(alpha: 0.5)),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(
                  color: AppColors.textPrimary.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(8),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: AppColors.seaGreen),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text('CANCEL',
                style: AppTextStyles.mono(12,
                    AppColors.textPrimary.withValues(alpha: 0.6))),
          ),
          TextButton(
            onPressed: () {
              final id = ctrl.text.trim();
              if (id.isEmpty) return;
              Navigator.pop(ctx, id);
            },
            child: Text('CONFIRM',
                style: AppTextStyles.mono(12, AppColors.seaGreen,
                    weight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<Map<String, String>?> _showDeviceDetailsDialog() async {
    final nameCtrl = TextEditingController();
    final locationCtrl = TextEditingController();

    return showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.deepGreen,
        title: Text('Name Your Device',
            style: AppTextStyles.headline(18, AppColors.textPrimary,
                weight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              style: AppTextStyles.mono(14, AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'e.g. Garden Sensor 1',
                hintStyle: AppTextStyles.mono(14,
                    AppColors.textPrimary.withValues(alpha: 0.5)),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                      color: AppColors.textPrimary.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: AppColors.seaGreen),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: locationCtrl,
              style: AppTextStyles.mono(14, AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'e.g. Backyard',
                hintStyle: AppTextStyles.mono(14,
                    AppColors.textPrimary.withValues(alpha: 0.5)),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                      color: AppColors.textPrimary.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: AppColors.seaGreen),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text('CANCEL',
                style: AppTextStyles.mono(12,
                    AppColors.textPrimary.withValues(alpha: 0.6))),
          ),
          TextButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              final location = locationCtrl.text.trim();
              if (name.isEmpty || location.isEmpty) return;
              Navigator.pop(ctx, {'name': name, 'location': location});
            },
            child: Text('CONFIRM',
                style: AppTextStyles.mono(12, AppColors.seaGreen,
                    weight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // EDIT DEVICE SHEET
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _showEditDeviceSheet(DeviceModel device) async {
    final nameCtrl = TextEditingController(text: device.name);
    final locationCtrl = TextEditingController(text: device.location);

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.seaGreen,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(device.name,
                        style: AppTextStyles.headline(16, AppColors.textPrimary,
                            weight: FontWeight.bold)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE4F27A).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color(0xFFE4F27A).withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.edit_outlined,
                            size: 12, color: Color(0xFFE4F27A)),
                        const SizedBox(width: 4),
                        Text('EDIT',
                            style: AppTextStyles.mono(9, const Color(0xFFE4F27A),
                                letterSpacing: 0.5)),
                      ],
                    ),
                  ),
                ],
              ),
              Text(
                '${device.location.isEmpty ? '—' : device.location} · Added recently',
                style: AppTextStyles.mono(10,
                    AppColors.textPrimary.withValues(alpha: 0.45)),
              ),
              const SizedBox(height: 16),
              Text('DEVICE NAME',
                  style: AppTextStyles.mono(9,
                      AppColors.textPrimary.withValues(alpha: 0.45),
                      letterSpacing: 0.5)),
              const SizedBox(height: 4),
              TextField(
                controller: nameCtrl,
                style: AppTextStyles.mono(13, AppColors.textPrimary),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.black.withValues(alpha: 0.2),
                  hintText: 'e.g. Garden Sensor 1',
                  hintStyle: AppTextStyles.mono(13,
                      AppColors.textPrimary.withValues(alpha: 0.3)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                        color: const Color(0xFFE4F27A).withValues(alpha: 0.4)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.15)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                        color: Color(0xFFE4F27A), width: 1.2),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text('LOCATION',
                  style: AppTextStyles.mono(9,
                      AppColors.textPrimary.withValues(alpha: 0.45),
                      letterSpacing: 0.5)),
              const SizedBox(height: 4),
              TextField(
                controller: locationCtrl,
                style: AppTextStyles.mono(13, AppColors.textPrimary),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.black.withValues(alpha: 0.2),
                  hintText: 'e.g. Backyard',
                  hintStyle: AppTextStyles.mono(13,
                      AppColors.textPrimary.withValues(alpha: 0.3)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.15)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                        color: Color(0xFFE4F27A), width: 1.2),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text('DEVICE ID',
                  style: AppTextStyles.mono(9,
                      AppColors.textPrimary.withValues(alpha: 0.45),
                      letterSpacing: 0.5)),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Text(device.deviceId,
                    style: AppTextStyles.mono(11,
                        AppColors.textPrimary.withValues(alpha: 0.35))),
              ),
              const SizedBox(height: 18),
              // Remove device button
              SizedBox(
                width: double.infinity,
                child: GestureDetector(
                  onTap: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: AppColors.deepGreen,
                        title: Text('Remove Device',
                            style: AppTextStyles.headline(
                                16, AppColors.textPrimary,
                                weight: FontWeight.bold)),
                        content: Text(
                          'This will release "${device.name}" so it can be claimed by another user.',
                          style: AppTextStyles.mono(
                              13, AppColors.textPrimary.withValues(alpha: 0.8)),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text('CANCEL',
                                style: AppTextStyles.mono(12,
                                    AppColors.textPrimary.withValues(alpha: 0.5))),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: Text('REMOVE',
                                style: AppTextStyles.mono(12, Colors.redAccent,
                                    weight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );

                    if (confirm != true || !mounted) return;
                    Navigator.pop(ctx);

                    try {
                      await BackendService().releaseDevice(deviceId: device.deviceId);
                      ref.invalidate(userDevicesProvider);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Device removed.',
                              style: AppTextStyles.mono(12, Colors.white)),
                          backgroundColor: AppColors.deepGreen,
                          duration: const Duration(seconds: 2),
                        ));
                      }
                    } on Exception catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Failed to remove: $e',
                              style: AppTextStyles.mono(12, Colors.white)),
                          backgroundColor: Colors.redAccent,
                        ));
                      }
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.redAccent.withValues(alpha: 0.6)),
                    ),
                    alignment: Alignment.center,
                    child: Text('REMOVE DEVICE',
                        style: AppTextStyles.headline(11, Colors.redAccent,
                            letterSpacing: 1.5, weight: FontWeight.w800)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Save button
              SizedBox(
                width: double.infinity,
                child: GestureDetector(
                  onTap: () async {
                    final name = nameCtrl.text.trim();
                    final location = locationCtrl.text.trim();
                    if (name.isEmpty || location.isEmpty) return;
                    Navigator.pop(ctx);
                    try {
                      await BackendService().updateDevice(
                        deviceId: device.deviceId,
                        name: name,
                        location: location,
                      );
                      ref.invalidate(userDevicesProvider);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Device updated!',
                              style: AppTextStyles.mono(12, Colors.white)),
                          backgroundColor: AppColors.deepGreen,
                          duration: const Duration(seconds: 2),
                        ));
                      }
                    } on Exception catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Failed to update: $e',
                              style: AppTextStyles.mono(12, Colors.white)),
                          backgroundColor: Colors.redAccent,
                        ));
                      }
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE4F27A),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text('SAVE CHANGES',
                        style: AppTextStyles.headline(11, AppColors.deepGreen,
                            letterSpacing: 1.5, weight: FontWeight.w800)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // QR PARSER
  // ══════════════════════════════════════════════════════════════════════════

  Map<String, dynamic> _parseQr(String raw) {
    // Try JSON first
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}

    // Fallback: plain text "deviceId:token" or "deviceId,token"
    final separators = [':', ',', '|', ' '];
    for (final sep in separators) {
      final parts = raw.split(sep);
      if (parts.length == 2) {
        return {
          'deviceId': parts[0].trim(),
          'token': parts[1].trim(),
        };
      }
    }

    // Final fallback: treat entire string as deviceId, no token
    return {'deviceId': raw.trim()};
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final devicesAsync = ref.watch(userDevicesProvider);

    return Scaffold(
      backgroundColor: AppColors.black,
      bottomNavigationBar: GrowWiserNavBar(
        currentIndex: _currentIndex,
        onTap: _onNavTap,
        showAdmin: _isAdmin,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
          child: Column(
            children: [
              const _DevicesHeaderCard(),
              const SizedBox(height: 8),
              _DevicesMainCard(
                devicesAsync: devicesAsync,
                isClaiming: _isClaiming,
                onScanTap: _startQrScan,
                onManualTap: _startManualEntry,
                onEditDevice: _showEditDeviceSheet,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// HEADER CARD
// ══════════════════════════════════════════════════════════════════════════

class _DevicesHeaderCard extends StatelessWidget {
  const _DevicesHeaderCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('DEVICES',
                    style: AppTextStyles.headline(26, AppColors.black,
                        letterSpacing: 2, weight: FontWeight.w900)),
              ),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(top: 15, right: 0),
                  height: 4,
                  color: AppColors.black,
                ),
              ),
            ],
          ),
          Row(
            children: [
              const SizedBox(height: 4),
              Text('ADD AND VIEW DEVICE DATA HERE',
                  style: AppTextStyles.mono(9, AppColors.black,
                      letterSpacing: 1, weight: FontWeight.w500)),
              Container(
                margin: const EdgeInsets.only(left: 90),
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEEEEE),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.devices_outlined,
                    color: Color(0xFFAAAAAA), size: 28),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// MAIN CARD
// ══════════════════════════════════════════════════════════════════════════

class _DevicesMainCard extends StatelessWidget {
  final AsyncValue<List<DeviceModel>> devicesAsync;
  final bool isClaiming;
  final VoidCallback onScanTap;
  final VoidCallback onManualTap;
  final void Function(DeviceModel) onEditDevice;

  const _DevicesMainCard({
    required this.devicesAsync,
    required this.isClaiming,
    required this.onScanTap,
    required this.onManualTap,
    required this.onEditDevice,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(5, 0, 5, 2),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.deepGreen,
              AppColors.seaGreen,
              AppColors.blushPink,
              AppColors.lightPink,
            ],
            stops: [0.07, 0.19, 0.70, 0.93],
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Image.asset(
  'assets/logo_yellowfont.png',
  width:80,
  fit: BoxFit.cover,
),
            Container(
                margin: const EdgeInsets.only(top: 6),
                height: 1,
                color: AppColors.white),
            const SizedBox(height: 10),
            Text('DEVICES LIST',
                style: AppTextStyles.headline(24, AppColors.textPrimary,
                    letterSpacing: 2, weight: FontWeight.w700)),
            const SizedBox(height: 8),

            _DevicesTable(devicesAsync: devicesAsync, onEditDevice: onEditDevice),

            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: Container(height: 1, color: AppColors.white)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text('ADD DEVICES',
                      style: AppTextStyles.headline(16, AppColors.white,
                          letterSpacing: 2)),
                ),
                Expanded(child: Container(height: 1, color: AppColors.white)),
              ],
            ),
            const SizedBox(height: 20),

            // QR Slider
            Center(
              child: _QrSlider(
                isClaiming: isClaiming,
                onTap: onScanTap,
              ),
            ),

            const SizedBox(height: 12),

            // Manual entry button
            Center(
              child: GestureDetector(
                onTap: onManualTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.keyboard,
                          size: 14, color: Colors.white70),
                      const SizedBox(width: 8),
                      Text('ENTER DEVICE ID MANUALLY',
                          style: AppTextStyles.mono(10, Colors.white70,
                              letterSpacing: 1, weight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 25),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// DEVICES TABLE
// ══════════════════════════════════════════════════════════════════════════

class _DevicesTable extends StatelessWidget {
  final AsyncValue<List<DeviceModel>> devicesAsync;
  final void Function(DeviceModel) onEditDevice;

  const _DevicesTable({
    required this.devicesAsync,
    required this.onEditDevice,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 100, maxHeight: 220),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: devicesAsync.when(
        data: (devices) => devices.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('— no devices added yet —',
                      style: AppTextStyles.mono(10, AppColors.white,
                          letterSpacing: 1, weight: FontWeight.w500)),
                ),
              )
            : Column(
                children: [
                  _TableHeader(),
                  const Divider(color: Colors.white24, height: 1),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: devices.length,
                      separatorBuilder: (_, __) =>
                          const Divider(color: Colors.white24, height: 1),
                      itemBuilder: (_, i) => _DeviceRow(
                        device: devices[i],
                        onLongPress: () => onEditDevice(devices[i]),
                      ),
                    ),
                  ),
                ],
              ),
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(color: Colors.white),
          ),
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Could not load devices.$e',
                style: const TextStyle(color: Colors.redAccent),
                textAlign: TextAlign.center),
          ),
        ),
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text('Device Name',
                style: AppTextStyles.headline(12, AppColors.white,
                    letterSpacing: 1, weight: FontWeight.bold)),
          ),
          Expanded(
            child: Text('Location',
                style: AppTextStyles.headline(12, AppColors.white,
                    letterSpacing: 1, weight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  final DeviceModel device;
  final VoidCallback onLongPress;

  const _DeviceRow({
    required this.device,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(device.name,
                  style: AppTextStyles.mono(12, AppColors.white,
                      weight: FontWeight.w600)),
            ),
            Expanded(
              child: Text(
                device.location.isEmpty ? '—' : device.location,
                style: AppTextStyles.mono(12,
                    AppColors.white.withValues(alpha: 0.7)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// QR SLIDER
// ══════════════════════════════════════════════════════════════════════════

class _QrSlider extends StatefulWidget {
  final bool isClaiming;
  final VoidCallback onTap;

  const _QrSlider({required this.isClaiming, required this.onTap});

  @override
  State<_QrSlider> createState() => _QrSliderState();
}

class _QrSliderState extends State<_QrSlider> {
  double _dragX = 0;
  bool _triggered = false;

  static const double _trackW = 210;
  static const double _thumbW = 60;
  static const double _maxDrag = _trackW - _thumbW - 8;

  void _onDragUpdate(DragUpdateDetails d) {
    if (_triggered || widget.isClaiming) return;
    setState(() {
      _dragX = (_dragX + d.delta.dx).clamp(0, _maxDrag);
    });
  }

  void _onDragEnd(DragEndDetails d) {
    if (_triggered || widget.isClaiming) return;
    if (_dragX >= _maxDrag * 0.80) {
      setState(() => _triggered = true);
      widget.onTap();
    } else {
      setState(() => _dragX = 0);
    }
  }

  @override
  void didUpdateWidget(covariant _QrSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset when claim finishes (isClaiming goes true -> false)
    if (oldWidget.isClaiming && !widget.isClaiming) {
      setState(() {
        _dragX = 0;
        _triggered = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      width: _trackW,
      decoration: BoxDecoration(
        color: const Color(0xFF06231D),
        borderRadius: BorderRadius.circular(30),
      ),
      child: widget.isClaiming
          ? const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
              ),
            )
          : Stack(
              alignment: Alignment.centerLeft,
              children: [
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.center,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 64),
                      child: Opacity(
                        opacity: (1 - (_dragX / _maxDrag)).clamp(0.0, 1.0),
                        child: Text(
                          'SLIDE HERE TO SCAN QR',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.headline(
                            9, AppColors.white,
                            letterSpacing: 1, weight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Transform.translate(
                  offset: Offset(_dragX + 4, 0),
                  child: GestureDetector(
                    onHorizontalDragUpdate: _onDragUpdate,
                    onHorizontalDragEnd: _onDragEnd,
                    child: Container(
                      width: _thumbW,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _triggered
                            ? const Color(0xFFE4F27A).withValues(alpha: 0.6)
                            : const Color(0xFFE4F27A),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Icon(
                        _triggered
                            ? Icons.qr_code_scanner_rounded
                            : Icons.arrow_forward_ios_rounded,
                        color: AppColors.deepGreen,
                        size: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// QR SCANNER PAGE
// ══════════════════════════════════════════════════════════════════════════

class _QrScannerPage extends StatefulWidget {
  const _QrScannerPage();

  @override
  State<_QrScannerPage> createState() => _QrScannerPageState();
}

class _QrCorner extends StatelessWidget {
  final bool flipX;
  final bool flipY;
  const _QrCorner({this.flipX = false, this.flipY = false});

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scaleX: flipX ? -1 : 1,
      scaleY: flipY ? -1 : 1,
      child: SizedBox(
        width: 28,
        height: 28,
        child: CustomPaint(painter: _CornerPainter()),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE4F27A)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      const Offset(0, 0),
      Offset(0, size.height),
      paint,
    );
    canvas.drawLine(
      const Offset(0, 0),
      Offset(size.width, 0),
      paint,
    );
  }

  @override
  bool shouldRepaint(_) => false;
}

class _QrScannerPageState extends State<_QrScannerPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _hasScanned = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: AppColors.deepGreen,
        title: Text('Scan Device QR',
            style: AppTextStyles.mono(16, AppColors.textPrimary,
                weight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context, null),
        ),
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              if (_hasScanned) return;
              final barcode = capture.barcodes.firstOrNull;
              final value = barcode?.rawValue;
              if (value != null) {
                _hasScanned = true;
                Navigator.pop(context, value);
              }
            },
          ),
          Center(
            child: SizedBox(
              width: 220,
              height: 220,
              child: Stack(
                children: [
                  Positioned(top: 0, left: 0, child: _QrCorner()),
                  Positioned(top: 0, right: 0, child: _QrCorner(flipX: true)),
                  Positioned(bottom: 0, left: 0, child: _QrCorner(flipY: true)),
                  Positioned(
                      bottom: 0, right: 0, child: _QrCorner(flipX: true, flipY: true)),
                  Center(
                    child: Container(
                      height: 1.5,
                      width: 180,
                      color: const Color(0xFFE4F27A).withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: Text('Point camera at device QR code',
                  style: AppTextStyles.mono(13, Colors.white,
                      weight: FontWeight.w500)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

// ══════════════════════════════════════════════════════════════════════════
// NAV BAR
// ══════════════════════════════════════════════════════════════════════════

class GrowWiserNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool showAdmin;

  const GrowWiserNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.showAdmin = false,
  });

  @override
  Widget build(BuildContext context) {
    final items = _navItems(showAdmin);
    return Container(
      color: AppColors.black,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(items.length, (i) {
          return _NavCard(
            item: items[i],
            index: i,
            isSelected: currentIndex == i,
            onTap: () => onTap(i),
          );
        }),
      ),
    );
  }

  static List<_NavItem> _navItems(bool showAdmin) => [
        const _NavItem(
            number: '01', label: 'HOME', imagePath: 'assets/home_black.png'),
        if (!showAdmin) ...[
          const _NavItem(
              number: '02',
              label: 'COMMAND',
              imagePath: 'assets/command_black.png'),
          const _NavItem(
              number: '03',
              label: 'DEVICES',
              imagePath: 'assets/tools.png'),
          const _NavItem(
              number: '04',
              label: 'LOG OUT',
              imagePath: 'assets/logout_black.png'),
        ] else ...[
          const _NavItem(
              number: '02',
              label: 'LOG OUT',
              imagePath: 'assets/logout_black.png'),
        ],
      ];
}

class _NavItem {
  final String number;
  final String label;
  final String imagePath;
  const _NavItem(
      {required this.number, required this.label, required this.imagePath});
}

class _NavCard extends StatelessWidget {
  final _NavItem item;
  final int index;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavCard({
    required this.item,
    required this.index,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        width: 60,
        height: 90,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(40),
            topRight: Radius.circular(40),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? AppColors.black : Colors.white,
                border: Border.all(
                  color: isSelected ? Colors.white : AppColors.black,
                  width: 0.5,
                ),
              ),
              padding: const EdgeInsets.all(8),
              child: Image.asset(item.imagePath, fit: BoxFit.contain),
            ),
            const SizedBox(height: 3),
            Text(item.number,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: Colors.black,
                    fontFamily: AppTextStyles.clashDisplay)),
            Text(item.label,
                style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: AppColors.black,
                    fontFamily: AppTextStyles.satoshi)),
            Container(
              height: 2,
              width: 48,
              color: AppColors.black,
              margin: const EdgeInsets.symmetric(vertical: 2),
            ),
          ],
        ),
      ),
    );
  }
}
