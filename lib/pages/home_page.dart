import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';


class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  double _slideX = 0;
  final double _knobSize = 46;

  void _onSlideUpdate(DragUpdateDetails d, double maxSlide) {
  setState(() {
    _slideX = (_slideX + d.delta.dx).clamp(0.0, maxSlide);
  });
}

  void _onSlideEnd(DragEndDetails d, double maxSlide) {
  if (_slideX >= maxSlide * 0.72) {
    Navigator.pushReplacementNamed(
      context,
       '/continue'
    );
  } else {
    setState(() => _slideX = 0);
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0a1a0a),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Layer 1: Background image ──────────────────────────────────
          Image.asset(
            'assets/land.jpg',
            fit: BoxFit.cover,
          ),

          // ── Layer 2: Dark gradient overlay ────────────────────────────
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x44000000),
                  Color(0x22000000),
                  Color(0x99000000),
                  Color(0xF2000000),
                ],
                stops: [0.0, 0.25, 0.6, 1.0],
              ),
            ),
          ),

          // ── Layer 3: Content ──────────────────────────────────────────
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Logo image 
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 28, 22, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // ── Logo image ───────────────────────────────
                        Image.asset(
                          'assets/logo_yellowfont.png', 
                          width: 400,
                          fit: BoxFit.contain,
                          alignment: Alignment.topLeft,
                        ),

                        const SizedBox(height: 12),

                        Padding(
                          padding: const EdgeInsets.fromLTRB(20,5,20,0),
                          child:
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        
                        children :[
                         

                        
                        Text(
                           textAlign:TextAlign.center,
                          'SOIL MOISTURE AND TEMPERATURE BASED\nSMART IRRIGATION SYSTEM',
                          style: AppTextStyles.mono(
                            12,
                            const Color(0xFFE4F27A),
                            letterSpacing: 1.5,
                            weight: FontWeight.w500,
                           
                            
                          ),
                        ),
                        ],
                        ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Bottom CTA ─────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 36),
                  child: Column(
                    children: [
                     
                      Container(
                        
                        width: 480,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 22, vertical: 15),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                AppColors.lightPink.withOpacity(0.7),
                AppColors.deepGreen,
              ],
              stops: [0.11,0.75],
            ),
                          borderRadius: BorderRadius.circular(50),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.22),
                            width: 1,
                          ),
                        ),
                        
                        child: Text(
                          textAlign: TextAlign.center,
                          'SET IT , FORGET IT , GROW IT',
                          style: AppTextStyles.mono(
                            13,
                            const Color(0xFFE4F27A),
                            letterSpacing: 4,
                            weight: FontWeight.w800,
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),

                      // Glassmorphism card
                      ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                          child: Container(
                            width: double.infinity,
                            padding:
                                const EdgeInsets.fromLTRB(20, 18, 20, 20),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.09),
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.16),
                                width: 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  'GrowWiser, A Smart Irrigation Solution',
                                  style: TextStyle(
                                    fontFamily: AppTextStyles.erode,
                                    fontSize: 16,
                                    fontStyle: FontStyle.italic,
                                    color: Colors.white.withOpacity(0.8),
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                _SlideToStart(
                                  slideX: _slideX,
                                  knobSize: _knobSize,
                                  onUpdate: _onSlideUpdate,
                                  onEnd: _onSlideEnd,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Slide To Start ─────────────────────────────────────────────────────────────

class _SlideToStart extends StatelessWidget {
  final double slideX;
  final double knobSize;
  final void Function(DragUpdateDetails, double maxSlide) onUpdate;
  final void Function(DragEndDetails, double maxSlide) onEnd;

  const _SlideToStart({
    required this.slideX,
    required this.knobSize,
    required this.onUpdate,
    required this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {

        final maxSlide = constraints.maxWidth - knobSize - 10;

        return Container(
          height: 56,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(50),
            border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              // Progress fill
              Positioned(
                left: 5,
                child: Container(
                  width: (slideX + knobSize).clamp(knobSize, maxSlide + knobSize),
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4E870).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(50),
                  ),
                ),
              ),

              // Label
              Center(
                child: Opacity(
                  opacity: (1.0 - (slideX / (maxSlide * 0.5))).clamp(0.0, 1.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.arrow_forward,
                          color: Colors.white.withOpacity(0.7), size: 14),
                      const SizedBox(width: 8),
                      Text(
                        'SLIDE TO GET STARTED',
                        style: AppTextStyles.mono(
                          11,
                          Colors.white.withOpacity(0.75),
                          letterSpacing: 1.5,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              
              Positioned(
                left: 5 + slideX.clamp(0.0, maxSlide),
                child: GestureDetector(
                  onHorizontalDragUpdate: (d) => onUpdate(d, maxSlide),
                  onHorizontalDragEnd: (d) => onEnd(d, maxSlide),
                  child: Container(
                    width: knobSize,
                    height: knobSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFE4F27A),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFD4E870).withOpacity(0.45),
                          blurRadius: 14,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.arrow_forward,
                      color: Color(0xFF0a1a0a),
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}