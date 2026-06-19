import 'package:flutter/material.dart';
import '../theme/app_Theme.dart';



class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final int _currentIndex = 0;
  final bool _isAdmin = true;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
        bottomNavigationBar: GrowWiserNavBar(
      currentIndex: _currentIndex,
      onTap: _onNavTap,
      showAdmin:_isAdmin,
    ),
      body: Column(
        children: [
          _AdminHeader(),
          Expanded(
            child: Container(
              padding: EdgeInsets.fromLTRB(16,8,16,0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children:  [
                  _SectionHeader(label: 'ERROR LOGS'),
                  SizedBox(height: 10),
                  _ErrorCard(),
                  SizedBox(height: 15),
                  _NoErrorLabel(),
                  SizedBox(height: 10),
                  _PublishButton(),
                  SizedBox(height: 18),
                  Container(
                    padding:EdgeInsets.fromLTRB(12,8,12,10),
                    decoration:BoxDecoration(
                       color:const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child:const SingleChildScrollView(
                    child:Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                    children : [
                  _StatRow(icon: 'assets/health.png',  label: 'SYSTEM HEALTH', date: '24/2/26', value: '100%', ),
                  SizedBox(height: 8),
                  _StatRow(icon: 'assets/error.png',  label: 'UNRESOLVED ERRORS', date: '24/2/26', value: '0', ),
                  SizedBox(height: 8),
                  _StatRow(icon:'assets/service.png', label: 'LAST MAINTENANCE', date: '24/2/26', value: '24/2/26',  smallValue: true),
                  

                    ], 
                    ),
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
}

class _AdminHeader extends StatelessWidget {
  const _AdminHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(15, MediaQuery.of(context).padding.top + 2, 20, 20),
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
              Text('ADMIN PANEL', style: AppTextStyles.headline(24, const Color(0xFF2A1A0A), letterSpacing: 2,weight:FontWeight.w900)),
              const SizedBox(width: 10),
              Expanded(child: Container(height: 3, color: const Color(0xFF2A1A0A))),
            ],
          ),
          const SizedBox(height: 4),
          Text('Welcome Admin, Goodluck with Your Work',
              style: AppTextStyles.body(11, const Color(0xFF2A1A0A),weight:FontWeight.w900).copyWith(fontStyle: FontStyle.italic)),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
             
              Text('SUN , 7 MARCH  ',
                  style: AppTextStyles.mono(10, const Color(0xFF2A1A0A), letterSpacing: 1,weight:FontWeight.w700)),
              Text('18:30', style: AppTextStyles.headline(44, const Color(0xFF2A1A0A), letterSpacing: 2,weight:FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: AppTextStyles.headline(18, AppColors.white, letterSpacing: 2,weight:FontWeight.w700)),
        const SizedBox(width: 10),
        Expanded(child: Container(height: 2, color: const Color(0xFF333333))),
      ],
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard();

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
        children: [
          Text('LATEST ERROR CODE:', style: AppTextStyles.mono(10, AppColors.white, letterSpacing: 2,weight:FontWeight.bold).copyWith(fontStyle: FontStyle.italic)),
          const SizedBox(height: 8,
         ),
          Text('CODE:\nERROR DETAIL:\nTIME:',
              style: AppTextStyles.mono(10, AppColors.white,weight:FontWeight.w600),
              textAlign: TextAlign.start),
        ],
      ),
    );
  }
}

class _NoErrorLabel extends StatelessWidget {
  const _NoErrorLabel();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text('NO CRITICAL ERRORS DETECTED',
          style: AppTextStyles.headline(10, AppColors.yellowWarning, letterSpacing: 1,weight:FontWeight.w700)),
    );
  }
}

class _PublishButton extends StatelessWidget {
  const _PublishButton();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {},
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
              decoration: const BoxDecoration(color: Color(0xFF1A3A1A), shape: BoxShape.circle),
              child: const Icon(Icons.upload_outlined, color: Color(0xFFA0E0A0), size: 20),
            ),
            const SizedBox(width: 12),
            Text('PUBLISH NEW VERSION',
                style: AppTextStyles.headline(18, const Color(0xFFC8F0C8), letterSpacing: 2)),
          ],
        ),
      ),
    );
  }
}

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
            padding:EdgeInsets.fromLTRB(7, 7, 7, 7),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Image.asset(icon,fit:BoxFit.cover),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTextStyles.mono(11, const Color(0xFFC0C0C0), weight: FontWeight.bold, letterSpacing: 1)),
                Text('LAST CHECKED: $date', style: AppTextStyles.mono(9, const Color(0xFF555555),weight: FontWeight.bold)),
              ],
            ),
          ),
          Text(
            value,
            style: smallValue
                ? AppTextStyles.mono(18,AppColors.white, weight: FontWeight.bold)
                : AppTextStyles.headline(26,AppColors.white, letterSpacing: 1),
          ),
        ],
      ),
    );
  }
}



class GrowWiserNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool showAdmin;
 
  const GrowWiserNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.showAdmin = true,
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
  const _NavItem(number: '01', label: 'HOME',    imagePath: 'assets/home.png'),
  if (!showAdmin) ...[
    const _NavItem(number: '02', label: 'COMMAND', imagePath: 'assets/command_black.png'),
    const _NavItem(number: '03', label: 'DEVICES', imagePath: 'assets/tools_black.png'),
    const _NavItem(number: '04', label: 'LOG OUT', imagePath: 'assets/logout_black.png'),
  ] else ...[
    const _NavItem(number: '02', label: 'LOG OUT', imagePath: 'assets/logout_black.png'),
  ],
];
}
 
// ─── Data model ───────────────────────────────
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
          color:  Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(40),
            topRight: Radius.circular(40),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ── Icon circle ──
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? AppColors.black :Colors.white ,
                border: Border.all(
                  color: isSelected ? Colors.white : AppColors.black,
                  width: 0.5,
                ),
              ),
               padding: const EdgeInsets.all(8), 
              child: Image.asset(
  item.imagePath,
  fit: BoxFit.contain,
),
            ),
            const SizedBox(height: 3),
            // ── Number ──
            Text(
              item.number,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
                color: Colors.black,
                fontFamily: AppTextStyles.clashDisplay,
              ),
            ),
            // ── Label ──
            Text(
              item.label,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color:  AppColors.black,
                fontFamily: AppTextStyles.satoshi,
              ),
            ),
            // ── Underline ──
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