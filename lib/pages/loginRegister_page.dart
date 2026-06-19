
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'; // NEW — needed for ConsumerStatefulWidget
import '../theme/app_theme.dart';
import '../services/backend_service.dart';               // NEW — our BackendService
import 'dashboard_page.dart';
import 'admin_page.dart';

// ─── MAIN AUTH PAGE ───────────────────────────────────────────────────────────
// CHANGE: StatefulWidget → ConsumerStatefulWidget
// Why: ConsumerStatefulWidget gives our State class access to `ref`,
//      which lets us read Riverpod providers. Without this, we can't
//      watch auth state changes from Firebase.
class AuthPage extends ConsumerStatefulWidget {
  final bool startOnLogin;
  const AuthPage({this.startOnLogin = true, super.key});

  @override
  ConsumerState<AuthPage> createState() => _AuthPageState();
  // CHANGE: State<AuthPage> → ConsumerState<AuthPage>
  // Why: Matches the ConsumerStatefulWidget above. ConsumerState
  //      is what gives us the `ref` object inside the state class.
}

class _AuthPageState extends ConsumerState<AuthPage> {
  late final PageController _pageController;
  late bool _isLogin;

  // CHANGE: _usernameCtrl renamed to _emailCtrl
  // Why: Firebase Auth identifies users by EMAIL, not username.
  //      The visual hint text in the field will say 'EMAIL' too.
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  // NEW: tracks whether a login/signup request is in flight
  // Why: While waiting for Firebase, we disable the button and show
  //      a spinner so the user can't tap twice and get a double-request.
  bool _isLoading = false;

  // NEW: holds an error message to show under the login button
  // Why: Firebase throws typed exceptions (wrong password, no user, etc.)
  //      We catch them and store a human-readable message here.
  //      Null means no error to show.
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _isLogin = widget.startOnLogin;
    _pageController = PageController(initialPage: _isLogin ? 0 : 1);
  }

  void _switchTab(bool toLogin) {
    if (_isLogin == toLogin) return;
    // Also clear errors when switching tabs — stale errors are confusing
    setState(() {
      _isLogin = toLogin;
      _errorMessage = null;
    });
    _pageController.animateToPage(
      toLogin ? 0 : 1,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  // CHANGE: _handleLogin is now async
  // Why: BackendService().signIn() returns a Future — it needs to wait
  //      for Firebase to respond before we can navigate. Async/await
  //      lets us write that waiting logic in a readable, linear way.
  Future<void> _handleLogin() async {
    // Clear any previous error and start loading
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Call BackendService — this talks to Firebase Auth
      // signIn takes email + password, returns a UserCredential on success,
      // or throws a FirebaseAuthException on failure.
      await BackendService().signIn(
        _emailCtrl.text.trim(),
        _passwordCtrl.text.trim(),
      );

      // CHANGE: admin check now comes from Firestore, not a string comparison
      // Why: Checking if username == 'admin' is not real auth. isAdmin()
      //      reads the user's role from Firestore after a verified login.
      final admin = await BackendService().isAdmin();

      // Navigate based on role — using pushReplacement so back button
      // doesn't return to the login screen
      if (mounted) {
        if (admin) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const AdminPage()),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const DashboardPage()),
          );
        }
      }
    } on Exception catch (e) {
      // If Firebase throws (wrong password, user not found, etc.),
      // we catch it here and store a message to show in the UI.
      // We don't crash — we just update state.
      setState(() {
        _errorMessage = _friendlyError(e.toString());
      });
    } finally {
      // Always stop loading whether we succeeded or failed
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // CHANGE: _handleSignup is now async
  Future<void> _handleSignup() async {

    List<String> _validatePassword(String password) {
  final errors = <String>[];
  if (password.length < 8)
    errors.add('At least 8 characters long.');
  if (!RegExp(r'[A-Z]').hasMatch(password))
    errors.add('At least one uppercase letter (A–Z).');
  if (!RegExp(r'[a-z]').hasMatch(password))
    errors.add('At least one lowercase letter (a–z).');
  if (!RegExp(r'[0-9]').hasMatch(password))
    errors.add('At least one number (0–9).');
  if (!RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(password))
    errors.add('At least one special character (!@#\$%^&* …).');
  if(_passwordCtrl.text != _confirmCtrl.text)
  errors.add("Passwords Do Not Match");
  return errors;
}

void _showPasswordErrorPopup(List<String> errors) {
  showDialog(
    context: context,
    barrierColor: Colors.black.withOpacity(0.6),
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      child: _PasswordErrorPopup(
        errors: errors,
        onDismiss: () => Navigator.pop(context),
      ),
    ),
  );
}

      final passwordErrors = _validatePassword(_passwordCtrl.text);
  if (passwordErrors.isNotEmpty) {
    _showPasswordErrorPopup(passwordErrors);
    return;
  }

  
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await BackendService().signUp(
        _emailCtrl.text.trim(),
        _passwordCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(), 
      );

      // After signup, go straight to dashboard (new users are never admin)
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const DashboardPage()),
        );
      }
    } on Exception catch (e) {
      setState(() => _errorMessage = _friendlyError(e.toString()));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // NEW: converts raw Firebase error strings into readable messages
  // Why: Firebase exceptions contain long internal strings like
  //      "[firebase_auth/wrong-password] The password is invalid."
  //      This strips that down to something the user can actually read.
  String _friendlyError(String raw) {
    if (raw.contains('wrong-password') || raw.contains('invalid-credential')) {
      return 'Incorrect email or password.';
    } else if (raw.contains('user-not-found')) {
      return 'No account found with that email.';
    } else if (raw.contains('email-already-in-use')) {
      return 'An account with this email already exists.';
    } else if (raw.contains('weak-password')) {
      return 'Password must be at least 6 characters.';
    } else if (raw.contains('invalid-email')) {
      return 'Please enter a valid email address.';
    }
    return 'Something went wrong. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView(
            controller: _pageController,
            onPageChanged: (index) => setState(() {
              _isLogin = index == 0;
              _errorMessage = null; // clear errors on swipe
            }),
            children: [
              _LoginContent(
                // CHANGE: was usernameCtrl, now emailCtrl
                emailCtrl: _emailCtrl,
                passwordCtrl: _passwordCtrl,
                onLogin: _handleLogin,
                isLogin: _isLogin,
                onSwitch: _switchTab,
                // NEW props passed down so the button and error
                // message can react to loading/error state
                isLoading: _isLoading,
                errorMessage: _errorMessage,
              ),
              _RegisterContent(
                emailCtrl: _emailCtrl,
                phoneCtrl: _phoneCtrl,
                codeCtrl: _codeCtrl,
                passwordCtrl: _passwordCtrl,
                confirmCtrl: _confirmCtrl,
                onSignup: _handleSignup,
                isLogin: _isLogin,
                onSwitch: _switchTab,
                isLoading: _isLoading,
                errorMessage: _errorMessage,
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }
}

// ─── LOGIN CONTENT ────────────────────────────────────────────────────────────

class _LoginContent extends StatelessWidget {
  // CHANGE: usernameCtrl → emailCtrl
  final TextEditingController emailCtrl, passwordCtrl;
  final VoidCallback onLogin;
  final bool isLogin;
  final ValueChanged<bool> onSwitch;
  final bool isLoading;
  final String? errorMessage;

  const _LoginContent({
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.onLogin,
    required this.isLogin,
    required this.onSwitch,
    required this.isLoading,
    this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Stack(
        children: [
          AuthHeader(
            isLogin: true,
            image: 'assets/PLANT.jpeg',
            isLoginState: isLogin,
            onSwitch: onSwitch,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 340),
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.deepGreen.withOpacity(0.1),
                    AppColors.lightGreen.withOpacity(0.55),
                    AppColors.lightGreen.withOpacity(0.77),
                    AppColors.deepGreen,
                  ],
                  stops: const [0.01, 0.12, 0.18, 0.24],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 50),
                  SectionTitle(label: 'LOG IN'),
                  const SizedBox(height: 16),
                  // CHANGE: hint is now 'EMAIL' instead of 'USERNAME'
                  AuthField(controller: emailCtrl, hint: 'EMAIL'),
                  const SizedBox(height: 15),
                  AuthField(controller: passwordCtrl, hint: 'PASSWORD', obscure: true),
                  const SizedBox(height: 20),
                  Text('FORGOT PASSWORD ?',
                      style: AppTextStyles.mono(11, AppColors.white, weight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Container(
                    height: 2,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.cream, AppColors.creamCard],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),

                  // NEW: show error message if login failed
                  if (errorMessage != null) ...[
                    Text(
                      errorMessage!,
                      style: AppTextStyles.mono(11, Colors.redAccent, weight: FontWeight.w600),
                    ),
                    const SizedBox(height: 10),
                  ],

                  // CHANGE: button now shows spinner when loading,
                  // and is disabled (onTap becomes no-op) while request is in flight
                  LoginButton(
  label: 'LOGIN',
  onTap: onLogin,
  isLoading: isLoading,
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

// ─── LOGIN CONTENT ────────────────────────────────────────────────────────────



// ─── REGISTER CONTENT ─────────────────────────────────────────────────────────

class _RegisterContent extends StatefulWidget {
  final TextEditingController emailCtrl,phoneCtrl, codeCtrl, passwordCtrl, confirmCtrl;
  final VoidCallback onSignup;
  final bool isLogin;
  final ValueChanged<bool> onSwitch;
  final bool isLoading;
  final String? errorMessage;

  const _RegisterContent({
    required this.emailCtrl,
    required this.phoneCtrl,
    required this.codeCtrl,
    required this.passwordCtrl,
    required this.confirmCtrl,
    required this.onSignup,
    required this.isLogin,
    required this.onSwitch,
    required this.isLoading,
    this.errorMessage,
  });

  @override
  State<_RegisterContent> createState() => _RegisterContentState();

}


  class _RegisterContentState extends State<_RegisterContent> {
  bool _otpSent = false;
  bool _otpVerified = false;
  bool _sendingOtp = false;
  String? _generatedOtp;
  String? _otpError;

  // Simulated OTP send — generates a fake 6-digit code and prints to console
  Future<void> _sendOtp() async {
  final phone = widget.phoneCtrl.text.trim();
  final email = widget.emailCtrl.text.trim();

  if (phone.isEmpty) {
    setState(() => _otpError = 'Enter a phone number first.');
    return;
  }

  setState(() {
    _sendingOtp = true;
    _otpError = null;
  });

  // Check both email and phone before sending OTP
  final emailExists = email.isNotEmpty
      ? await BackendService().isEmailRegistered(email)
      : false;
  final phoneExists = await BackendService().isPhoneRegistered(phone);

  if (emailExists || phoneExists) {
    setState(() => _sendingOtp = false);
    if (mounted) {
      _showAlreadyRegisteredPopup(
        reason: emailExists ? 'email' : 'phone',
      );
    }
    return;
  }

  await Future.delayed(const Duration(seconds: 1));

  final otp = (100000 + (DateTime.now().millisecondsSinceEpoch % 900000))
      .toString()
      .substring(0, 6);
  _generatedOtp = otp;
  debugPrint('==== SIMULATED OTP: $otp ====');

  if (mounted) {
    setState(() {
      _otpSent = true;
      _sendingOtp = false;
    });
  }
}

  void _verifyOtp() {
    if (widget.codeCtrl.text.trim() == _generatedOtp) {
      setState(() {
        _otpVerified = true;
        _otpError = null;
      });
    } else {
      setState(() => _otpError = 'Incorrect code. Try again.');
    }
  }

  void _showAlreadyRegisteredPopup({required String reason}) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: _AlreadyRegisteredPopup(
          reason: reason,  
          onLogin: () {
            Navigator.pop(context);
            widget.onSwitch(true); // switch to login tab
          },
          onDismiss: () => Navigator.pop(context),
        ),
      ),
    );
  }

  

   @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        margin: const EdgeInsets.symmetric(horizontal: 7, vertical: 12),
        child: Stack(
          children: [
            // Layer 1: image header
            ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: AuthHeader(
                isLogin: false,
                image: 'assets/register bg.jpeg',
                isLoginState: widget.isLogin,
                onSwitch: widget.onSwitch,
              ),
            ),

            // Layer 2: gradient fade + email + phone fields
            Positioned(
              top: 250,
              left: 0,
              right: 0,
              child: Container(
                height: 230,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.lightGreen.withOpacity(0.75),
                      AppColors.lightGreen.withOpacity(0.9),
                      AppColors.deepGreen,
                    ],
                    stops: const [0.10, 0.20, 0.40],
                  ),
                  borderRadius: BorderRadius.circular(32),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Transform.translate(
                          offset: const Offset(-18, 0),
                          child: Container(
                            width: 40, height: 40,
                            decoration: const BoxDecoration(
                              color: Colors.black, shape: BoxShape.circle),
                          ),
                        ),
                        Expanded(child: SectionTitle(label: 'SIGN UP')),
                        Transform.translate(
                          offset: const Offset(18, 0),
                          child: Container(
                            width: 40, height: 40,
                            decoration: const BoxDecoration(
                              color: Colors.black, shape: BoxShape.circle),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    RegisterField(controller: widget.emailCtrl, hint: 'EMAIL'),
                    const SizedBox(height: 18),
                    RegisterField(controller: widget.phoneCtrl, hint: 'PHONE NUMBER'),
                  ],
                ),
              ),
            ),

            // Layer 3: deep green card with password fields + sign up button
            Padding(
              padding: const EdgeInsets.only(top: 480),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.deepGreen,
                  borderRadius: BorderRadius.circular(24),
                ),
                padding: const EdgeInsets.fromLTRB(10, 40, 10, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RegisterField(
                        controller: widget.passwordCtrl,
                        hint: 'PASSWORD',
                        obscure: true),
                    const SizedBox(height: 14),
                    RegisterField(
                        controller: widget.confirmCtrl,
                        hint: 'CONFIRM PASSWORD',
                        obscure: true),
                    const SizedBox(height: 15),

                    // OTP status indicator
                    if (_otpVerified)
                      Padding(
                        padding: const EdgeInsets.only(left: 12, bottom: 10),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle,
                                color: AppColors.lightGreen, size: 16),
                            const SizedBox(width: 6),
                            Text('Phone verified',
                                style: AppTextStyles.mono(
                                    11, Colors.greenAccent,
                                    weight: FontWeight.w600)),
                          ],
                        ),
                      ),

                    if (_otpError != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 12, bottom: 10),
                        child: Text(_otpError!,
                            style: AppTextStyles.mono(11, Colors.redAccent,
                                weight: FontWeight.w600)),
                      ),

                    if (widget.errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 12, bottom: 10),
                        child: Text(widget.errorMessage!,
                            style: AppTextStyles.mono(11, Colors.redAccent,
                                weight: FontWeight.w600)),
                      ),

                    Container(
                      height: 2,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AppColors.cream, AppColors.creamCard],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        const SizedBox(width: 8),
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 40),
                          width: 270,
                          child: LoginButton(
                          label: 'SIGN UP',
                          onTap: _otpVerified
                        ? widget.onSignup
                             : () {
                                          setState(() => _otpError =
                                              'Please verify your phone first.');
                                        },
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Layer 4: verification code field (straddles boundary)
            Positioned(
              top: 450,
              left: 24,
              right: 24,
              child: Stack(
                children: [
                  Container(
                    height: 55,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 8,
                          spreadRadius: 2,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                      child: Container(
                        height: 45,
                        margin: const EdgeInsets.symmetric(
                            horizontal: 15, vertical: 5),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: _otpVerified
                                ? Colors.greenAccent.withOpacity(0.4)
                                : Colors.black.withOpacity(0.15),
                            width: 0.8,
                          ),
                          color: Colors.white.withOpacity(0.28),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: widget.codeCtrl,
                                enabled: _otpSent && !_otpVerified,
                                keyboardType: TextInputType.number,
                                style: AppTextStyles.headline(
                                  12, Colors.black,
                                  weight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                ),
                                decoration: InputDecoration(
                                  hintText: _otpVerified
                                      ? '✓ VERIFIED'
                                      : _otpSent
                                          ? 'ENTER 6-DIGIT CODE'
                                          : 'VERIFICATION CODE',
                                  hintStyle: AppTextStyles.headline(
                                    12,
                                    _otpVerified
                                        ? Colors.greenAccent.withOpacity(0.8)
                                        : Colors.black.withOpacity(0.5),
                                    weight: FontWeight.bold,
                                    letterSpacing: 1.5,
                                  ),
                                  filled: true,
                                  fillColor: Colors.transparent,
                                  border: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 14),
                                ),
                              ),
                            ),
                            Container(
                                width: 1,
                                height: 28,
                                color: Colors.black.withOpacity(0.2)),
                            // SEND / VERIFY / VERIFIED button
                            GestureDetector(
                              onTap: _otpVerified
                                  ? null
                                  : _otpSent
                                      ? _verifyOtp
                                      : _sendOtp,
                              child: Container(
                                margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                height: 30,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: _otpVerified
                                        ? [
                                            Colors.greenAccent.withOpacity(0.4),
                                            Colors.green.withOpacity(0.4)
                                          ]
                                        : [
                                            AppColors.blushPink
                                                .withOpacity(0.7),
                                            AppColors.lightPink
                                                .withOpacity(0.7),
                                          ],
                                    stops: const [0.13, 0.54],
                                  ),
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: Center(
                                  child: _sendingOtp
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.black))
                                      : Text(
                                          _otpVerified
                                              ? 'DONE'
                                              : _otpSent
                                                  ? 'VERIFY'
                                                  : 'SEND',
                                          style: AppTextStyles.mono(
                                            10,
                                            const Color(0xFF2A0A3A),
                                            weight: FontWeight.bold,
                                            letterSpacing: 1,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ticket circles
            Positioned(
              top: 720,
              child: Row(
                children: [
                  Transform.translate(
                    offset: const Offset(-25, 0),
                    child: Container(
                      width: 60, height: 60,
                      decoration: const BoxDecoration(
                          color: Colors.black, shape: BoxShape.circle),
                    ),
                  ),
                  Transform.translate(
                    offset: const Offset(285, 0),
                    child: Container(
                      width: 60, height: 60,
                      decoration: const BoxDecoration(
                          color: Colors.black, shape: BoxShape.circle),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── AUTH HEADER ──────────────────────────────────────────────────────────────

class AuthHeader extends StatelessWidget {
  final bool isLogin;
  final String image;
  final bool isLoginState;
  final ValueChanged<bool> onSwitch;

  const AuthHeader({
    required this.isLogin,
    required this.image,
    required this.isLoginState,
    required this.onSwitch,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 400,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Image.asset(image, fit: BoxFit.cover),
          ),
          Positioned.fill(
            child: Container(color: Colors.black.withOpacity(0.15)),
          ),
          Positioned(
            top: 10,
            right: 12,
            child: _FloatingTabBar(isLogin: isLoginState, onSwitch: onSwitch),
          ),
        ],
      ),
    );
  }
}

// ─── FLOATING TAB BAR ─────────────────────────────────────────────────────────

class _FloatingTabBar extends StatefulWidget {
  final bool isLogin;
  final ValueChanged<bool> onSwitch;
  const _FloatingTabBar({required this.isLogin, required this.onSwitch});

  @override
  State<_FloatingTabBar> createState() => _FloatingTabBarState();
}

class _FloatingTabBarState extends State<_FloatingTabBar> {
  late bool _isLogin;

  @override
  void initState() {
    super.initState();
    _isLogin = !widget.isLogin;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _isLogin = widget.isLogin);
    });
  }

  @override
  void didUpdateWidget(_FloatingTabBar old) {
    super.didUpdateWidget(old);
    if (old.isLogin != widget.isLogin) {
      setState(() => _isLogin = widget.isLogin);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 18),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.all(4),
      child: SizedBox(
        width: 150,
        height: 35,
        child: Stack(
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              alignment: _isLogin ? Alignment.centerLeft : Alignment.centerRight,
              child: FractionallySizedBox(
                widthFactor: 0.5,
                child: Container(
                  height: 33,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.blushPink, AppColors.lightPink],
                      stops: [0.13, 0.54],
                    ),
                    borderRadius: BorderRadius.circular(26),
                  ),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => widget.onSwitch(true),
                    child: SizedBox(
                      height: 35,
                      child: Center(
                        child: Text('LOGIN',
                            style: AppTextStyles.mono(10,
                                _isLogin ? const Color(0xFF2A0A3A) : Colors.white.withOpacity(0.5),
                                weight: FontWeight.bold,
                                letterSpacing: 1)),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => widget.onSwitch(false),
                    child: SizedBox(
                      height: 35,
                      child: Center(
                        child: Text('SIGN UP',
                            style: AppTextStyles.mono(10,
                                !_isLogin ? const Color(0xFF2A0A3A) : Colors.white.withOpacity(0.5),
                                weight: FontWeight.bold,
                                letterSpacing: 1)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── SHARED WIDGETS ───────────────────────────────────────────────────────────

class TabButton extends StatelessWidget {
  final String label;
  final bool active;
  const TabButton({required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        gradient: active
            ? const LinearGradient(
                colors: [AppColors.blushPink, AppColors.lightPink],
                stops: [0.13, 0.54],
              )
            : null,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        label,
        style: AppTextStyles.mono(10,
            active ? const Color(0xFF2A0A3A) : Colors.white.withOpacity(0.5),
            weight: FontWeight.bold,
            letterSpacing: 1),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String label;
  const SectionTitle({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [AppColors.cream, AppColors.creamCard],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds),
          child: Text(label,
              style: AppTextStyles.headline(28, Colors.white,
                  letterSpacing: 3, weight: FontWeight.w900)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            height: 2,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.cream, AppColors.creamCard],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class AuthField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool obscure;

  const AuthField({required this.controller, required this.hint, this.obscure = false});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          height: 62,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.creamLight, AppColors.cream, AppColors.creamCard],
              stops: [0.10, 0.3, 0.7],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 6,
                  offset: const Offset(0, 3)),
            ],
          ),
        ),
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                child: TextField(
                  controller: controller,
                  obscureText: obscure,
                  style: AppTextStyles.headline(16, AppColors.black,
                          letterSpacing: 2, weight: FontWeight.w900)
                      .copyWith(fontStyle: FontStyle.italic),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: AppTextStyles.headline(16, AppColors.black.withOpacity(0.5),
                        letterSpacing: 2, weight: FontWeight.w900),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.06),
                    border: InputBorder.none,
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide:
                          BorderSide(color: AppColors.white.withOpacity(0.2), width: 1),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide:
                          BorderSide(color: AppColors.white.withOpacity(0.1), width: 1),
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class RegisterField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool obscure;

  const RegisterField({required this.controller, required this.hint, this.obscure = false});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 10),
          height: 55,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.cream, AppColors.creamCard],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 6,
                  offset: const Offset(0, 3)),
            ],
          ),
        ),
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 5),
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.12),
                        blurRadius: 8,
                        spreadRadius: 2,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                            color: Colors.black.withOpacity(0.15), width: 0.8),
                        color: Colors.white.withOpacity(0.18),
                      ),
                      child: TextField(
                        controller: controller,
                        obscureText: obscure,
                        style: AppTextStyles.headline(15, Colors.black,
                            weight: FontWeight.bold, letterSpacing: 1.5),
                        decoration: InputDecoration(
                          hintText: hint,
                          hintStyle: AppTextStyles.headline(
                              15, Colors.black.withOpacity(0.8),
                              weight: FontWeight.bold, letterSpacing: 1.5),
                          filled: true,
                          fillColor: Colors.transparent,
                          border: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 22, vertical: 12),
                        ),
                      ),
                    ),
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

class LoginButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final bool isLoading;

  const LoginButton({
    required this.label,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  State<LoginButton> createState() => _LoginButtonState();
}

class _LoginButtonState extends State<LoginButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _dotCtrl;

  @override
  void initState() {
    super.initState();
    _dotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _dotCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.isLoading ? null : widget.onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.creamLight, AppColors.cream, AppColors.creamCard],
            stops: [0.10, 0.3, 0.7],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.9),
              blurRadius: 6,
              offset: const Offset(10, 10),
            ),
          ],
        ),
        child: Center(
          child: widget.isLoading
              ? _PulsingLabel(
                  baseText: widget.label == 'LOGIN' ? 'LOGGING IN' : 'SIGNING UP',
                  controller: _dotCtrl,
                )
              : Text(
                  widget.label,
                  style: AppTextStyles.headline(
                    24,
                    AppColors.accentGreen,
                    weight: FontWeight.w900,
                    letterSpacing: 3,
                  ),
                ),
        ),
      ),
    );
  }
}

class _PulsingLabel extends AnimatedWidget {
  final String baseText;
  const _PulsingLabel({
    required this.baseText,
    required AnimationController controller,
  }) : super(listenable: controller);

  AnimationController get _ctrl => listenable as AnimationController;

  @override
  Widget build(BuildContext context) {
    // 3 dots, each offset by 1/3 of the cycle
    // opacity pulses 0.2 → 1.0 in a sine wave per dot
    final t = _ctrl.value; // 0.0 → 1.0

    final dot1 = (math.sin((t * 2 * math.pi))).clamp(0.0, 1.0);
    final dot2 = (math.sin((t * 2 * math.pi) - (math.pi / 1.5))).clamp(0.0, 1.0);
    final dot3 = (math.sin((t * 2 * math.pi) - (math.pi / 0.75))).clamp(0.0, 1.0);

    Widget dot(double opacity) => Opacity(
          opacity: opacity.clamp(0.2, 1.0),
          child: Text(
            '.',
            style: AppTextStyles.headline(
              28,
              AppColors.accentGreen,
              weight: FontWeight.w900,
            ),
          ),
        );

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          baseText,
          style: AppTextStyles.headline(
            22,
            AppColors.accentGreen,
            weight: FontWeight.w900,
            letterSpacing: 3,
          ),
        ),
        const SizedBox(width: 2),
        dot(dot1),
        dot(dot2),
        dot(dot3),
      ],
    );
  }
}

class _AlreadyRegisteredPopup extends StatelessWidget {
  final VoidCallback onLogin;
  final VoidCallback onDismiss;
  final String reason;

  const _AlreadyRegisteredPopup({
    required this.onLogin,
    required this.onDismiss,
    required this.reason,
  });

  @override
  Widget build(BuildContext context) {
    final bodyText = reason == 'email'
        ? 'This email address is already\nlinked to a GrowWiser account.'
        : 'This phone number is already\nlinked to a GrowWiser account.';
    return Container(
      width: 300,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      decoration: BoxDecoration(
        color:AppColors.deepGreen,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.blushPink.withOpacity(0.25)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // icon circle
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.blushPink.withOpacity(0.12),
              border: Border.all(
                  color: AppColors.blushPink.withOpacity(0.4), width: 1.5),
            ),
            child: const Icon(Icons.person_off_outlined,
                color: AppColors.blushPink, size: 24),
          ),
          const SizedBox(height: 14),

          // tag
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.blushPink.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: AppColors.blushPink.withOpacity(0.2)),
            ),
            child: Text('ACCOUNT EXISTS',
                style: AppTextStyles.mono(10, AppColors.blushPink,
                    weight: FontWeight.w700, letterSpacing: 1)),
          ),
          const SizedBox(height: 12),

          Text('Already Registered',
              style: AppTextStyles.headline(17, AppColors.lightPink,
                  weight: FontWeight.w900, letterSpacing: 1.5)),
          const SizedBox(height: 8),

          Text(
  bodyText,
  textAlign: TextAlign.center,
  style: AppTextStyles.mono(12,
      AppColors.lightPink.withOpacity(0.6),
      weight: FontWeight.w500),
),
          const SizedBox(height: 18),

          // divider
          Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                Colors.transparent,
                AppColors.blushPink.withOpacity(0.3),
                Colors.transparent,
              ]),
            ),
          ),
          const SizedBox(height: 18),

          // login button
          GestureDetector(
            onTap: onLogin,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.blushPink, AppColors.lightPink],
                  stops: [0.13, 0.54],
                ),
                borderRadius: BorderRadius.circular(32),
              ),
              child: Center(
                child: Text('LOG IN INSTEAD',
                    style: AppTextStyles.mono(12,
                        const Color(0xFF10231E),
                        weight: FontWeight.w800, letterSpacing: 2)),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // dismiss button
          GestureDetector(
            onTap: onDismiss,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                    color: AppColors.blushPink.withOpacity(0.3)),
              ),
              child: Center(
                child: Text('USE DIFFERENT EMAIL',
                    style: AppTextStyles.mono(11,
                        AppColors.lightPink.withOpacity(0.7),
                        weight: FontWeight.w600, letterSpacing: 1.5)),
              ),
            ),
          ),
        ],
      ),
    );
  }

}

class _PasswordErrorPopup extends StatelessWidget {
  final List<String> errors;
  final VoidCallback onDismiss;

  const _PasswordErrorPopup({
    required this.errors,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      decoration: BoxDecoration(
        color: AppColors.deepGreen,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.blushPink.withOpacity(0.25)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // icon circle
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.blushPink.withOpacity(0.12),
              border: Border.all(
                  color: AppColors.blushPink.withOpacity(0.4), width: 1.5),
            ),
            child: const Icon(Icons.lock_outline,
                color: AppColors.blushPink, size: 24),
          ),
          const SizedBox(height: 14),

          // tag
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.blushPink.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.blushPink.withOpacity(0.2)),
            ),
            child: Text('INVALID PASSWORD',
                style: AppTextStyles.mono(10, AppColors.blushPink,
                    weight: FontWeight.w700, letterSpacing: 1)),
          ),
          const SizedBox(height: 12),

          Text('Password Requirements',
              style: AppTextStyles.headline(17, AppColors.lightPink,
                  weight: FontWeight.w900, letterSpacing: 1.5)),
          const SizedBox(height: 14),

          // error rows
          ...errors.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.cancel_outlined,
                    color: AppColors.blushPink, size: 14),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(e,
                      style: AppTextStyles.mono(11,
                          AppColors.lightPink.withOpacity(0.75),
                          weight: FontWeight.w500)),
                ),
              ],
            ),
          )),

          const SizedBox(height: 10),

          // divider
          Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                Colors.transparent,
                AppColors.blushPink.withOpacity(0.3),
                Colors.transparent,
              ]),
            ),
          ),
          const SizedBox(height: 18),

          // dismiss button
          GestureDetector(
            onTap: onDismiss,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.blushPink, AppColors.lightPink],
                  stops: [0.13, 0.54],
                ),
                borderRadius: BorderRadius.circular(32),
              ),
              child: Center(
                child: Text('GOT IT',
                    style: AppTextStyles.mono(12, const Color(0xFF10231E),
                        weight: FontWeight.w800, letterSpacing: 2)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}