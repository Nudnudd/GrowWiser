import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../services/backend_service.dart';
import '../providers/backend_providers.dart';
import '../utils/irrigation_logic.dart';

// ══════════════════════════════════════════════════════════════════════════
// COMMAND PAGE
// ══════════════════════════════════════════════════════════════════════════

class CommandPage extends ConsumerStatefulWidget {
  const CommandPage({super.key});

  @override
  ConsumerState<CommandPage> createState() => _CommandPageState();
}

class _CommandPageState extends ConsumerState<CommandPage> {
  final int _currentIndex = 1;
  bool _isAdmin = false;
  String _selectedZone = '';
  bool _isCommandLoading = false;
  String? _activeDeviceId;

  @override
  void initState() {
    super.initState();
    _loadAdminStatus();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDevices());
  }

  Future<void> _loadAdminStatus() async {
    final admin = await BackendService().isAdmin();
    if (mounted) setState(() => _isAdmin = admin);
  }

 Future<void> _loadDevices() async {
  final devices = await ref.read(userDevicesProvider.future);
if (!mounted) return;
setState(() {
  _activeDeviceId = devices.firstOrNull?.deviceId ?? 'no-device';
  _selectedZone = devices.firstOrNull?.name ?? '—';
});
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

  Future<void> _handleWaterNow() async {
  if (_activeDeviceId == null || _activeDeviceId == 'no-device') return;
    if (!BackendService().mqttConnected) {
    try {
      await BackendService().connectMqtt(
        brokerHost: 'broker.hivemq.com', // ← see hardcoded data below
        port: 1883,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Broker unreachable', style: AppTextStyles.mono(12, Colors.white)),
          backgroundColor: Colors.redAccent),
        );
      }
      return;
    }
  }
    setState(() => _isCommandLoading = true);
    try {
      await BackendService().sendPumpCommand(_activeDeviceId!, true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$_selectedZone irrigation started.',
              style: AppTextStyles.mono(12, Colors.white),
            ),
            backgroundColor: AppColors.deepGreen,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Command failed: $e',
                style: AppTextStyles.mono(12, Colors.white)),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCommandLoading = false);
    }
  }

  void _onZoneSelected(String zoneName) {
    // Find device ID by name
    final devicesAsync = ref.read(userDevicesProvider).valueOrNull ?? [];
    final matched = devicesAsync.where((d) => d.name == zoneName).firstOrNull;
    if (matched != null) {
      setState(() {
        _selectedZone = zoneName;
        _activeDeviceId = matched.deviceId;
      });
    }
  }

  Future<void> _onRefresh() async {
    if (_activeDeviceId != null) {
      ref.invalidate(sensorDataProvider(_activeDeviceId!));
    }
    await Future.delayed(const Duration(milliseconds: 800));
  }

  @override
  Widget build(BuildContext context) {
    final configAsync = ref.watch(deviceConfigProvider(_activeDeviceId ?? 'no-device'));
final sensorAsync = ref.watch(sensorDataProvider(_activeDeviceId ?? 'no-device'));
final lastWateredAsync = ref.watch(lastWateredProvider(_activeDeviceId ?? 'no-device'));
    return Scaffold(
      backgroundColor: AppColors.black,
      bottomNavigationBar: GrowWiserNavBar(
        currentIndex: _currentIndex,
        onTap: _onNavTap,
        showAdmin: _isAdmin,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _onRefresh,
          color: const Color(0xFFE4F27A),
          backgroundColor: const Color(0xFF111111),
          displacement: 20,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _TopRow(),
                    const _SectionTitle(),
                      configAsync.when(
                        data: (device) => sensorAsync.when(
                          data: (sensorData) {
                            final mode = IrrigationLogic.evaluate(
                              moisture: sensorData.moisture,
                              lowerThreshold: device.moistureThreshold,
                              upperThreshold: device.moistureUpperLimit,
                            );
                            return Column(
                              children: [
                                _ModeTabs(mode: mode),
                                _CommandCard(
                                  moisture: sensorData.moisture,
                                  irrigationMode: mode,
                                  selectedZone: _selectedZone,
                                  isCommandLoading: _isCommandLoading,
                                  onWaterNow: _handleWaterNow,
                                  onZoneSelected: _onZoneSelected,
                                  lastWateredAsync: lastWateredAsync,
                                ),
                                const _SlideToRefreshHint(),
                              ],
                            );
                          },
                          loading: () => const SizedBox(
                            height: 360,
                            child: Center(
                              child: CircularProgressIndicator(
                                  color: Color(0xFFE4F27A)),
                            ),
                          ),
                          error: (e, _) => const SizedBox(
                            height: 360,
                            child: Center(
                              child: Text('Failed to load sensor data.\n\$e',
                                  style:
                                       TextStyle(color: Colors.redAccent),
                                  textAlign: TextAlign.center),
                            ),
                          ),
                        ),
                        loading: () => const SizedBox(
                          height: 360,
                          child: Center(
                            child: CircularProgressIndicator(
                                color: Color(0xFFE4F27A)),
                          ),
                        ),
                        error: (e, _) => const SizedBox(
                          height: 360,
                          child: Center(
                            child: Text('Failed to load config.\n\$e',
                                style:
                                    TextStyle(color: Colors.redAccent),
                                textAlign: TextAlign.center),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// TOP ROW
// ══════════════════════════════════════════════════════════════════════════

class _TopRow extends StatelessWidget {
  const _TopRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const _OrbWidget(mode: null),
          const Spacer(),
        Column(
  crossAxisAlignment: CrossAxisAlignment.end,
  children: [
    Builder(builder: (context) {
      final now = DateTime.now();
      final days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
      final months = ['JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE', 
                      'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER'];
      final dayName = days[now.weekday - 1];
      final monthName = months[now.month - 1];
      return Text(
        '$dayName, ${now.day} $monthName',
        style: AppTextStyles.mono(
          13,
          AppColors.textPrimary.withValues(alpha: 0.6),
          letterSpacing: 2,
          weight: FontWeight.w500,
        ),
      );
    }),
    Builder(builder: (context) {
      final now = DateTime.now();
      final hour = now.hour.toString().padLeft(2, '0');
      final minute = now.minute.toString().padLeft(2, '0');
      return Text(
        '$hour:$minute',
        style: AppTextStyles.headline(
          36,
          AppColors.textPrimary,
          letterSpacing: 1,
          weight: FontWeight.w900,
        ),
      );
    }),
  ],
),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// ORB WIDGET
// ══════════════════════════════════════════════════════════════════════════

class _OrbWidget extends StatelessWidget {
  final IrrigationMode? mode;
  const _OrbWidget({this.mode});

  List<Color> get _gradientColors {
    switch (mode) {
      case IrrigationMode.manualUnlocked:
        return const [
          Color(0xFFF5FFB0),
          Color(0xFFC8E030),
          Color(0xFF7A9A00),
          Color(0xFF3A5000),
        ];
      case IrrigationMode.blocked:
        return const [
          Color(0xFFFF9999),
          Color(0xFFCC3333),
          Color(0xFF661111),
          Color(0xFF2A0000),
        ];
      case IrrigationMode.autoIrrigate:
      default:
        return const [
          Color(0xFFA8EDBE),
          Color(0xFF1B6B3A),
          Color(0xFF06200F),
        ];
    }
  }

  Color get _ringColor {
    switch (mode) {
      case IrrigationMode.manualUnlocked:
        return const Color(0xFFE4F27A).withValues(alpha: 0.6);
      case IrrigationMode.blocked:
        return const Color(0xFFFF5050).withValues(alpha: 0.35);
      default:
        return const Color(0xFFE4F27A).withValues(alpha: 0.35);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _ringColor, width: 1.5),
      ),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: const Alignment(-0.3, -0.3),
            radius: 0.85,
            colors: _gradientColors,
          ),
        ),
        child: Align(
          alignment: const Alignment(-0.1, -0.25),
          child: Container(
            width: 28,
            height: 20,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: Colors.white.withValues(alpha: 0.18),
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// SECTION TITLE
// ══════════════════════════════════════════════════════════════════════════

class _SectionTitle extends StatelessWidget {
  const _SectionTitle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        children: [
          Text(
            'COMMAND',
            style: AppTextStyles.headline(
              24,
              AppColors.textPrimary,
              letterSpacing: 3,
              weight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(top: 4),
              height: 2,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// MODE TABS
// ══════════════════════════════════════════════════════════════════════════

class _ModeTabs extends StatelessWidget {
  final IrrigationMode mode;
  const _ModeTabs({required this.mode});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Row(
        children: [
          _ModeTab(
            label: 'WET',
            isActive: mode == IrrigationMode.blocked,
            activeColor: const Color(0xFFFF8080),
            activeBg: const Color(0x26FF5050),
            activeBorder: const Color(0xB3FF5050),
            inactiveColor: const Color(0x99FF7878),
            inactiveBg: const Color(0x14FF5050),
            inactiveBorder: const Color(0x40FF5050),
          ),
          const SizedBox(width: 8),
          _ModeTab(
            label: 'MANUAL',
            isActive: mode == IrrigationMode.manualUnlocked,
            activeColor: const Color(0xFFE4F27A),
            activeBg: const Color(0x33E4F27A),
            activeBorder: const Color(0xFFE4F27A),
            inactiveColor: const Color(0xFFE4F27A),
            inactiveBg: const Color(0x26E4F27A),
            inactiveBorder: const Color(0x80E4F27A),
          ),
          const SizedBox(width: 8),
          _ModeTab(
            label: 'AUTO',
            isActive: mode == IrrigationMode.autoIrrigate,
            activeColor: const Color(0xFF96F0A0),
            activeBg: const Color(0x801A4A28),
            activeBorder: const Color(0x9950B464),
            inactiveColor: const Color(0x9978DC8C),
            inactiveBg: const Color(0x591A4A28),
            inactiveBorder: const Color(0x4050B464),
          ),
        ],
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  final String label;
  final bool isActive;
  final Color activeColor, activeBg, activeBorder;
  final Color inactiveColor, inactiveBg, inactiveBorder;

  const _ModeTab({
    required this.label,
    required this.isActive,
    required this.activeColor,
    required this.activeBg,
    required this.activeBorder,
    required this.inactiveColor,
    required this.inactiveBg,
    required this.inactiveBorder,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(
          color: isActive ? activeBg : inactiveBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive ? activeBorder : inactiveBorder,
            width: isActive ? 2 : 1,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: AppTextStyles.mono(
              9,
              isActive ? activeColor : inactiveColor,
              letterSpacing: 1.3,
              weight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// COMMAND CARD
// ══════════════════════════════════════════════════════════════════════════

class _CommandCard extends StatelessWidget {
  final double moisture;
  final IrrigationMode irrigationMode;
  final String selectedZone;
  final bool isCommandLoading;
  final VoidCallback onWaterNow;
  final ValueChanged<String> onZoneSelected;
  final AsyncValue<DateTime?>? lastWateredAsync;

  const _CommandCard({
    required this.moisture,
    required this.irrigationMode,
    required this.selectedZone,
    required this.isCommandLoading,
    required this.onWaterNow,
    required this.onZoneSelected,
    this.lastWateredAsync,
  });

  List<Color> get _cardGradient {
    switch (irrigationMode) {
      case IrrigationMode.manualUnlocked:
        return const [
          Color(0xFF3A5200),
          Color(0xFF5A7800),
          Color(0xFF8AB000),
          Color(0xFFD4E060),
          Color(0xFFF0E890),
          Color(0xFFFAFAD0),
        ];
      case IrrigationMode.blocked:
        return const [
          Color(0xFF4A1010),
          Color(0xFF6B1515),
          Color(0xFF9B2020),
          Color(0xFFD06060),
          Color(0xFFF0A0A0),
          Color(0xFFFFD0D0),
        ];
      case IrrigationMode.autoIrrigate:
      default:
        return const [
          Color(0xFF1A4A28),
          Color(0xFF0F3320),
          Color(0xFF2A6040),
          Color(0xFFC8A0A0),
          Color(0xFFF0C0C0),
          Color(0xFFF8D8D8),
        ];
    }
  }

  Color get _chipTextColor {
    switch (irrigationMode) {
      case IrrigationMode.blocked:
        return const Color(0xFFFF8080);
      case IrrigationMode.manualUnlocked:
        return const Color(0xFF0A0A0A);
      default:
        return const Color(0xFFE4F27A);
    }
  }

  Color get _chipBg {
    switch (irrigationMode) {
      case IrrigationMode.blocked:
        return const Color(0x26FF5050);
      case IrrigationMode.manualUnlocked:
        return const Color(0x33000000);
      default:
        return const Color(0x1FE4F27A);
    }
  }

  Color get _chipBorder {
    switch (irrigationMode) {
      case IrrigationMode.blocked:
        return const Color(0x40FF5050);
      case IrrigationMode.manualUnlocked:
        return const Color(0x66000000);
      default:
        return const Color(0x4DE4F27A);
    }
  }

  Color get _cornerColor {
    switch (irrigationMode) {
      case IrrigationMode.blocked:
        return const Color.fromARGB(236, 181, 7, 7);
      case IrrigationMode.manualUnlocked:
        return const Color.fromARGB(255, 0, 0, 0);
      default:
        return const Color.fromARGB(255, 228, 242, 122);
    }
  }

  Color get _tagColor {
    switch (irrigationMode) {
      case IrrigationMode.blocked:
        return const Color.fromARGB(236, 181, 7, 7);
      case IrrigationMode.manualUnlocked:
        return const Color.fromARGB(221, 0, 0, 0);
      default:
        return const Color.fromARGB(255, 228, 242, 122);
    }
  }

  bool get _isDark => irrigationMode == IrrigationMode.manualUnlocked;

  String _formatLastWatered(DateTime? dt) {
    if (dt == null) return 'Last watered: —';
    final hour = dt.hour;
    final suffix = hour >= 12 ? 'P.M' : 'A.M';
    final display = hour % 12 == 0 ? 12 : hour % 12;
    return 'Last watered: $display $suffix';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _cardGradient,
              stops: const [0.0, 0.1, 0.3, 0.6, 0.82, 1.0],
            ),
          ),
          child: Stack(
            children: [
              _CornerMark(corner: Alignment.topLeft, color: _cornerColor),
              _CornerMark(corner: Alignment.topRight, color: _cornerColor),
              _CornerMark(corner: Alignment.bottomLeft, color: _cornerColor),
              _CornerMark(corner: Alignment.bottomRight, color: _cornerColor),

              Positioned(
                  top: 11,
                  left: 13,
                  child: Text(selectedZone.toUpperCase(),
                      style: AppTextStyles.mono(10, _tagColor, weight: FontWeight.w600))),
              Positioned(
                  top: 11,
                  right: 13,
                  child: Text('LIVE',
                      style: AppTextStyles.mono(10, _tagColor, weight: FontWeight.w600))),
              Positioned(
                  bottom: 10,
                  left: 13,
                  child: Text('SENSOR',
                      style: AppTextStyles.mono(10, _tagColor, weight: FontWeight.w600))),
              Positioned(
                bottom: 10,
                right: 13,
                child: Text(
                  irrigationMode == IrrigationMode.autoIrrigate ? 'AUTO:ON' : 'AUTO:OFF',
                  style: AppTextStyles.mono(12, _tagColor, weight: FontWeight.w900),
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),

                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _chipBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _chipBorder),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 82, vertical: 0),
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _chipTextColor,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'SOIL MOISTURE',
                                  style: AppTextStyles.mono(12, _chipTextColor,
                                      letterSpacing: 2, weight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),

                    Text(
                      '${moisture.toStringAsFixed(0)}%',
                      style: AppTextStyles.headline(
                        64,
                        _isDark ? const Color(0xD90A0A0A) : Colors.white,
                        weight: FontWeight.w900,
                        letterSpacing: -1,
                      ),
                    ),

                    if (lastWateredAsync != null)
                      lastWateredAsync!.when(
                        data: (dt) => Text(
                          _formatLastWatered(dt),
                          style: AppTextStyles.body(
                            10,
                            (_isDark ? const Color(0xFF0A0A0A) : Colors.white)
                                .withValues(alpha: 0.85),
                            weight: FontWeight.w800,
                          ),
                        ),
                        loading: () => Text(
                          'Last watered: ...',
                          style: AppTextStyles.body(
                            10,
                            (_isDark ? const Color(0xFF0A0A0A) : Colors.white)
                                .withValues(alpha: 0.85),
                            weight: FontWeight.w800,
                          ),
                        ),
                        error: (_, __) => Text(
                          'Last watered: —',
                          style: AppTextStyles.body(
                            10,
                            (_isDark ? const Color(0xFF0A0A0A) : Colors.white)
                                .withValues(alpha: 0.85),
                            weight: FontWeight.w800,
                          ),
                        ),
                      )
                    else
                      Text(
                        'Last watered: —',
                        style: AppTextStyles.body(
                          10,
                          (_isDark ? const Color(0xFF0A0A0A) : Colors.white)
                              .withValues(alpha: 0.85),
                          weight: FontWeight.w800,
                        ),
                      ),

                    const SizedBox(height: 10),

                    Container(
                        height: 3,
                        color: (_isDark ? const Color(0xFF0A0A0A) : Colors.white)
                            .withValues(alpha: 0.8)),
                    const SizedBox(height: 5),
                    Container(
                        height: 3,
                        color: (_isDark ? const Color(0xFF0A0A0A) : Colors.white)
                            .withValues(alpha: 0.4)),

                    const SizedBox(height: 10),

                    _ControlsGlass(
                      irrigationMode: irrigationMode,
                      selectedZone: selectedZone,
                      isCommandLoading: isCommandLoading,
                      onWaterNow: onWaterNow,
                      onZoneSelected: onZoneSelected,
                      isDark: _isDark,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// CORNER MARK
// ══════════════════════════════════════════════════════════════════════════

class _CornerMark extends StatelessWidget {
  final Alignment corner;
  final Color color;
  const _CornerMark({required this.corner, required this.color});

  @override
  Widget build(BuildContext context) {
    final isLeft = corner == Alignment.topLeft || corner == Alignment.bottomLeft;
    final isTop = corner == Alignment.topLeft || corner == Alignment.topRight;

    return Positioned(
      top: isTop ? 8 : null,
      bottom: isTop ? null : 8,
      left: isLeft ? 8 : null,
      right: isLeft ? null : 8,
      child: SizedBox(
        width: 15,
        height: 15,
        child: CustomPaint(
          painter: _CornerPainter(color: color, isLeft: isLeft, isTop: isTop),
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final Color color;
  final bool isLeft, isTop;
  const _CornerPainter({required this.color, required this.isLeft, required this.isTop});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path();
    if (isLeft && isTop) {
      path.moveTo(0, size.height);
      path.lineTo(0, 0);
      path.lineTo(size.width, 0);
    } else if (!isLeft && isTop) {
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width, size.height);
    } else if (isLeft && !isTop) {
      path.moveTo(0, 0);
      path.lineTo(0, size.height);
      path.lineTo(size.width, size.height);
    } else {
      path.moveTo(size.width, 0);
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CornerPainter old) => old.color != color;
}

// ══════════════════════════════════════════════════════════════════════════
// GLASS CONTROLS PANEL
// ══════════════════════════════════════════════════════════════════════════

class _ControlsGlass extends ConsumerWidget {
  final IrrigationMode irrigationMode;
  final String selectedZone;
  final bool isCommandLoading;
  final VoidCallback onWaterNow;
  final ValueChanged<String> onZoneSelected;
  final bool isDark;

  const _ControlsGlass({
    required this.irrigationMode,
    required this.selectedZone,
    required this.isCommandLoading,
    required this.onWaterNow,
    required this.onZoneSelected,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: isDark
              ? const Color.fromARGB(255, 127, 40, 40).withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark
                ? Colors.black.withValues(alpha: 0.28)
                : Colors.white.withValues(alpha: 0.22),
          ),
        ),
        child: Column(
          children: [
            _ZoneSelector(
              selectedZone: selectedZone,
              irrigationMode: irrigationMode,
              isDark: isDark,
              onTap: () => _showZoneSheet(context, ref, selectedZone, onZoneSelected),
            ),
            const SizedBox(height: 8),
            isCommandLoading
                ? const SizedBox(
                    height: 46,
                    child: Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFFE4F27A), strokeWidth: 2),
                    ),
                  )
                : _ActionButton(
                    irrigationMode: irrigationMode,
                    onWaterNow: onWaterNow,
                  ),
            if (irrigationMode == IrrigationMode.autoIrrigate) ...[
              const SizedBox(height: 8),
              const _ThresholdChips(),
            ],
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// ZONE SELECTOR
// ══════════════════════════════════════════════════════════════════════════

class _ZoneSelector extends StatelessWidget {
  final String selectedZone;
  final IrrigationMode irrigationMode;
  final bool isDark;
  final VoidCallback onTap;

  const _ZoneSelector({
    required this.selectedZone,
    required this.irrigationMode,
    required this.isDark,
    required this.onTap,
  });

  Color get _dotColor {
    switch (irrigationMode) {
      case IrrigationMode.blocked:
        return const Color(0xFFFF6060);
      case IrrigationMode.manualUnlocked:
        return const Color(0xFF0A0A0A);
      default:
        return const Color(0xFFE4F27A);
    }
  }

  Color get _valueColor {
    switch (irrigationMode) {
      case IrrigationMode.blocked:
        return const Color(0xFFFF8080);
      case IrrigationMode.manualUnlocked:
        return const Color(0xD30A0A0A);
      default:
        return const Color(0xFFE4F27A);
    }
  }

  Color get _borderColor {
    switch (irrigationMode) {
      case IrrigationMode.blocked:
        return const Color(0x40FF5050);
      case IrrigationMode.manualUnlocked:
        return const Color(0x66000000);
      default:
        return const Color(0x38E4F27A);
    }
  }

  Color get _scanColor {
    switch (irrigationMode) {
      case IrrigationMode.blocked:
        return const Color(0x73FF5050);
      case IrrigationMode.manualUnlocked:
        return const Color(0x33000000);
      default:
        return const Color(0x73E4F27A);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.black.withValues(alpha: 0.38)
              : const Color(0xFF0A0A0A).withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _borderColor),
        ),
        child: Stack(
          children: [
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: _dotColor),
                ),
                const SizedBox(width: 8),
                Text(
                  'ZONE',
                  style: AppTextStyles.mono(
                    9,
                    isDark
                        ? Colors.black.withValues(alpha: 0.8)
                        : const Color(0xFF888888),
                    letterSpacing: 2.5,
                    weight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '${selectedZone.toUpperCase()} ▼',
                  style: AppTextStyles.mono(
                    12,
                    _valueColor,
                    letterSpacing: 2,
                    weight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            Positioned(
              bottom: -11,
              left: 0,
              right: 0,
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      _scanColor,
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// ACTION BUTTON
// ══════════════════════════════════════════════════════════════════════════

class _ActionButton extends StatelessWidget {
  final IrrigationMode irrigationMode;
  final VoidCallback onWaterNow;

  const _ActionButton({
    required this.irrigationMode,
    required this.onWaterNow,
  });

  bool get _isEnabled => irrigationMode == IrrigationMode.manualUnlocked;

  String get _label {
    switch (irrigationMode) {
      case IrrigationMode.autoIrrigate:
        return 'AUTO\nIRRIGATING';
      case IrrigationMode.blocked:
        return 'SOIL TOO WET';
      case IrrigationMode.manualUnlocked:
        return 'WATER NOW ◎';
    }
  }

  List<Color> get _gradientColors {
    switch (irrigationMode) {
      case IrrigationMode.manualUnlocked:
        return const [Color(0xFFE4F27A), Color(0xFFC8D840)];
      case IrrigationMode.autoIrrigate:
        return const [Color(0xFF1A4A28), Color(0xFF0F6E3A)];
      case IrrigationMode.blocked:
        return const [Color(0xFF5A1010), Color(0xFF3D0A0A)];
    }
  }

  Color get _borderColor {
    switch (irrigationMode) {
      case IrrigationMode.manualUnlocked:
        return Colors.transparent;
      case IrrigationMode.autoIrrigate:
        return const Color(0x59E4F27A);
      case IrrigationMode.blocked:
        return const Color(0x80FF5050);
    }
  }

  Color get _labelColor {
    switch (irrigationMode) {
      case IrrigationMode.manualUnlocked:
        return const Color(0xFF0A0A0A);
      case IrrigationMode.autoIrrigate:
        return const Color(0xF2E4F27A);
      case IrrigationMode.blocked:
        return const Color(0xF9FF9696);
    }
  }

  Color get _dotColor {
    switch (irrigationMode) {
      case IrrigationMode.manualUnlocked:
        return const Color(0xFF0A0A0A);
      case IrrigationMode.autoIrrigate:
        return const Color(0xFFE4F27A);
      case IrrigationMode.blocked:
        return const Color(0xFFFF6060);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _isEnabled ? onWaterNow : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _gradientColors,
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _borderColor, width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _PulseDot(
              color: _dotColor,
              animate: irrigationMode != IrrigationMode.manualUnlocked,
              slow: irrigationMode == IrrigationMode.blocked,
            ),
            const SizedBox(width: 8),
            Text(
              _label,
              textAlign: TextAlign.center,
              style: AppTextStyles.headline(
                10,
                _labelColor,
                letterSpacing: 2.5,
                weight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// PULSE DOT
// ══════════════════════════════════════════════════════════════════════════

class _PulseDot extends StatefulWidget {
  final Color color;
  final bool animate;
  final bool slow;
  const _PulseDot({required this.color, this.animate = false, this.slow = false});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: widget.slow
          ? const Duration(milliseconds: 2200)
          : const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 1.0, end: 0.35).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animate) {
      return Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
      );
    }
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Opacity(
        opacity: _anim.value,
        child: Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// THRESHOLD CHIPS
// ══════════════════════════════════════════════════════════════════════════

class _ThresholdChips extends StatelessWidget {
  const _ThresholdChips();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFFE4F27A).withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              children: [
                Text(
                  'LOW',
                  style: AppTextStyles.mono(
                    9,
                    const Color(0xFFE4F27A).withValues(alpha: 0.80),
                    weight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '40%',
                  style: AppTextStyles.headline(
                    15,
                    const Color(0xFFE4F27A),
                    weight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFFE4F27A).withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              children: [
                Text(
                  'HIGH',
                  style: AppTextStyles.mono(
                    9,
                    const Color(0xFFE4F27A).withValues(alpha: 0.80),
                    weight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '80%',
                  style: AppTextStyles.headline(
                    15,
                    const Color(0xFFE4F27A),
                    weight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// SLIDE TO REFRESH HINT
// ══════════════════════════════════════════════════════════════════════════

class _SlideToRefreshHint extends StatefulWidget {
  const _SlideToRefreshHint();

  @override
  State<_SlideToRefreshHint> createState() => _SlideToRefreshHintState();
}

class _SlideToRefreshHintState extends State<_SlideToRefreshHint>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _bob;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _bob = Tween<double>(begin: 0, end: 4).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Column(
        children: [
          AnimatedBuilder(
            animation: _bob,
            builder: (_, child) => Transform.translate(
              offset: Offset(0, _bob.value),
              child: child,
            ),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                ),
              ),
              child: const Center(
                child: Text(
                  '↓',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0x66FFFFFF),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'SLIDE TO REFRESH',
            style: AppTextStyles.mono(
              12,
              Colors.white.withValues(alpha: 0.70),
              letterSpacing: 1.8,
            ),
          ),
        ],
      ),
    );
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
        const _NavItem(number: '01', label: 'HOME', imagePath: 'assets/home_black.png'),
        if (!showAdmin) ...[
          const _NavItem(number: '02', label: 'COMMAND', imagePath: 'assets/command.png'),
          const _NavItem(number: '03', label: 'DEVICES', imagePath: 'assets/tools_black.png'),
          const _NavItem(number: '04', label: 'LOG OUT', imagePath: 'assets/logout_black.png'),
        ] else ...[
          const _NavItem(number: '02', label: 'LOG OUT', imagePath: 'assets/logout_black.png'),
        ],
      ];
}

class _NavItem {
  final String number;
  final String label;
  final String imagePath;
  const _NavItem({required this.number, required this.label, required this.imagePath});
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

// ══════════════════════════════════════════════════════════════════════════
// ZONE SELECTOR SHEET
// ══════════════════════════════════════════════════════════════════════════

void _showZoneSheet(
  BuildContext context,
  WidgetRef ref,
  String currentZone,
  ValueChanged<String> onZoneSelected,
) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _ZoneSheetContent(
      currentZone: currentZone,
      onZoneSelected: onZoneSelected,
    ),
  );
}

class _ZoneSheetContent extends ConsumerStatefulWidget {
  final String currentZone;
  final ValueChanged<String> onZoneSelected;

  const _ZoneSheetContent({
    required this.currentZone,
    required this.onZoneSelected,
  });

  @override
  ConsumerState<_ZoneSheetContent> createState() => _ZoneSheetContentState();
}

class _ZoneSheetContentState extends ConsumerState<_ZoneSheetContent> {
  int? _expandedIndex;

  @override
  Widget build(BuildContext context) {
    final allDevicesAsync = ref.watch(allDevicesSensorProvider);

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF141414),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              Text(
                'SELECT ZONE',
                style: AppTextStyles.headline(
                  19,
                  Colors.white.withOpacity(0.94),
                  letterSpacing: 1,
                  weight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Tap a zone to water it, or expand for details',
                style: AppTextStyles.mono(
                  11,
                  Colors.white.withOpacity(0.35),
                  weight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 18),
              allDevicesAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFFE4F27A),
                      strokeWidth: 2,
                    ),
                  ),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  child: Center(
                    child: Text(
                      'Failed to load zones',
                      style: AppTextStyles.mono(12, Colors.redAccent),
                    ),
                  ),
                ),
                data: (devices) {
                  if (devices.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 30),
                      child: Center(
                        child: Text(
                          'No devices available',
                          style: AppTextStyles.mono(12, Colors.white.withOpacity(0.5)),
                        ),
                      ),
                    );
                  }
                  return Column(
                    children: List.generate(devices.length, (i) {
                      final device = devices[i].$1;
                      final sensor = devices[i].$2;
                      final label = device.name;
                      final isExpanded = _expandedIndex == i;

                      return _ZoneTile(
                        label: label,
                        moisture: sensor?.moisture,
                        temperature: sensor?.temperature,
                        lastUpdated: sensor?.lastUpdatedDateTime,
                        isAvailable: true,
                        isExpanded: isExpanded,
                        onTap: () {
                          widget.onZoneSelected(label);
                          Navigator.pop(context);
                        },
                        onExpandToggle: () => setState(() {
                          _expandedIndex = isExpanded ? null : i;
                        }),
                      );
                    }),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// ZONE TILE
// ══════════════════════════════════════════════════════════════════════════

class _ZoneTile extends StatelessWidget {
  final String label;
  final double? moisture;
  final double? temperature;
  final DateTime? lastUpdated;
  final bool isAvailable;
  final bool isExpanded;
  final VoidCallback? onTap;
  final VoidCallback? onExpandToggle;

  const _ZoneTile({
    required this.label,
    required this.moisture,
    required this.temperature,
    required this.lastUpdated,
    required this.isAvailable,
    required this.isExpanded,
    required this.onTap,
    required this.onExpandToggle,
  });

  String get _statusLabel {
    if (!isAvailable || moisture == null) return 'N/A';
    if (moisture! < 50) return 'LOW';
    if (moisture! > 80) return 'HIGH';
    return 'GOOD';
  }

  Color get _statusColor {
    if (!isAvailable || moisture == null) return Colors.white24;
    if (moisture! < 50) return const Color(0xFFFFB040);
    if (moisture! > 80) return const Color(0xFFFF6B6B);
    return const Color(0xFFE4F27A);
  }

  String _timeAgo(DateTime? time) {
    if (time == null) return '—';
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    if (!isAvailable) {
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF181812),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.04)),
        ),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.18),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'N/A',
              style: AppTextStyles.body(
                13,
                Colors.white.withOpacity(0.28),
                weight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE4F27A).withOpacity(0.12)),
        gradient: const RadialGradient(
          center: Alignment(-0.4, -1.0),
          radius: 2,
          colors: [
            Color(0xFF3A4218),
            Color(0xFF1E2410),
            Color(0xFF141414),
          ],
          stops: [0.0, 0.45, 0.8],
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            style: AppTextStyles.headline(
                              25,
                              Colors.white.withOpacity(0.95),
                              letterSpacing: -0.5,
                              weight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _statusColor.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _statusColor,
                                  boxShadow: [
                                    BoxShadow(
                                      color: _statusColor.withOpacity(0.6),
                                      blurRadius: 6,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                _statusLabel,
                                style: AppTextStyles.mono(
                                  9,
                                  _statusColor,
                                  letterSpacing: 1,
                                  weight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    GestureDetector(
                      onTap: onExpandToggle,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Row(
                          children: [
                            AnimatedRotation(
                              turns: isExpanded ? 0.5 : 0,
                              duration: const Duration(milliseconds: 200),
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFFE4F27A).withOpacity(0.1),
                                ),
                                child: const Icon(
                                  Icons.keyboard_arrow_down,
                                  size: 13,
                                  color: Color(0xFFE4F27A),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isExpanded ? 'Tap to collapse' : 'Tap to expand details',
                              style: AppTextStyles.mono(
                                10,
                                const Color(0xFFE4F27A).withOpacity(0.55),
                                letterSpacing: 0.5,
                                weight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: isExpanded
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        children: [
                          Container(
                            height: 1,
                            color: Colors.white.withOpacity(0.08),
                            margin: const EdgeInsets.only(bottom: 12),
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: _StatChip(
                                  label: 'MOISTURE',
                                  value: moisture != null
                                      ? '${moisture!.toStringAsFixed(0)}%'
                                      : '--',
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _StatChip(
                                  label: 'TEMP',
                                  value: temperature != null
                                      ? '${temperature!.toStringAsFixed(1)}°C'
                                      : '--',
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _StatChip(
                                  label: 'UPDATED',
                                  value: _timeAgo(lastUpdated),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity, height: 0),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE4F27A).withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyles.mono(
              8,
              Colors.white.withOpacity(0.35),
              letterSpacing: 1,
              weight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: AppTextStyles.body(
              13,
              const Color(0xFFE4F27A),
              weight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeoutLoader extends StatefulWidget {
  const _TimeoutLoader();

  @override
  State<_TimeoutLoader> createState() => _TimeoutLoaderState();
}

class _TimeoutLoaderState extends State<_TimeoutLoader> {
  bool _showRetry = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted) setState(() => _showRetry = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_showRetry) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off, color: Colors.white54, size: 40),
          const SizedBox(height: 12),
          Text('No connection', style: AppTextStyles.mono(14, Colors.white54)),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              // Retry
              (context as Element).markNeedsBuild();
            },
            child: Text('RETRY', style: AppTextStyles.mono(12, const Color(0xFFE4F27A))),
          ),
        ],
      );
    }
    return const CircularProgressIndicator(color: Color(0xFFE4F27A));
  }
}
