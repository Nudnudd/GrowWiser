import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/backend_service.dart';
import 'dart:math' as math;
import '../theme/app_theme.dart';
import '../providers/backend_providers.dart';
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../models/device.dart';
import '../models/sensor_data.dart';

class DashboardPage extends ConsumerStatefulWidget { 
  // CHANGE: StatefulWidget → ConsumerStatefulWidget
  // Why: We need `ref` to watch sensorDataProvider and
  //      userDevicesProvider inside this page's state class.
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  final int _currentIndex = 0;

  // CHANGE: _isAdmin is no longer a hardcoded final bool.
  // Why: We now derive it from authStateProvider. We keep a local
  //      bool here that gets set after we check Firestore.
  //      For now it defaults false until isAdmin() resolves.
  bool _isAdmin = false;

  // NEW: we store the active deviceId here once we load the user's devices.
  // Why: watchSensorData() needs a deviceId. We grab the first device
  //      the user owns and use that as the active device for now.
  String? _activeDeviceId;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  // NEW: runs once on page load to fetch devices and admin status
  Future<void> _loadInitialData() async {

      final user = await FirebaseAuth.instance.authStateChanges().first;
      if (user == null || !mounted) return;

    // Fetch user's devices — we take the first one as the active device
    final devices = await ref.read(userDevicesProvider.future);
    // ref.read() is used here instead of ref.watch() because we only
    // want this once on init, not to rebuild on every change.

    if (!mounted) return;
setState(() {
  _activeDeviceId = devices.firstOrNull?.deviceId ?? 'no-device';
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

  Future<void> _onRefresh() async {
    // Invalidate the sensor provider so it re-fetches from Firebase
    if (_activeDeviceId != null) {
      ref.invalidate(sensorDataProvider(_activeDeviceId!));
       ref.invalidate(nextWaterProvider(_activeDeviceId!));
    }
    ref.invalidate(allDevicesSensorProvider);
    // Small delay so the spinner feels intentional
    await Future.delayed(const Duration(milliseconds: 800));
  }

 @override
Widget build(BuildContext context) {
  final sensorAsync = ref.watch(sensorDataProvider(_activeDeviceId ?? 'no-device'));
final nextWaterAsync = ref.watch(nextWaterProvider(_activeDeviceId ?? 'no-device'));
  
  final allDevicesAsync = ref.watch(allDevicesSensorProvider);

  
  final zoneDevices = allDevicesAsync.when(
    data: (allDevices) => allDevices,
    loading: () =>
        <(DeviceModel, SensorData?)>[],
    error: (_, __) =>
        <(DeviceModel, SensorData?)>[],
  );

   // Compute avg moisture across all devices
  final avgMoisture = allDevicesAsync.when(
    data: (allDevices) {
      final moistures = allDevices
          .map((e) => e.$2?.moisture)
          .whereType<double>()
          .toList();
      return moistures.isEmpty
          ? null // null = fall back to single device moisture
          : moistures.reduce((a, b) => a + b) / moistures.length;
    },
    loading: () => null,
    error: (_, __) => null,
  );

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
                  // ─── GRADIENT CONTAINER ───
                  Container(
                    margin: const EdgeInsets.fromLTRB(4, 0, 4, 1),
                    decoration: const BoxDecoration(
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                        bottomLeft: Radius.circular(70),
                        bottomRight: Radius.circular(70),
                      ),
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
                    clipBehavior: Clip.antiAlias,
                    child:sensorAsync.when(
                            loading: () => const SizedBox(
                              height: 360,
                              child: Center(
                                child: CircularProgressIndicator(
                                    color: Colors.white),
                              ),
                            ),
                            error: (e, _) => SizedBox(
                              height: 360,
                              child: Center(
                                child: Text(
                                  'Failed to load sensor data.\n$e',
                                  style: const TextStyle(
                                      color: Colors.redAccent),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                            data: (sensorData) {
                              final nextWaterLabel = nextWaterAsync?.when(
                                    data: (v) => v ,// null = not enough history yet
                                    loading: () => '...',
                                    error: (_, __) => '—',
                                  ) ??
                                  '—';

                                  final avg = avgMoisture ?? sensorData.moisture;
                             

                             

                              return SingleChildScrollView(
                                padding: const EdgeInsets.all(8),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const _PageTitle(),
                                    const SizedBox(height: 10),
                                    _SensorGrid(
                                      temperature:
                                          sensorData.temperature,
                                      humidity: sensorData.humidity,
                                      nextWater: nextWaterLabel,
                                    ),
                                    const SizedBox(height: 12),
                                    _SoilMoistureCard(moisture: avg),
                                    const SizedBox(height: 12),
                                    const _WeatherCard(),
                                    const SizedBox(height: 12),
                                    _ZoneSection(devices: zoneDevices),
                                    const SizedBox(height: 16),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),

                  // ─── SLIDE TO REFRESH HINT ───
                  
                  const _SlideToRefreshHint(),
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

// ─── PAGE TITLE — unchanged ───────────────────────────────────────────────────

class _PageTitle extends StatelessWidget {
  const _PageTitle();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 6),
        Text(
          'HOMEPAGE',
          style: AppTextStyles.headline(26, AppColors.textPrimary,
              letterSpacing: 2, weight: FontWeight.w900),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(top: 15),
            height: 4,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

}

// ─── SENSOR GRID ─────────────────────────────────────────────────────────────

// CHANGE: was const _SensorGrid() with no parameters.
// Now accepts temperature, humidity, nextWater from the parent.
// Why: child widgets should just display what they're given —
//      they should not know where data comes from.
class _SensorGrid extends StatelessWidget {
  final double temperature;
  final double humidity;
  final String nextWater;

  const _SensorGrid({
    required this.temperature,
    required this.humidity,
    required this.nextWater,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SensorCard(
            imagePath: 'assets/temp.png',
            label: 'TEMPERATURE',
            // CHANGE: was hardcoded '32°C'
            // toStringAsFixed(1) formats to 1 decimal place e.g. '28.3°C'
            value: '${temperature.toStringAsFixed(1)}°C',
            valueColor: AppColors.tempCard,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SensorCard(
            imagePath: 'assets/humidity.png',
            label: 'HUMIDITY',
            // CHANGE: was hardcoded '32%'
            value: '${humidity.toStringAsFixed(0)}%',
            valueColor: AppColors.blueLight,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SensorCard(
            imagePath: 'assets/time.png',
            label: 'NEXT WATER',
            value: nextWater, // static for now
            valueColor: AppColors.waterNext,
          ),
        ),
      ],
    );
  }
}

// _SensorCard — unchanged, no data wiring needed here
class _SensorCard extends StatelessWidget {
  final String imagePath;
  final String label;
  final String value;
  final Color valueColor;

  const _SensorCard({
    required this.imagePath,
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 135,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color.fromARGB(185, 0, 0, 0),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 35,
            height: 35,
            decoration: BoxDecoration(color: valueColor, shape: BoxShape.circle),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Image.asset(imagePath),
            ),
          ),
          const SizedBox(height: 8),
          Text(label, style: AppTextStyles.mono(10, AppColors.textPrimary, weight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  color: valueColor,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  fontFamily: AppTextStyles.clashDisplay)),
          const Spacer(),
          Container(
            width: double.infinity,
            height: 4,
            decoration: BoxDecoration(color: valueColor, borderRadius: BorderRadius.circular(20)),
          ),
        ],
      ),
    );
  }
}

// ─── SOIL MOISTURE CARD ───────────────────────────────────────────────────────

// CHANGE: now accepts a moisture double (0–100) from parent
class _SoilMoistureCard extends StatelessWidget {
  final double moisture; // 0.0 to 100.0

  const _SoilMoistureCard({required this.moisture});

  // NEW: derive a status label and color from the moisture value
  // Why: the card shows 'GOOD' / 'LOW' / 'HIGH' based on thresholds.
  //      Keeping this logic here means the parent doesn't need to know about it.
  String get _statusLabel {
    if (moisture < 50) return 'LOW';
    if (moisture > 80) return 'HIGH';
    return 'GOOD';
  }

  Color get _statusColor {
    if (moisture < 50) return Colors.orangeAccent;
    if (moisture > 80) return Colors.redAccent;
    return AppColors.mutedGreen;
  }

  @override
  Widget build(BuildContext context) {
    // CHANGE: convert moisture (0–100) to percentage (0.0–1.0) for the arc painter
    final pct = (moisture / 100).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color.fromARGB(185, 0, 0, 0),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('AVG. SOIL MOISTURE',
              style: AppTextStyles.headline(16, AppColors.textPrimary,
                  letterSpacing: 1, weight: FontWeight.bold)),
          Row(
            children: [
              SizedBox(
                width: 210,
                height: 90,
                // CHANGE: was hardcoded percentage: 0.75
                child: CustomPaint(painter: _ArcPainter(percentage: pct)),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 6),
                  // CHANGE: was hardcoded 'Soil Moisture > 75%'
                  Text('Soil Moisture ${moisture.toStringAsFixed(0)}%',
                      style: AppTextStyles.mono(12, _statusColor, weight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
                    decoration: BoxDecoration(
                      // CHANGE: color now reflects status
                      color: AppColors.deepGreen,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    // CHANGE: was hardcoded 'GOOD'
                    child: Text(_statusLabel,
                        style: AppTextStyles.mono(11, _statusColor,
                            letterSpacing: 1, weight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// _ArcPainter — only change is shouldRepaint now returns true
// Why: before it always returned false meaning the arc never
//      repainted even when percentage changed. Now it checks
//      if the value actually changed before repainting.
class _ArcPainter extends CustomPainter {
  final double percentage;
  const _ArcPainter({required this.percentage});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height - 10;
    const radius = 60.0;
    const strokeWidth = 10.0;
    const startAngle = math.pi;
    const sweepAngle = math.pi;

    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: radius),
      startAngle, sweepAngle, false,
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: radius),
      startAngle, sweepAngle * percentage, false,
      Paint()
        ..color = AppColors.blueLight
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );

    final tp = TextPainter(
      text: TextSpan(
        text: '${(percentage * 100).round()}%',
        style: const TextStyle(
          fontFamily: AppTextStyles.satoshi,
          fontSize: 32,
          color: Color(0xFFE8F5E8),
          letterSpacing: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2 - 10));
  }

  @override
  // CHANGE: was always returning false
  // Why: returning false means "never repaint me" which breaks live updates.
  //      Now we only repaint if the percentage value actually changed.
  bool shouldRepaint(_ArcPainter old) => old.percentage != percentage;
}

// ─── WEATHER MODELS ──────────────────────────────────────────────────────────
 
class _HourlyForecast {
  final String time;   // e.g. "3 PM"
  final double temp;
  final int weatherCode;
  const _HourlyForecast({
    required this.time,
    required this.temp,
    required this.weatherCode,
  });
}
 
class _WeatherState {
  final double temp;
  final int weatherCode;
  final String date;
  final String location;
  final List<_HourlyForecast> hourly; // exactly 6 slots starting from next hour
  const _WeatherState({
    required this.temp,
    required this.weatherCode,
    required this.date,
    required this.location,
    required this.hourly,
  });
}
 
// ─── WEATHER CARD ─────────────────────────────────────────────────────────────
 
class _WeatherCard extends ConsumerStatefulWidget {
  const _WeatherCard();
 
  @override
  ConsumerState<_WeatherCard> createState() => _WeatherCardState();
}
 
class _WeatherCardState extends ConsumerState<_WeatherCard> {
  _WeatherState? _weather;
  String? _errorMessage;
  bool _loading = false;
  bool _locationDenied = false;

  @override
  void initState(){
    super.initState();
    _tryLoadFromCache();

  }
 
  // ── WMO code → label ─────────────────────────────────────────────────────
  String _label(int code) {
    if (code == 0) return 'CLEAR';
    if (code <= 3) return 'CLOUDY';
    if (code <= 49) return 'FOGGY';
    if (code <= 67) return 'RAINY';
    if (code <= 77) return 'SNOWY';
    if (code <= 82) return 'SHOWERS';
    if (code <= 99) return 'STORMY';
    return 'CLOUDY';
  }
 
  // ── WMO code → asset path ─────────────────────────────────────────────────
  String _asset(int code) {
    if (code == 0) return 'assets/temp.png';
    if (code <= 3) return 'assets/cloudy.png';
    if (code <= 49) return 'assets/cloudy.png';
    if (code <= 82) return 'assets/rain.png';
    return 'assets/rain.png';
  }
 
  // ── Rain hint from next 6 hours ───────────────────────────────────────────
  String _rainHint(List<_HourlyForecast> hourly) {
    for (final h in hourly) {
      if (h.weatherCode >= 51) return '☔ Rain predicted around ${h.time}';
    }
    return '☀️ No rain expected in the next 6 hours';
  }
 
  // ── Format hour → "3 PM" / "11 AM" ───────────────────────────────────────
  String _formatHour(int hour) {
    final suffix = hour >= 12 ? 'PM' : 'AM';
    final display = hour % 12 == 0 ? 12 : hour % 12;
    return '$display $suffix';
  }
 
  // ─── MAIN SETUP ───────────────────────────────────────────────────────────
   Future<void> _tryLoadFromCache() async {
    setState(() => _loading = true);
    try {
      final cache = await BackendService().getWeatherCache();
      if (cache != null && mounted) {
        // Re-fetch live data using the cached lat/lon so hourly is fresh
        final lat = (cache['lat'] as num).toDouble();
        final lon = (cache['lon'] as num).toDouble();
        final locationName = cache['locationName'] as String? ?? '';
        await _fetchWeatherForCoords(lat, lon, locationName);
        return;
      }
    } catch (_) {
      // Cache miss or RTDB error — fall through to show setup prompt
    }
    if (mounted) setState(() => _loading = false);
  }

  // ── Core fetch: given coords → hit Open-Meteo → update state + write cache ─
  Future<void> _fetchWeatherForCoords(
    double lat,
    double lon,
    String locationName,
  ) async {
    setState(() { _loading = true; _errorMessage = null; });

    try {
      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$lat'
        '&longitude=$lon'
        '&current=temperature_2m,weathercode'
        '&hourly=temperature_2m,weathercode'
        '&forecast_days=1'
        '&timezone=auto',
      );
      final res = await http.get(url).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) throw Exception('API error ${res.statusCode}');
      final json = jsonDecode(res.body) as Map<String, dynamic>;

      final current = json['current'] as Map<String, dynamic>;
      final double currentTemp = (current['temperature_2m'] as num).toDouble();
      final int currentCode = (current['weathercode'] as num).toInt();

      final hourlyTimes = (json['hourly']['time'] as List).cast<String>();
      final hourlyTemps = (json['hourly']['temperature_2m'] as List)
          .map((e) => (e as num).toDouble()).toList();
      final hourlyCodes = (json['hourly']['weathercode'] as List)
          .map((e) => (e as num).toInt()).toList();

      final now = DateTime.now();
      final nextHour = now.hour < 23
          ? DateTime(now.year, now.month, now.day, now.hour + 1)
          : DateTime(now.year, now.month, now.day + 1, 0);

      final forecasts = <_HourlyForecast>[];
      for (int i = 0; i < hourlyTimes.length && forecasts.length < 6; i++) {
        final slotTime = DateTime.parse(hourlyTimes[i]);
        if (!slotTime.isBefore(nextHour)) {
          forecasts.add(_HourlyForecast(
            time: _formatHour(slotTime.hour),
            temp: hourlyTemps[i],
            weatherCode: hourlyCodes[i],
          ));
        }
      }

      final months = ['Jan','Feb','Mar','Apr','May','Jun',
                      'Jul','Aug','Sep','Oct','Nov','Dec'];
      final dateStr = '${now.day} ${months[now.month - 1]} ${now.year}';

      // Write to RTDB so next app launch uses this location
      await BackendService().saveWeatherCache(
        data: {'temp': currentTemp, 'weatherCode': currentCode, 'date': dateStr},
        lat: lat,
        lon: lon,
        locationName: locationName,
      );

      if (mounted) {
        setState(() {
          _weather = _WeatherState(
            temp: currentTemp,
            weatherCode: currentCode,
            date: dateStr,
            location: locationName,
            hourly: forecasts,
          );
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _errorMessage = e.toString(); });
    }
  }

  // ── GPS flow (same as before, now calls _fetchWeatherForCoords) ───────────
  Future<void> _setupWeather() async {
    setState(() { _loading = true; _locationDenied = false; _errorMessage = null; });

    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) setState(() { _locationDenied = true; _loading = false; });
        return;
      }

      Position? pos = await Geolocator.getLastKnownPosition();
      pos ??= await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 10),
      );

      // Reverse geocode
      String locationName =
          '${pos.latitude.toStringAsFixed(2)}, ${pos.longitude.toStringAsFixed(2)}';
      try {
        final geoRes = await http.get(
          Uri.parse(
            'https://nominatim.openstreetmap.org/reverse'
            '?lat=${pos.latitude}&lon=${pos.longitude}&format=json',
          ),
          headers: {'User-Agent': 'GrowWiser/1.0'},
        ).timeout(const Duration(seconds: 5));
        if (geoRes.statusCode == 200) {
          final geoJson = jsonDecode(geoRes.body) as Map<String, dynamic>;
          final address = geoJson['address'] as Map<String, dynamic>? ?? {};
          locationName = address['city'] ?? address['town'] ??
              address['village'] ?? address['county'] ?? locationName;
        }
      } catch (_) {}

      await _fetchWeatherForCoords(pos.latitude, pos.longitude, locationName);
    } catch (e) {
      if (mounted) setState(() { _loading = false; _errorMessage = e.toString(); });
    }
  }

 
  void _showEditLocationSheet() {
    final ctrl = TextEditingController();
    bool searching = false;
    String? sheetError;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheet) {
          Future<void> searchCity() async {
            final query = ctrl.text.trim();
            if (query.isEmpty) return;
            setSheet(() { searching = true; sheetError = null; });

            final result = await BackendService().geocodeCity(query);
            if (result == null) {
              setSheet(() { searching = false; sheetError = 'City not found. Try a different name.'; });
              return;
            }
            Navigator.pop(ctx);
            await _fetchWeatherForCoords(
              result['lat'] as double,
              result['lon'] as double,
              result['displayName'] as String,
            );
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1F1A),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // handle
                  Center(
                    child: Container(
                      width: 36, height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text('CHANGE LOCATION',
                      style: AppTextStyles.mono(11, Colors.white,
                          weight: FontWeight.w800, letterSpacing: 1.5)),
                  const SizedBox(height: 14),

                  // search field
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.12)),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 14),
                        Expanded(
                          child: TextField(
                            controller: ctrl,
                            autofocus: true,
                            onSubmitted: (_) => searchCity(),
                            style: AppTextStyles.mono(13, Colors.white,
                                weight: FontWeight.w600),
                            decoration: InputDecoration(
                              hintText: 'Search city…',
                              hintStyle: AppTextStyles.mono(13,
                                  Colors.white38, weight: FontWeight.w500),
                              border: InputBorder.none,
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: searchCity,
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE4F27A).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: searching
                                ? const SizedBox(
                                    width: 16, height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFFE4F27A)),
                                  )
                                : const Icon(Icons.search,
                                    color: Color(0xFFE4F27A), size: 18),
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (sheetError != null) ...[
                    const SizedBox(height: 8),
                    Text(sheetError!,
                        style: AppTextStyles.mono(11, Colors.redAccent,
                            weight: FontWeight.w500)),
                  ],

                  const SizedBox(height: 12),

                  // Use my location button
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      _setupWeather();
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.my_location,
                              color: Color(0xFFE4F27A), size: 16),
                          const SizedBox(width: 8),
                          Text('USE MY LOCATION',
                              style: AppTextStyles.mono(11,
                                  const Color(0xFFE4F27A),
                                  weight: FontWeight.w700, letterSpacing: 1)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            AppColors.blueLight,
            AppColors.weatherBlue,
            AppColors.blueDim,
            AppColors.blueDark,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: _loading
          ? _buildLoading()
          : _weather == null
              ? _buildSetupPrompt()
              : _buildWeatherContent(),
    );
  }
 
  // ── STATE: setup prompt ───────────────────────────────────────────────────
  Widget _buildSetupPrompt() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.15),
              border:
                  Border.all(color: Colors.white.withOpacity(0.3), width: 1),
            ),
            child: const Icon(Icons.location_off_outlined,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _locationDenied
                      ? 'LOCATION DENIED'
                      : _errorMessage != null
                          ? 'WEATHER ERROR'
                          : 'WEATHER MONITORING',
                  style: AppTextStyles.mono(10, Colors.white,
                      weight: FontWeight.w800, letterSpacing: 1.5),
                ),
                const SizedBox(height: 4),
                Text(
                  _locationDenied
                      ? 'Enable location in device settings to activate weather.'
                      : _errorMessage != null
                          ? _errorMessage!
                          : 'Activate location to get live weather for your garden.',
                  style: AppTextStyles.mono(
                    9,
                    _errorMessage != null
                        ? Colors.redAccent.withOpacity(0.9)
                        : Colors.white.withOpacity(0.65),
                    weight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _setupWeather,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: Colors.white.withOpacity(0.35), width: 0.8),
              ),
              child: Text(
                _errorMessage != null ? 'RETRY' : 'SET UP',
                style: AppTextStyles.mono(9, Colors.white,
                    weight: FontWeight.w800, letterSpacing: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
 
  // ── STATE: loading ────────────────────────────────────────────────────────
  Widget _buildLoading() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 22),
      child: Center(
        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
      ),
    );
  }
 
  // ── STATE: data ready ─────────────────────────────────────────────────────
  Widget _buildWeatherContent() {
    final w = _weather!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── date + location row ──
        Row(
          children: [
            Text(
              w.date,
              style: AppTextStyles.mono(10, Colors.white.withOpacity(0.7),weight: FontWeight.w700),
            ),
            const SizedBox(width: 6),
            Text('·',
                style:
                    TextStyle(color: Colors.white.withOpacity(0.4),fontWeight: FontWeight.w700)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                w.location,
                overflow: TextOverflow.ellipsis,
                style:
                    AppTextStyles.mono(10, Colors.white.withOpacity(0.7),weight: FontWeight.w700),
              ),
            ),
            GestureDetector(
              onTap: _showEditLocationSheet,
              child: Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(Icons.edit_outlined,
                    size: 14, color: Colors.white.withOpacity(0.55)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
 
        // ── current + hourly row ──
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Current weather — fixed width prevents overflow
            SizedBox(
              width: 115,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Image.asset(
                    _asset(w.weatherCode),
                    width: 36,
                    height: 36,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 6),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _label(w.weatherCode),
                        style: AppTextStyles.mono(
                          9,
                          Colors.white.withOpacity(0.8),
                          weight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      Text(
                        '${w.temp.toStringAsFixed(0)}°C',
                        style: AppTextStyles.headline(28, Colors.white,
                            letterSpacing: 1),
                      ),
                    ],
                  ),
                ],
              ),
            ),
 
            // Vertical divider
            Container(
              width: 1,
              height: 50,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: Colors.white.withOpacity(0.2),
            ),
 
            // Hourly forecast — scrollable, takes remaining space
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: w.hourly
                      .map((h) => Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: _ForecastItem(
                              time: h.time,
                              icon: _asset(h.weatherCode),
                              temp: '${h.temp.toStringAsFixed(0)}°C',
                            ),
                          ))
                      .toList(),
                ),
              ),
            ),
          ],
        ),
 
        const SizedBox(height: 4),
 
        // ── rain hint ──
        Text(
          _rainHint(w.hourly),
          style: AppTextStyles.body(9, Colors.white.withOpacity(0.7),
              weight: FontWeight.w600),
        ),
      ],
    );
  }
}
 
// ─── FORECAST ITEM ────────────────────────────────────────────────────────────
 
class _ForecastItem extends StatelessWidget {
  final String time, icon, temp;
  const _ForecastItem({
    required this.time,
    required this.icon,
    required this.temp,
  });
 
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            time,
            style: AppTextStyles.mono(8, Colors.white.withOpacity(0.7),
                weight: FontWeight.w600),
          ),
          const SizedBox(height: 3),
          Image.asset(icon, width: 20, height: 20, fit: BoxFit.contain),
          const SizedBox(height: 4),
          Container(height: 1, width: 28, color: Colors.white.withOpacity(0.3)),
          const SizedBox(height: 4),
          Text(
            temp,
            style:
                AppTextStyles.mono(9, Colors.white, weight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

// ─── ZONE SECTION ─────────────────────────────────────────────────────────────

class _ZoneSection extends ConsumerWidget {
  // List of (DeviceModel, SensorData?) — one entry per device
  final List<(DeviceModel, SensorData?)> devices;
  const _ZoneSection({required this.devices});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Always show 4 slots — fill from real devices, rest are N/A
    const maxZones = 4;

    return Column(
      children: [
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(maxZones, (i) {
            if (i < devices.length) {
              final device = devices[i].$1;
              final sensor = devices[i].$2;
              final moisture = sensor?.moisture ?? 0.0;
              final pct = (moisture / 100).clamp(0.0, 1.0);
              // Use location name, fall back to device name
              final label = device.location.isNotEmpty
                  ? device.location
                  : device.name;
              return _ZoneBar(
                pct: pct,
                label: label,
                color: AppColors.white,
                isEmpty: false,
              );
            } else {
              // Unpopulated slot
              return _ZoneBar(
                pct: 0.0,
                label: 'N/A',
                color: Colors.white24,
                isEmpty: true,
              );
            }
          }),
        ),
        const SizedBox(height: 15),
        Text(
          'ZONAL SOIL MOISTURE',
          style: AppTextStyles.mono(13, Colors.black,
              letterSpacing: 1, weight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Container(height: 2, width: 180, color: const Color(0xFF000000)),
      ],
    );
  }
}

class _ZoneBar extends StatelessWidget {
  final double pct;
  final String label;
  final Color color;
  final bool isEmpty;

  const _ZoneBar({
    required this.pct,
    required this.label,
    required this.color,
    required this.isEmpty,
  });

  @override
  Widget build(BuildContext context) {
    const barHeight = 100.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Column(
        children: [
          Container(
            width: 40,
            height: barHeight,
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                width: 0.8,
                color: isEmpty
                    ? AppColors.black.withOpacity(0.3)
                    : AppColors.black,
              ),
            ),
            alignment: Alignment.bottomCenter,
            child: pct > 0
                ? FractionallySizedBox(
                    heightFactor: pct,
                    widthFactor: 1.0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(width: 0.8, color: AppColors.black),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${(pct * 100).round()}%',
                        style: AppTextStyles.mono(11, AppColors.black,
                            weight: FontWeight.bold),
                      ),
                    ),
                  )
                : Center(
                    child: Text(
                      '0%',
                      style: AppTextStyles.mono(11,
                          AppColors.black.withOpacity(isEmpty ? 0.3 : 1.0),
                          weight: FontWeight.bold),
                    ),
                  ),
          ),
          const SizedBox(height: 4),
          // Truncate long location names to fit the bar width
          SizedBox(
            width: 50,
            child: Text(
              label,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.mono(
                9,
                isEmpty
                    ? const Color(0xFF000000).withOpacity(0.3)
                    : const Color(0xFF000000),
                letterSpacing: 0.5,
                weight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── NAV BAR — unchanged ──────────────────────────────────────────────────────

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
    const _NavItem(number: '01', label: 'HOME', imagePath: 'assets/home.png'),
    if (!showAdmin) ...[
      const _NavItem(number: '02', label: 'COMMAND', imagePath: 'assets/command_black.png'),
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
    return Center (
      child :Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _bob,
            builder: (_, child) => Transform.translate(
              offset: Offset(0, _bob.value),
              child: child,
            ),
            child: Container(
              width: 30, height: 30,
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
    ),
    );
  }
}