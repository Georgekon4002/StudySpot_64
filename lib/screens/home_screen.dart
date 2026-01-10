import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'qr_scan_screen.dart';
import 'welcome_screen.dart';

// Seat states: null = empty, true = occupied, 'reserved' = reserved by user
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  int occupiedSpots = 38;
  int totalSpots = 60;
  int? queueNumber; // null = not in queue, number = position in queue
  int totalQueueSize = 0; // Total people in queue
  bool _isSeated = false; // Track if user has reserved a seat
  DateTime? _reservationStartTime; // When user reserved the seat
  int? _reservedSpotIndex; // Which spot user reserved
  int? _reservedSeatIndex; // Which seat user reserved
  Timer? _reservationTimer; // Timer for 30-minute reservation

  // Color constants
  static const Color orangeColor = Color(0xFFFF7B00);
  static const Color beigeColor = Color(0xFFFFECC9);

  // Sample data for study spots (15 spots, each with 4 seats)
  // null = empty, true = occupied, 'reserved' = reserved by user
  List<List<dynamic>> studySpots = [
    [true, true, true, null], // Spot 1 - 3 occupied
    [true, true, true, null], // Spot 2 - 3 occupied
    [true, null, null, null], // Spot 3 - 1 occupied
    [null, null, true, true], // Spot 4 - 2 occupied
    [true, true, true, true], // Spot 5 - 4 occupied
    [true, true, true, true], // Spot 6 - 4 occupied
    [true, null, true, null], // Spot 7 - 2 occupied
    [null, null, null, null], // Spot 8 - 0 occupied
    [null, null, true, true], // Spot 9 - 2 occupied
    [true, true, true, null], // Spot 10 - 3 occupied
    [true, true, true, true], // Spot 11 - 4 occupied
    [null, true, null, true], // Spot 12 - 2 occupied
    [true, true, true, true], // Spot 13 - 4 occupied
    [null, null, true, true], // Spot 14 - 2 occupied
    [true, null, true, null], // Spot 15 - 2 occupied
    // Total: 3+3+1+2+4+4+2+0+2+3+4+2+4+2+2 = 38 occupied
  ];

  Timer? _queueTimer;

  @override
  void initState() {
    super.initState();
    _startQueueTimer();
  }

  @override
  void dispose() {
    _queueTimer?.cancel();
    _reservationTimer?.cancel();
    super.dispose();
  }

  void _startQueueTimer() {
    _queueTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (queueNumber != null &&
          queueNumber! > 1 &&
          occupiedSpots == totalSpots) {
        // Simulate someone ahead in queue getting a seat
        setState(() {
          queueNumber = queueNumber! - 1;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('study_spots')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text("Error loading spots"));
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          // Initialize dummy data if empty
          if (docs.isEmpty) {
            _initializeDummyData();
            return const Center(child: CircularProgressIndicator());
          }

          // Parse Firestore data
          int currentOccupied = 0;
          Map<int, List<dynamic>> tempSpots = {};

          for (var doc in docs) {
            final header = doc.id;
            if (header.startsWith('spot_')) {
              final index = int.tryParse(header.split('_')[1]) ?? 0;
              final spotIndex = index - 1;
              if (spotIndex >= 0 && spotIndex < 15) {
                final data = doc.data() as Map<String, dynamic>;
                final seatsMap = data['seats'] as Map<String, dynamic>? ?? {};

                final List<dynamic> seatList = List.generate(4, (i) {
                  final letter = ['A', 'B', 'C', 'D'][i];
                  if (seatsMap.containsKey(letter)) {
                    final status = seatsMap[letter];
                    if (status != null) currentOccupied++;
                    return status == 'occupied' ? true : status;
                  }
                  return null;
                });
                tempSpots[spotIndex] = seatList;
              }
            }
          }

          studySpots = List.generate(
            15,
            (i) => tempSpots[i] ?? [null, null, null, null],
          );
          occupiedSpots = currentOccupied;

          final progress = occupiedSpots / totalSpots;

          return SafeArea(
            child: Column(
              children: [
                // Header Section
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // App Name with colored "Spot"
                      RichText(
                        text: TextSpan(
                          style: GoogleFonts.inter(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                          children: [
                            const TextSpan(text: 'Study'),
                            TextSpan(
                              text: 'Spot',
                              style: GoogleFonts.inter(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: orangeColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Profile Picture
                      GestureDetector(
                        onTap: () {
                          FirebaseAuth.instance.signOut().then((_) {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (context) => const WelcomeWrapper(),
                              ),
                            );
                          });
                        },
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.grey[300],
                            border: Border.all(
                              color: Colors.grey[400]!,
                              width: 1,
                            ),
                          ),
                          child: Icon(
                            Icons.logout,
                            color: Colors.grey[600],
                            size: 24,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Progress and Count Section
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      // Circular Progress Indicator
                      SizedBox(
                        width: 60,
                        height: 60,
                        child: Stack(
                          children: [
                            // Background circle
                            CircularProgressIndicator(
                              value: 1.0,
                              strokeWidth: 6,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                beigeColor,
                              ),
                              backgroundColor: Colors.transparent,
                            ),
                            // Progress arc
                            CircularProgressIndicator(
                              value: progress,
                              strokeWidth: 6,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                orangeColor,
                              ),
                              backgroundColor: Colors.transparent,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Count Text
                      Text(
                        '$occupiedSpots/$totalSpots',
                        style: GoogleFonts.inter(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      const Spacer(),
                      // Queue or Enqueue Button
                      if (occupiedSpots == totalSpots)
                        queueNumber != null
                            ? Text(
                                'Queue No.: $queueNumber',
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black,
                                ),
                              )
                            : ElevatedButton(
                                onPressed: _enqueueUser,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: orangeColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: Text(
                                  'Scan to Enqueue',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Study Spots Grid
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    child: GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.85,
                          ),
                      itemCount: studySpots.length,
                      padding: const EdgeInsets.only(bottom: 100),
                      itemBuilder: (context, index) {
                        return _buildStudySpotCard(
                          index + 1,
                          studySpots[index],
                        );
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
      // Floating Action Button (always visible, transparent background)
      floatingActionButton: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: FloatingActionButton(
          onPressed: () {
            // Show menu if there are available seats OR user is seated
            if (_hasAvailableSeats() || _isSeated) {
              _showFabMenu();
            }
          },
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: orangeColor,
            ),
            child: const Icon(Icons.add, color: Colors.white),
          ),
        ),
      ),
      // Bottom Navigation Bar
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.grey[100],
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(Icons.home, 'Home', 0, true),
                _buildNavItem(Icons.chat_bubble_outline, 'Chat', 1, false),
                _buildNavItem(Icons.article_outlined, 'News', 2, false),
                _buildNavItem(Icons.person_outline, 'Profile', 3, false),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStudySpotCard(int spotNumber, List<dynamic> seats) {
    final spotIndex = spotNumber - 1; // Convert back to 0-based index
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            color: beigeColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey[300]!, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              physics: const NeverScrollableScrollPhysics(),
              children: List.generate(4, (seatIndex) {
                final seatState = seats[seatIndex];
                return _buildSeat(spotIndex, seatIndex, seatState);
              }),
            ),
          ),
        ),
        // Table number at lower center
        Positioned(
          bottom: 4,
          left: 0,
          right: 0,
          child: Center(
            child: Text(
              '#$spotNumber',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSeat(int spotIndex, int seatIndex, dynamic seatState) {
    final isOccupied = seatState == true;
    final isEmpty = seatState == null;
    final isReserved = seatState == 'reserved';

    Widget seatWidget;
    if (isOccupied) {
      seatWidget = Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.grey[800],
        ),
        child: const Icon(Icons.person, color: Colors.white, size: 16),
      );
    } else if (isReserved) {
      // Reserved by user - show profile pic with countdown timer
      final isUserReserved =
          _reservedSpotIndex == spotIndex && _reservedSeatIndex == seatIndex;
      if (isUserReserved && _reservationStartTime != null) {
        final now = DateTime.now();
        final elapsed = now.difference(_reservationStartTime!);
        final remaining = const Duration(minutes: 30) - elapsed;
        final progress = remaining.inSeconds / (30 * 60);

        seatWidget = SizedBox(
          width: 32,
          height: 32,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Red progress circle
              SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  strokeWidth: 3,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
                  backgroundColor: Colors.red.withOpacity(0.2),
                ),
              ),
              // Profile picture
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: orangeColor,
                  border: Border.all(color: Colors.white, width: 1),
                ),
                child: const Icon(Icons.person, color: Colors.white, size: 14),
              ),
            ],
          ),
        );
      } else {
        seatWidget = Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(shape: BoxShape.circle, color: orangeColor),
          child: const Icon(Icons.person, color: Colors.white, size: 16),
        );
      }
    } else {
      seatWidget = Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: orangeColor,
            width: 2,
            style: BorderStyle.solid,
          ),
        ),
      );
    }

    // Only allow interaction if seat is empty AND user is not already seated
    if (isEmpty && !_isSeated) {
      return GestureDetector(
        onTapDown: (TapDownDetails details) => _showReserveMenu(
          context,
          details.globalPosition,
          spotIndex,
          seatIndex,
        ),
        behavior: HitTestBehavior.opaque,
        child: Center(child: seatWidget),
      );
    } else {
      // Locked state - show with reduced opacity if user is seated and this seat is empty
      return Center(
        child: Opacity(
          opacity: (isEmpty && _isSeated) ? 0.5 : 1.0,
          child: seatWidget,
        ),
      );
    }
  }

  void _showReserveMenu(
    BuildContext context,
    Offset position,
    int spotIndex,
    int seatIndex,
  ) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Rect.fromLTWH(0, 0, overlay.size.width, overlay.size.height),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        PopupMenuItem(
          padding: EdgeInsets.zero,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                Navigator.of(context).pop();
                _reserveSeat(spotIndex, seatIndex);
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock, color: Colors.black, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Reserve',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _enqueueUser() {
    setState(() {
      totalQueueSize++;
      queueNumber = totalQueueSize;
    });
  }

  void _reserveSeat(int spotIndex, int seatIndex) {
    setState(() {
      studySpots[spotIndex][seatIndex] = 'reserved';
      occupiedSpots++;
      _isSeated = true; // Mark user as seated
      _reservedSpotIndex = spotIndex;
      _reservedSeatIndex = seatIndex;
      _reservationStartTime = DateTime.now();

      // If user was in queue and reserved a seat, remove from queue
      if (queueNumber != null) {
        queueNumber = null;
        totalQueueSize = totalQueueSize > 0 ? totalQueueSize - 1 : 0;
      }
    });

    // Start 30-minute timer
    _reservationTimer?.cancel();
    _reservationTimer = Timer(const Duration(minutes: 30), () {
      if (mounted) {
        // Timer expired - release the seat
        setState(() {
          if (_reservedSpotIndex != null && _reservedSeatIndex != null) {
            studySpots[_reservedSpotIndex!][_reservedSeatIndex!] = null;
            occupiedSpots = occupiedSpots > 0 ? occupiedSpots - 1 : 0;
          }
          _isSeated = false;
          _reservedSpotIndex = null;
          _reservedSeatIndex = null;
          _reservationStartTime = null;
        });
      }
    });

    // Update UI every second for countdown
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || !_isSeated || _reservationStartTime == null) {
        timer.cancel();
        return;
      }
      final elapsed = DateTime.now().difference(_reservationStartTime!);
      if (elapsed >= const Duration(minutes: 30)) {
        timer.cancel();
        return;
      }
      setState(() {}); // Trigger rebuild for countdown
    });
  }

  bool _hasAvailableSeats() {
    for (var spot in studySpots) {
      for (var seat in spot) {
        if (seat == null) {
          return true;
        }
      }
    }
    return false;
  }

  void _showFabMenu() {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final Size screenSize = MediaQuery.of(context).size;
    final double bottomNavHeight = 80; // Approximate bottom nav height
    final double fabSize = 56; // Standard FAB size
    final double fabPadding = 16; // Standard FAB padding from edges

    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(
          screenSize.width - 200, // Position menu to the left of FAB area
          screenSize.height -
              bottomNavHeight -
              fabSize -
              fabPadding -
              120, // Position above FAB
          0,
          0,
        ),
        Rect.fromLTWH(0, 0, overlay.size.width, overlay.size.height),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 8,
      items: [
        PopupMenuItem(
          padding: EdgeInsets.zero,
          enabled: !_isSeated, // Disable when seated
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: !_isSeated
                  ? () {
                      Navigator.of(context).pop();
                      _openQRScanner();
                    }
                  : null,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.qr_code_scanner,
                      color: !_isSeated ? Colors.grey[800] : Colors.grey[400],
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Scan QR',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: !_isSeated ? Colors.black : Colors.grey[400],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        PopupMenuItem(
          padding: EdgeInsets.zero,
          enabled: _isSeated, // Enable when seated
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _isSeated
                  ? () {
                      Navigator.of(context).pop();
                      _showLeaveDialog();
                    }
                  : null,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.logout,
                      color: _isSeated ? Colors.grey[800] : Colors.grey[400],
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Leave',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: _isSeated ? Colors.black : Colors.grey[400],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showLeaveDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: beigeColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'See you later! 👋',
                  style: GoogleFonts.inter(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'Your seat is now free for someone else who needs to focus 😊',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _leaveSeat();
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                    child: Text(
                      'Back to Map',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: orangeColor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _leaveSeat() {
    // Cancel reservation timer
    _reservationTimer?.cancel();

    // Find and remove reserved seat
    if (_reservedSpotIndex != null && _reservedSeatIndex != null) {
      setState(() {
        studySpots[_reservedSpotIndex!][_reservedSeatIndex!] = null;
        occupiedSpots = occupiedSpots > 0 ? occupiedSpots - 1 : 0;
        _isSeated = false;
        _reservedSpotIndex = null;
        _reservedSeatIndex = null;
        _reservationStartTime = null;
      });

      // Update Firestore
      _updateSeatStatusFirestore(
        _reservedSpotIndex!,
        _reservedSeatIndex!,
        null,
      );
    }
  }

  // Parse QR code to get spot and seat indices
  // QR code format: "{tableNumber}{seatLetter}" e.g., "1A", "15D"
  Map<String, int>? _parseQRCode(String qrCode) {
    // Regex to match 1-15 followed by A-D
    final RegExp regex = RegExp(r'^([1-9]|1[0-5])([A-D])$');
    final match = regex.firstMatch(qrCode);

    if (match != null) {
      final tableStr = match.group(1)!;
      final seatStr = match.group(2)!;

      final tableNum = int.parse(tableStr);
      final spotIndex = tableNum - 1; // 0-based index

      int seatIndex;
      switch (seatStr) {
        case 'A':
          seatIndex = 0;
          break;
        case 'B':
          seatIndex = 1;
          break;
        case 'C':
          seatIndex = 2;
          break;
        case 'D':
          seatIndex = 3;
          break;
        default:
          return null;
      }

      return {'spotIndex': spotIndex, 'seatIndex': seatIndex};
    }
    return null;
  }

  void _openQRScanner() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (context) => const QRScanScreen()),
    );

    if (result != null) {
      _handleQRScan(result);
    }
  }

  Future<void> _handleQRScan(String qrCode) async {
    final parsed = _parseQRCode(qrCode);
    if (parsed == null) {
      // Invalid QR code format
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid QR code format. Use e.g. 1A, 15C'),
        ),
      );
      return;
    }

    final spotIndex = parsed['spotIndex']!;
    final seatIndex = parsed['seatIndex']!;

    // Validate indices (double check)
    if (spotIndex < 0 ||
        spotIndex >= studySpots.length ||
        seatIndex < 0 ||
        seatIndex >= 4) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invalid seat location')));
      return;
    }

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    // Check Firestore
    final isTaken = await _checkSeatAvailabilityFirestore(spotIndex, seatIndex);

    // Pop loading
    if (mounted) Navigator.of(context).pop();

    if (isTaken) {
      _showSeatTakenDialog();
    } else {
      // Also check local state just in case, though Firestore is authority
      // For this demo, we assume if Firestore says free, we can try to take it.
      // We will confirm locally.
      _showSeatFreeDialog(spotIndex, seatIndex);
    }
  }

  Future<bool> _checkSeatAvailabilityFirestore(
    int spotIndex,
    int seatIndex,
  ) async {
    try {
      final docId = 'spot_${spotIndex + 1}';
      final docSnapshot = await FirebaseFirestore.instance
          .collection('study_spots')
          .doc(docId)
          .get();

      if (docSnapshot.exists) {
        final data = docSnapshot.data();
        if (data != null && data['seats'] != null) {
          final seats = data['seats'] as Map<String, dynamic>;
          final seatLetter = ['A', 'B', 'C', 'D'][seatIndex];
          // If the key exists and is not null, it's taken
          return seats[seatLetter] != null;
        }
      }
      return false; // Document doesn't exist or seat not listed -> Free
    } catch (e) {
      print('Firestore error: $e');
      // If error, fail safe to "taken" or handle gracefully.
      // For now, let's assume if we can't check, we shouldn't allow reservation?
      // Or allow it and sync later. Let's return false (free) to not block user in demo.
      return false;
    }
  }

  void _showSeatFreeDialog(int spotIndex, int seatIndex) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: beigeColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Seat is free! 🥳',
                  style: GoogleFonts.inter(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'You want to sit here to focus and study?',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _confirmSeatOccupancy(spotIndex, seatIndex);
                      },
                      child: Text(
                        'Accept',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: orangeColor,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      child: Text(
                        'Decline',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: orangeColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSeatTakenDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: beigeColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Seat is taken 💦',
                  style: GoogleFonts.inter(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'Unfortunately this seat is already taken. You can find which seat is free on the map.',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: Text(
                      'Back to Map',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: orangeColor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _confirmSeatOccupancy(int spotIndex, int seatIndex) {
    // If user had a reserved seat, release it
    if (_isSeated && _reservedSpotIndex != null && _reservedSeatIndex != null) {
      studySpots[_reservedSpotIndex!][_reservedSeatIndex!] = null;
      _reservationTimer?.cancel();
    }

    setState(() {
      // Mark seat as occupied
      studySpots[spotIndex][seatIndex] = true;
      occupiedSpots++;

      // Update user status
      _isSeated = true;
      _reservedSpotIndex = spotIndex;
      _reservedSeatIndex = seatIndex;
      _reservationStartTime = DateTime.now();
    });

    // Update Firestore
    _updateSeatStatusFirestore(spotIndex, seatIndex, 'occupied');

    // Start 30-minute timer for the new seat
    _reservationTimer?.cancel();
    _reservationTimer = Timer(const Duration(minutes: 30), () {
      if (mounted) {
        setState(() {
          if (_reservedSpotIndex != null && _reservedSeatIndex != null) {
            studySpots[_reservedSpotIndex!][_reservedSeatIndex!] = null;
            occupiedSpots = occupiedSpots > 0 ? occupiedSpots - 1 : 0;
          }
          _isSeated = false;
          _reservedSpotIndex = null;
          _reservedSeatIndex = null;
          _reservationStartTime = null;
        });
      }
    });

    // Update UI every second for countdown
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || !_isSeated || _reservationStartTime == null) {
        timer.cancel();
        return;
      }
      final elapsed = DateTime.now().difference(_reservationStartTime!);
      if (elapsed >= const Duration(minutes: 30)) {
        timer.cancel();
        return;
      }
      setState(() {}); // Trigger rebuild for countdown
    });
  }

  Future<void> _updateSeatStatusFirestore(
    int spotIndex,
    int seatIndex,
    String? status,
  ) async {
    try {
      final docId = 'spot_${spotIndex + 1}';
      final seatLetter = ['A', 'B', 'C', 'D'][seatIndex];

      await FirebaseFirestore.instance.collection('study_spots').doc(docId).set(
        {
          'seats': {seatLetter: status},
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      print('Error updating Firestore: $e');
    }
  }

  Future<void> _initializeDummyData() async {
    final firestore = FirebaseFirestore.instance;
    final batch = firestore.batch();

    // Create 15 spots
    for (int i = 1; i <= 15; i++) {
      final docRef = firestore.collection('study_spots').doc('spot_$i');

      // Randomly occupy some seats for realistic dummy data
      // For this user request "needed some dummy data"
      Map<String, String?> seats = {
        'A': (i % 2 == 0) ? 'occupied' : null,
        'B': (i % 3 == 0) ? 'occupied' : null,
        'C': null,
        'D': (i > 10) ? 'occupied' : null,
      };

      batch.set(docRef, {'seats': seats});
    }

    try {
      await batch.commit();
    } catch (e) {
      print('Error initializing dummy data: $e');
    }
  }

  Widget _buildNavItem(IconData icon, String label, int index, bool isHome) {
    final isSelected = _selectedIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedIndex = index;
        });
        if (index != 0) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('$label tapped')));
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? orangeColor.withOpacity(0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? orangeColor : Colors.grey[600],
              size: 24,
            ),
            if (isHome)
              Container(
                margin: const EdgeInsets.only(top: 2),
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: orangeColor,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
