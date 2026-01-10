import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'home_screen.dart';

class WelcomeWrapper extends StatefulWidget {
  const WelcomeWrapper({super.key});

  @override
  State<WelcomeWrapper> createState() => _WelcomeWrapperState();
}

class _WelcomeWrapperState extends State<WelcomeWrapper> {
  final PageController _pageController = PageController();
  Timer? _autoSlideTimer;

  // Purple color constant
  static const Color purpleColor = Color(0xFFBEA1F7);
  static const Color yellowColor = Color(0xFFFFD700); // Bright yellow for logo

  @override
  void initState() {
    super.initState();
    // Auto-slide to second screen after 2 seconds
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
        children: [
          _buildOpeningScreen(),
          _buildWelcomeScreen(),
        ],
      ),
    );
  }

  Widget _buildLogo({double fontSize = 48}) {
    // Orange-yellow color for the blocks (slightly darker than main yellow)
    const Color blockColor = Color(0xFFFFB800);
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'S',
          style: GoogleFonts.inter(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            color: yellowColor,
          ),
        ),
        Text(
          't',
          style: GoogleFonts.inter(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            color: yellowColor,
          ),
        ),
        // "u" as stacked blocks
        SizedBox(
          width: fontSize * 0.35,
          height: fontSize * 0.65,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: fontSize * 0.35,
                height: fontSize * 0.28,
                decoration: BoxDecoration(
                  color: blockColor,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              SizedBox(height: fontSize * 0.04),
              Container(
                width: fontSize * 0.35,
                height: fontSize * 0.28,
                decoration: BoxDecoration(
                  color: blockColor,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ],
          ),
        ),
        // "d" as stacked blocks
        SizedBox(
          width: fontSize * 0.35,
          height: fontSize * 0.65,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: fontSize * 0.35,
                height: fontSize * 0.28,
                decoration: BoxDecoration(
                  color: blockColor,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              SizedBox(height: fontSize * 0.04),
              Container(
                width: fontSize * 0.35,
                height: fontSize * 0.28,
                decoration: BoxDecoration(
                  color: blockColor,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ],
          ),
        ),
        Text(
          'y',
          style: GoogleFonts.inter(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            color: yellowColor,
          ),
        ),
        Text(
          'S',
          style: GoogleFonts.inter(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            color: yellowColor,
          ),
        ),
        Text(
          'p',
          style: GoogleFonts.inter(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            color: yellowColor,
          ),
        ),
        Text(
          'o',
          style: GoogleFonts.inter(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            color: yellowColor,
          ),
        ),
        Text(
          't',
          style: GoogleFonts.inter(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            color: yellowColor,
          ),
        ),
      ],
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
              // Logo with styled "StudySpot"
              _buildLogo(fontSize: 48),
              const SizedBox(height: 16),
              // Tagline
              Text(
                'Find your spot. Focus together',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  color: purpleColor,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 60),
              // Swipe up text
              Text(
                'Swipe up',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 8),
              Icon(
                Icons.keyboard_arrow_up,
                color: Colors.grey[600],
                size: 24,
              ),
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
              // Logo and Tagline at the top
              _buildLogo(fontSize: 36),
              const SizedBox(height: 12),
              Text(
                'Find your spot. Focus together',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: purpleColor,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const Spacer(),
              // Welcome message
              Text(
                'Welcome to StudySpot!',
                style: GoogleFonts.inter(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 60),
              // Login button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (context) => const HomeScreen()),
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
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // "or" separator
              Text(
                'or',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: Colors.grey[400],
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 24),
              // Create account link
              GestureDetector(
                onTap: () {
                  // Handle create account navigation
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (context) => const HomeScreen()),
                  );
                },
                child: Text(
                  'Create an account',
                  style: GoogleFonts.inter(
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
