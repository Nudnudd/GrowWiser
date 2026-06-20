import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_Theme.dart';
import '../services/backend_service.dart';
import 'package:url_launcher/url_launcher.dart';

// ══════════════════════════════════════════════════════════════════════════
// PROVIDERS
// ══════════════════════════════════════════════════════════════════════════

// Fetches the latest error log across all devices for this admin
final adminErrorLogProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return null;

  final snap = await FirebaseFirestore.instance
      .collectionGroup('errors')
      .where('resolved', isEqualTo: false)
      .orderBy('created_at', descending: true)
      .limit(1)
      .get();

  if (snap.docs.isEmpty) return null;
  
  // Include doc path so we can resolve it
  final data = snap.docs.first.data();
  data['_docPath'] = snap.docs.first.reference.path; // NEW
  return data;
});

final unresolvedErrorCountProvider = FutureProvider<int>((ref) async {
  final snap = await FirebaseFirestore.instance
      .collectionGroup('errors')
      .where('resolved', isEqualTo: false)
      .get();
  return snap.docs.length;
});

// ══════════════════════════════════════════════════════════════════════════
// ADMIN PAGE
// ══════════════════════════════════════════════════════════════════════════

class AdminPage extends ConsumerStatefulWidget {
  const AdminPage({super.key});

  @override
  ConsumerState<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends ConsumerState<AdminPage> {
  final int _currentIndex = 0;
  final bool _isAdmin = true;

  Future<void> _resolveError(String docPath) async {
  await FirebaseFirestore.instance
      .doc(docPath)
      .update({'resolved': true});
  ref.invalidate(adminErrorLogProvider);
  ref.invalidate(unresolvedErrorCountProvider);
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

  Future<void> _handlePublish() async {
  const repoUrl = 'https://github.com/Nudnudd/GrowWiser';
  
  try {
    await launchUrl(
      Uri.parse(repoUrl),
      mode: LaunchMode.externalApplication,
    );
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open repo: $e',
              style: AppTextStyles.mono(12, Colors.white)),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }
}


  @override
  Widget build(BuildContext context) {
    final errorAsync = ref.watch(adminErrorLogProvider);
    final errorCountAsync = ref.watch(unresolvedErrorCountProvider);

    return Scaffold(
      backgroundColor: AppColors.black,
      bottomNavigationBar: GrowWiserNavBar(
        currentIndex: _currentIndex,
        onTap: _onNavTap,
        showAdmin: _isAdmin,
      ),
      body: Column(
        children: [
          const _AdminHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionHeader(label: 'ERROR LOGS'),
                  const SizedBox(height: 10),

                  // Error card — wired to Firebase
                  errorAsync.when(
                    loading: () => _buildLoadingCard(),
                    error: (e, _) => _ErrorCard(
                      errorCode: 'FETCH ERROR',
                      errorDetail: e.toString(),
                      errorTime: '—',
                    ),
                    data: (error) => error == null
                        ? const _NoErrorCard()
                        : _ErrorCard(
                            errorCode: error['error_code'] ?? '—',
                            errorDetail: error['error_message'] ?? error['detail'] ?? '—',
                            errorTime: error['created_at'] != null
                                ? _formatTimestamp(
                                    error['created_at'] as Timestamp)
                                : '—',
                                docPath: error['_docPath'] as String?, 
        onResolve: error['_docPath'] != null     
            ? () => _resolveError(error['_docPath'] as String)
            : null,
                          ),
                  ),

                  const SizedBox(height: 15),

                  errorCountAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (count) => Center(
                      child: Text(
                        count == 0
                            ? 'NO CRITICAL ERRORS DETECTED'
                            : '$count UNRESOLVED ERROR${count > 1 ? 'S' : ''}',
                        style: AppTextStyles.headline(
                          10,
                          count == 0
                              ? AppColors.yellowWarning
                              : Colors.redAccent,
                          letterSpacing: 1,
                          weight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  _PublishButton(
                    isLoading: false,
                    onTap: _handlePublish,
                  ),

                  const SizedBox(height: 18),

                  // Stat rows — wired to live data
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // System health — derived from error count
                       errorCountAsync.when(
  loading: () => _StatRow(
    icon: 'assets/health.png',
    label: 'SYSTEM HEALTH',
    date: _todayStr(),
    value: '...',
  ),
  error: (_, __) => _StatRow(
    icon: 'assets/health.png',
    label: 'SYSTEM HEALTH',
    date: _todayStr(),
    value: '—',
  ),
  data: (count) {
    final health = (100.0 - (count * 0.2)).clamp(0.0, 100.0);
    final healthStr = health <= 0 ? 'CRITICAL' : '${health.toStringAsFixed(1)}%';
    
    return _StatRow(
      icon: 'assets/health.png',
      label: 'SYSTEM HEALTH',
      date: _todayStr(),
      value: healthStr,
    );
  },
),
                        const SizedBox(height: 8),

                        // Unresolved errors count
                        errorCountAsync.when(
                          loading: () => _StatRow(
                            icon: 'assets/error.png',
                            label: 'UNRESOLVED ERRORS',
                            date: _todayStr(),
                            value: '...',
                          ),
                          error: (_, __) => _StatRow(
                            icon: 'assets/error.png',
                            label: 'UNRESOLVED ERRORS',
                            date: _todayStr(),
                            value: '—',
                          ),
                          data: (count) => _StatRow(
                            icon: 'assets/error.png',
                            label: 'UNRESOLVED ERRORS',
                            date: _todayStr(),
                            value: '$count',
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Last maintenance — static for now, wire when you have a maintenance log
                        _StatRow(
                          icon: 'assets/service.png',
                          label: 'LAST MAINTENANCE',
                          date: _todayStr(),
                          value: _todayStr(),
                          smallValue: true,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.redBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Center(
        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
      ),
    );
  }

  String _formatTimestamp(Timestamp ts) {
    final dt = ts.toDate();
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    return '$day/$month/${dt.year.toString().substring(2)} $h:$m';
  }

  String _todayStr() {
    final now = DateTime.now();
    final d = now.day.toString().padLeft(2, '0');
    final m = now.month.toString().padLeft(2, '0');
    final y = now.year.toString().substring(2);
    return '$d/$m/$y';
  }
}

// ══════════════════════════════════════════════════════════════════════════
// HEADER
// ══════════════════════════════════════════════════════════════════════════

class _AdminHeader extends StatelessWidget {
  const _AdminHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
          15, MediaQuery.of(context).padding.top + 2, 20, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.creamCard, AppColors.cream],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('ADMIN PANEL',
                  style: AppTextStyles.headline(24, const Color(0xFF2A1A0A),
                      letterSpacing: 2, weight: FontWeight.w900)),
              const SizedBox(width: 10),
              Expanded(
                  child: Container(height: 3, color: const Color(0xFF2A1A0A))),
            ],
          ),
          const SizedBox(height: 4),
          Text('Welcome Admin, Goodluck with Your Work',
              style: AppTextStyles
                  .body(11, const Color(0xFF2A1A0A), weight: FontWeight.w900)
                  .copyWith(fontStyle: FontStyle.italic)),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Builder(builder: (context) {
                final now = DateTime.now();
                final days = [
                  'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'
                ];
                final months = [
                  'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE',
                  'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER',
                  'DECEMBER'
                ];
                return Text(
                  '${days[now.weekday - 1]} , ${now.day} ${months[now.month - 1]}  ',
                  style: AppTextStyles.mono(10, const Color(0xFF2A1A0A),
                      letterSpacing: 1, weight: FontWeight.w700),
                );
              }),
              Builder(builder: (context) {
                final now = DateTime.now();
                final h = now.hour.toString().padLeft(2, '0');
                final m = now.minute.toString().padLeft(2, '0');
                return Text('$h:$m',
                    style: AppTextStyles.headline(44, const Color(0xFF2A1A0A),
                        letterSpacing: 2, weight: FontWeight.w700));
              }),
            ],
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// SECTION HEADER
// ══════════════════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label,
            style: AppTextStyles.headline(18, AppColors.white,
                letterSpacing: 2, weight: FontWeight.w700)),
        const SizedBox(width: 10),
        Expanded(
            child: Container(height: 2, color: const Color(0xFF333333))),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// ERROR CARD — wired
// ══════════════════════════════════════════════════════════════════════════

class _ErrorCard extends StatelessWidget {
  final String errorCode;
  final String errorDetail;
  final String errorTime;
  final String? docPath;        // NEW
  final VoidCallback? onResolve; // NEW

  const _ErrorCard({
    required this.errorCode,
    required this.errorDetail,
    required this.errorTime,
    this.docPath,
    this.onResolve,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.redBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('LATEST ERROR CODE:',
              style: AppTextStyles.mono(10, AppColors.white,
                      letterSpacing: 2, weight: FontWeight.bold)
                  .copyWith(fontStyle: FontStyle.italic)),
          const SizedBox(height: 8),
          Text('CODE: $errorCode',
              style: AppTextStyles.mono(10, AppColors.white,
                  weight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('ERROR DETAIL: $errorDetail',
              style: AppTextStyles.mono(10, AppColors.white,
                  weight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('TIME: $errorTime',
              style: AppTextStyles.mono(10, AppColors.white,
                  weight: FontWeight.w600)),

          // Resolve button
          if (onResolve != null) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: onResolve,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(
                      color: Colors.white.withOpacity(0.4)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('MARK RESOLVED',
                    style: AppTextStyles.mono(10, Colors.white,
                        weight: FontWeight.w700, letterSpacing: 1)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NoErrorCard extends StatelessWidget {
  const _NoErrorCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.deepGreen,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color:const Color(0xFFE4F27A).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline,
              color: Color(0xFFE4F27A), size: 20),
          const SizedBox(width: 10),
          Text('No errors logged.',
              style: AppTextStyles.mono(11,const Color(0xFFE4F27A),
                  weight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// PUBLISH BUTTON — wired
// ══════════════════════════════════════════════════════════════════════════

class _PublishButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onTap;

  const _PublishButton({required this.isLoading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: AppColors.deepGreen,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                  color: Color(0xFF1A3A1A), shape: BoxShape.circle),
              child: isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(
                          color: Color(0xFFE4F27A), strokeWidth: 2),
                    )
                  : const Icon(Icons.open_in_new,  // Changed icon
                      color: Color(0xFFE4F27A), size: 20),
            ),
            const SizedBox(width: 12),
            Text('OPEN GITHUB REPO',  // Changed label
                style: AppTextStyles.headline(18, const Color(0xFFE4F27A),
                    letterSpacing: 2)),
          ],
        ),
      ),
    );
  }
}



// ══════════════════════════════════════════════════════════════════════════
// STAT ROW
// ══════════════════════════════════════════════════════════════════════════

class _StatRow extends StatelessWidget {
  final String icon;
  final String label, date, value;
  final bool smallValue;

  const _StatRow({
    required this.icon,
    required this.label,
    required this.date,
    required this.value,
    this.smallValue = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF5C0307),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Image.asset(icon, fit: BoxFit.cover),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: AppTextStyles.mono(11, const Color(0xFFC0C0C0),
                        weight: FontWeight.bold, letterSpacing: 1)),
                Text('LAST CHECKED: $date',
                    style: AppTextStyles.mono(9, const Color(0xFF555555),
                        weight: FontWeight.bold)),
              ],
            ),
          ),
          Text(
            value,
            style: (smallValue
                ? AppTextStyles.mono(18, AppColors.white,
                    weight: FontWeight.bold)
                : AppTextStyles.headline(26,  AppColors.white, 
                    letterSpacing: 1)),
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
    this.showAdmin = false, // fixed: was wrongly defaulting to true
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
            number: '01', label: 'HOME', imagePath: 'assets/home.png'),
        if (!showAdmin) ...[
          const _NavItem(
              number: '02',
              label: 'COMMAND',
              imagePath: 'assets/command_black.png'),
          const _NavItem(
              number: '03',
              label: 'DEVICES',
              imagePath: 'assets/tools_black.png'),
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