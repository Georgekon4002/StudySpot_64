import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
// Πρέπει να υπάρχουν αυτά τα αρχεία στον φάκελο screens
import 'login_screen.dart';
import 'signup_step1_screen.dart';

class WelcomeWrapper extends StatefulWidget {
  const WelcomeWrapper({super.key});

  @override
  State<WelcomeWrapper> createState() => _WelcomeWrapperState();
}

class _WelcomeWrapperState extends State<WelcomeWrapper> {
  final PageController _pageController = PageController();
  Timer? _autoSlideTimer;

  static const Color purpleColor = Color(0xFFBEA1F7);

  @override
  void initState() {
    super.initState();
    _autoSlideTimer = Timer(const Duration(seconds: 2), () {
      if (_pageController.hasClients) {
        _pageController.animateToPage(
          1,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _autoSlideTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: PageView(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        physics: const ClampingScrollPhysics(), // Prevent overscroll
        children: [_buildOpeningScreen(), _buildWelcomeScreen()],
      ),
    );
  }

  Widget _buildLogo({double? width, double? height}) {
    return Image.asset(
      'AppIcons/intro.png',
      width: width,
      height: height,
      fit: BoxFit.contain,
    );
  }

  Widget _buildOpeningScreen() {
    return Container(
      color: Colors.white,
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLogo(width: 350),
              const SizedBox(height: 60),
              Text(
                'Swipe up',
                style: GoogleFonts.alata(
                  fontSize: 14,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 8),
              Icon(Icons.keyboard_arrow_up, color: Colors.grey[600], size: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeScreen() {
    return Container(
      color: Colors.white,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            children: [
              const SizedBox(height: 80),
              _buildLogo(width: 280),
              const Spacer(),
              Text(
                'Welcome to StudySpot!',
                style: GoogleFonts.alata(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 60),

              // Login Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const LoginScreen(),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: purpleColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Login',
                    style: GoogleFonts.alata(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),
              Text(
                'or',
                style: GoogleFonts.alata(fontSize: 14, color: Colors.grey[400]),
              ),
              const SizedBox(height: 24),

              // Create account link
              GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const SignupStep1Screen(),
                    ),
                  );
                },
                child: Text(
                  'Create an account',
                  style: GoogleFonts.alata(
                    fontSize: 16,
                    color: purpleColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
