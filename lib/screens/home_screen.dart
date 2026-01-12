import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'qr_scan_screen.dart';
import 'welcome_screen.dart';
import 'profile_screen.dart';

// Seat states: null = empty, true = occupied, 'reserved' = reserved by user
// NOW: We will use a Map {'status': 'occupied'/'reserved', 'userId': 'xyz'} to store detailed info
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
  // int totalQueueSize = 0; // Derived from Firestore now
  bool _isSeated = false; // Track if user has reserved a seat
  DateTime? _reservationStartTime; // When user reserved the seat
  int? _reservedSpotIndex; // Which spot user reserved
  int? _reservedSeatIndex; // Which seat user reserved
  String? _reservationStatus; // 'reserved' or 'occupied'
  Timer? _reservationTimer; // Timer for 30-minute reservation
  bool _isProcessingReservation =
      false; // Lock to prevent multiple auto-reservations

  // Color constants
  static const Color orangeColor = Color(0xFFFF7B00);
  static const Color beigeColor = Color(0xFFFFECC9);

  // Sample data for study spots (15 spots, each with 4 seats)
  // null = empty, true = occupied, 'reserved' = reserved by user
  List<List<dynamic>> studySpots = List.generate(
    15,
    (_) => List.filled(4, null),
  );

  @override
  void initState() {
    super.initState();
    // No more local queue timer, we listen to Firestore
  }

  @override
  void dispose() {
    _reservationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('study_spots').snapshots(),
      builder: (context, spotsSnapshot) {
        if (spotsSnapshot.hasError) {
          // ... error handling
          return const Scaffold(
            body: Center(child: Text("Error loading spots")),
          );
        }
        if (!spotsSnapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final spotDocs = spotsSnapshot.data!.docs;
        if (spotDocs.isEmpty) {
          _initializeDummyData();
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // --- 1. Parse Study Spots & Calculate Occupancy ---
        int currentOccupied = 0;
        Map<int, List<dynamic>> tempSpots = {};

        bool frameIsSeated = false;
        String? frameReservationStatus;
        int? frameReservedSpotIndex;
        int? frameReservedSeatIndex;
        DateTime? frameReservationTimestamp;

        // For Queue Auto-Assign: Find first available seat
        int? firstFreeSpotIndex;
        int? firstFreeSeatIndex;

        for (var doc in spotDocs) {
          final header = doc.id;
          if (header.startsWith('spot_')) {
            final index = int.tryParse(header.split('_')[1]) ?? 0;
            final spotIndex = index - 1;
            if (spotIndex >= 0 && spotIndex < 15) {
              final data = doc.data() as Map<String, dynamic>;
              final seatsMap = data['seats'] as Map<String, dynamic>? ?? {};

              final List<dynamic> seatList = List.generate(4, (i) {
                final letter = ['A', 'B', 'C', 'D'][i];
                dynamic seatVal;

                if (seatsMap.containsKey(letter)) {
                  final seatData = seatsMap[letter];

                  // Helper to check standard occupancy
                  bool isTaken = false;

                  if (seatData is String) {
                    // Legacy string support
                    if (seatData == 'occupied' || seatData == 'reserved') {
                      currentOccupied++;
                      isTaken = true;
                      // Cannot navigate to profile if legacy string (no userId)
                      seatVal = {'status': seatData, 'userId': null};
                    }
                  } else if (seatData is Map<String, dynamic>) {
                    final status = seatData['status'];
                    final userId = seatData['userId'];
                    final timestamp = seatData['timestamp'] as Timestamp?;

                    // Check for expiration (30 mins)
                    bool isExpired = false;
                    if (status == 'reserved' && timestamp != null) {
                      final diff = DateTime.now().difference(
                        timestamp.toDate(),
                      );
                      if (diff.inMinutes >= 30) {
                        isExpired = true;
                      }
                    }

                    if (!isExpired) {
                      if (userId == currentUser?.uid) {
                        frameIsSeated = true;
                        frameReservationStatus = status;
                        frameReservedSpotIndex = spotIndex;
                        frameReservedSeatIndex = i;
                        if (timestamp != null)
                          frameReservationTimestamp = timestamp.toDate();
                      }

                      if (status == 'occupied' || status == 'reserved') {
                        currentOccupied++;
                        isTaken = true;
                        seatVal = {'status': status, 'userId': userId};
                      }
                    }
                    // If isExpired is true, we treat it as free (seatVal remains null/default, isTaken remains false)
                  }

                  if (!isTaken) {
                    // Found a free seat, record if it's the first one we see
                    if (firstFreeSpotIndex == null) {
                      firstFreeSpotIndex = spotIndex;
                      firstFreeSeatIndex = i;
                    }
                  }
                  return seatVal;
                } else {
                  // Seat key missing -> Free
                  if (firstFreeSpotIndex == null) {
                    firstFreeSpotIndex = spotIndex;
                    firstFreeSeatIndex = i;
                  }
                  return null;
                }
              });
              tempSpots[spotIndex] = seatList;
            }
          }
        }

        // --- 2. Sync Local State (Seated/Timer) ---
        if (frameIsSeated) {
          _isSeated = true;
          _reservationStatus = frameReservationStatus;
          _reservedSpotIndex = frameReservedSpotIndex;
          _reservedSeatIndex = frameReservedSeatIndex;
          if (frameReservationTimestamp != null) {
            _reservationStartTime = frameReservationTimestamp;
          }
          if (_reservationTimer == null || !_reservationTimer!.isActive) {
            Future.microtask(() => _startReservationTimer());
          }
        } else if (_isSeated && !frameIsSeated) {
          _isSeated = false;
          _reservationStatus = null;
          _reservedSpotIndex = null;
          _reservedSeatIndex = null;
          _reservationStartTime = null;
          _reservationTimer?.cancel();
        }

        studySpots = List.generate(
          15,
          (i) => tempSpots[i] ?? [null, null, null, null],
        );
        occupiedSpots = currentOccupied;
        final progress = occupiedSpots / totalSpots;

        // --- 3. Queue Stream Builder ---
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('queue')
              .orderBy('timestamp')
              .snapshots(),
          builder: (context, queueSnapshot) {
            // Default Queue State
            int? myQueuePosition;
            // int totalInQueue = 0; // Not strictly needed for UI unless we show queue size

            if (queueSnapshot.hasData) {
              final queueDocs = queueSnapshot.data!.docs;
              // totalInQueue = queueDocs.length;

              // Find my position (1-based)
              for (int i = 0; i < queueDocs.length; i++) {
                final data = queueDocs[i].data() as Map<String, dynamic>;
                if (data['userId'] == currentUser?.uid) {
                  myQueuePosition = i + 1;
                  break;
                }
              }
            }

            // --- 4. Auto-Reserve Logic ---
            // If I am #1 in queue AND there is a free seat
            if (myQueuePosition == 1 &&
                firstFreeSpotIndex != null &&
                firstFreeSeatIndex != null &&
                !_isSeated &&
                !_isProcessingReservation) {
              // Trigger reservation logic
              Future.microtask(() {
                if (mounted && !_isProcessingReservation && !_isSeated) {
                  _processQueueReservation(
                    firstFreeSpotIndex!,
                    firstFreeSeatIndex!,
                    currentUser?.uid,
                  );
                }
              });
            }

            return Scaffold(
              backgroundColor: Colors.white,
              body: SafeArea(
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
                          PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'profile') {
                                if (currentUser != null) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ProfileScreen(
                                        userId: currentUser.uid,
                                        isCurrentUser: true,
                                      ),
                                    ),
                                  );
                                }
                              } else if (value == 'logout') {
                                FirebaseAuth.instance.signOut().then((_) {
                                  Navigator.of(context).pushAndRemoveUntil(
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const WelcomeWrapper(),
                                    ),
                                    (route) => false,
                                  );
                                });
                              } else if (value == 'reset_data') {
                                _initializeDummyData(); // Force reset
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      "Resetting to 56/60 seats...",
                                    ),
                                  ),
                                );
                              }
                            },
                            itemBuilder: (BuildContext context) =>
                                <PopupMenuEntry<String>>[
                                  PopupMenuItem<String>(
                                    value: 'profile',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.person,
                                          color: Colors.black87,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          'View Profile',
                                          style: GoogleFonts.inter(
                                            color: Colors.black87,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem<String>(
                                    value: 'logout',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.logout,
                                          color: Colors.red[400],
                                          size: 20,
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          'Sign Out',
                                          style: GoogleFonts.inter(
                                            color: Colors.red[400],
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Debug Option for Testing
                                  PopupMenuItem<String>(
                                    value: 'reset_data',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.refresh,
                                          color: Colors.blue,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          'Reset Data (Test)',
                                          style: GoogleFonts.inter(
                                            color: Colors.blue,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
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
                                Icons.person,
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
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
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

                          // OLD QUEUE UI REPLACED WITH NEW LOGIC
                          // Logic:
                          // 1. If user is in queue -> Show "Queue No.: X" (Orange text)
                          // 2. Else IF full (60/60) -> Show "Scan to Enqueue" Button
                          // 3. Else -> Empty (or "Scan to Enqueue" only visible when full)
                          Builder(
                            builder: (context) {
                              if (myQueuePosition != null) {
                                return Text(
                                  'Queue No.: $myQueuePosition',
                                  style: GoogleFonts.inter(
                                    fontSize: 18,
                                    fontWeight: FontWeight
                                        .bold, // Bold to match screenshot
                                    color:
                                        orangeColor, // Orange color as per screenshot usually (or black if unspecified, but orange looks standard)
                                  ),
                                );
                              } else if (occupiedSpots == totalSpots &&
                                  !_isSeated) {
                                // Hide if seated
                                return ElevatedButton(
                                  onPressed: _enqueueUser,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: orangeColor,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        20,
                                      ), // More rounded
                                    ),
                                  ),
                                  child: Text(
                                    'Scan to Enqueue',
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            },
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
              ),
              bottomNavigationBar: Container(
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
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
                        _buildNavItem(
                          Icons.chat_bubble_outline,
                          'Chat',
                          1,
                          false,
                        ),
                        _buildNavItem(Icons.article_outlined, 'News', 2, false),
                        _buildNavItem(
                          Icons.center_focus_strong_outlined,
                          'Focus',
                          3,
                          false,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
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
            );
          }, // end queue builder
        );
      },
    );
  }

  // ... (rest of the file: _buildStudySpotCard, _buildSeat, _showReserveMenu, _showUnreserveMenu)

  // --- Logic Methods ---

  Future<void> _enqueueUser() async {
    // Just add to queue collection
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Use user Uid as doc id to prevent duplicates
      await FirebaseFirestore.instance.collection('queue').doc(user.uid).set({
        'userId': user.uid,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'waiting',
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error joining queue: $e")));
    }
  }

  Future<void> _processQueueReservation(
    int spotIndex,
    int seatIndex,
    String? userId,
  ) async {
    if (userId == null) return;

    // 0. Set Lock & Optimistic UI Update
    // We set _isSeated true immediately to block other reservations locally
    // We also set processing to true
    setState(() {
      _isProcessingReservation = true;
      // Optimistic Reservation
      if (spotIndex < studySpots.length && seatIndex < 4) {
        studySpots[spotIndex][seatIndex] = 'reserved';
      }
      _isSeated = true; // Block UI locally
      _reservedSpotIndex = spotIndex;
      _reservedSeatIndex = seatIndex;
      _reservationStatus = 'reserved';
      queueNumber = null; // Clear queue locally
    });

    try {
      // 1. Reserve the seat
      await _updateSeatStatusFirestore(spotIndex, seatIndex, {
        'status': 'reserved',
        'userId': userId,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // 2. Remove from Queue
      await FirebaseFirestore.instance.collection('queue').doc(userId).delete();

      // 3. Notify User
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false, // Force them to acknowledge
          builder: (_) => AlertDialog(
            backgroundColor: beigeColor,
            title: Text(
              "Seat Assigned!",
              style: GoogleFonts.inter(fontWeight: FontWeight.bold),
            ),
            content: Text(
              "Seat ${spotIndex + 1}${['A', 'B', 'C', 'D'][seatIndex]} is now free and you're entitled to it! It has been reserved for you for 30 minutes.",
              style: GoogleFonts.inter(),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  // Reset lock
                  if (mounted) {
                    setState(() {
                      _isProcessingReservation = false;
                    });
                  }
                },
                child: Text(
                  "Awesome!",
                  style: GoogleFonts.inter(
                    color: orangeColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      print("Error processing queue reservation: $e");
      // Revert lock if failed
      if (mounted) {
        setState(() {
          _isProcessingReservation = false;
          _isSeated = false; // Revert
          if (spotIndex < studySpots.length && seatIndex < 4) {
            studySpots[spotIndex][seatIndex] = null; // Revert
          }
        });
      }
    }
  }

  Widget _buildStudySpotCard(int spotNumber, List<dynamic> seats) {
    final spotIndex = spotNumber - 1;
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
    bool isOccupied = false;
    bool isReserved = false;
    String? seatedUserId;

    if (seatState == true) {
      isOccupied = true;
    } else if (seatState is String) {
      if (seatState == 'occupied') isOccupied = true;
      if (seatState == 'reserved' || seatState == 'reserved_by_me')
        isReserved = true;
    } else if (seatState is Map) {
      final status = seatState['status'];
      seatedUserId = seatState['userId'];
      if (status == 'occupied') isOccupied = true;
      if (status == 'reserved') isReserved = true;
    }

    final isEmpty = !isOccupied && !isReserved;

    // Check if it's the current user
    final isUserReserved =
        (_reservedSpotIndex == spotIndex && _reservedSeatIndex == seatIndex) ||
        (seatState is String && seatState == 'reserved_by_me') ||
        (seatedUserId != null &&
            seatedUserId == FirebaseAuth.instance.currentUser?.uid);

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
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.grey[200],
          border: Border.all(color: Colors.grey[300]!),
        ),
      );
    }

    return Center(
      child: GestureDetector(
        onTapDown: (details) {
          // Case 1: Empty -> Reserve
          if (isEmpty) {
            if (_isSeated) {
              _showUnreserveMenu(context, details.globalPosition);
            } else {
              _showReserveMenu(
                context,
                details.globalPosition,
                spotIndex,
                seatIndex,
              );
            }
          }
          // Case 2: Other User -> View Profile
          else if (!isUserReserved && seatedUserId != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    ProfileScreen(userId: seatedUserId!, isCurrentUser: false),
              ),
            );
          }
          // Case 3: Me -> Unreserve
          else if (isUserReserved) {
            _showUnreserveMenu(context, details.globalPosition);
          }
        },
        child: seatWidget,
      ),
    );
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

  void _showUnreserveMenu(BuildContext context, Offset position) {
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
                _leaveSeat(); // Re-use free logic to unreserve
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
                    const Icon(Icons.lock_open, color: Colors.black, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Unreserve',
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

  void _reserveSeat(int spotIndex, int seatIndex) {
    // 1. Optimistic Update
    setState(() {
      studySpots[spotIndex][seatIndex] = 'reserved';
      occupiedSpots++;
      _isSeated = true;
      _reservedSpotIndex = spotIndex;
      _reservedSeatIndex = seatIndex;
      _reservationStatus = 'reserved';
      _reservationStartTime = DateTime.now();

      if (queueNumber != null) {
        queueNumber = null;
        // totalQueueSize = totalQueueSize > 0 ? totalQueueSize - 1 : 0;
      }
    });

    // 2. Firestore Update (Source of Truth)
    // We store a rich object now
    _updateSeatStatusFirestore(spotIndex, seatIndex, {
      'status': 'reserved',
      'userId': FirebaseAuth.instance.currentUser?.uid,
      'timestamp': FieldValue.serverTimestamp(),
    });

    // 3. Start Timer
    _startReservationTimer();
  }

  void _startReservationTimer() {
    _reservationTimer?.cancel();
    if (_reservationStartTime == null) return;

    final now = DateTime.now();
    final expirationTime = _reservationStartTime!.add(
      const Duration(minutes: 30),
    );
    final remaining = expirationTime.difference(now);

    if (remaining.isNegative) {
      // Already expired
      if (mounted) {
        _leaveSeat();
      }
    } else {
      _reservationTimer = Timer(remaining, () {
        if (mounted) {
          _leaveSeat();
        }
      });
    }

    // UI Tick Timer
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || !_isSeated || _reservationStartTime == null) {
        timer.cancel();
        return;
      }
      final elapsed = DateTime.now().difference(_reservationStartTime!);
      if (elapsed >= const Duration(minutes: 30)) {
        timer.cancel(); // limit reached
        return;
      }
      setState(() {});
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
          enabled:
              !_isSeated || (_isSeated && _reservationStatus == 'reserved'),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap:
                  (!_isSeated ||
                      (_isSeated && _reservationStatus == 'reserved'))
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
                      color: (!_isSeated || _reservationStatus == 'reserved')
                          ? Colors.grey[800]
                          : Colors.grey[400],
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Scan QR',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: (!_isSeated || _reservationStatus == 'reserved')
                            ? Colors.black
                            : Colors.grey[400],
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
          enabled:
              _isSeated &&
              _reservationStatus == 'occupied', // Only enabled if occupied
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: (_isSeated && _reservationStatus == 'occupied')
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
                      color: (_isSeated && _reservationStatus == 'occupied')
                          ? Colors.grey[800]
                          : Colors.grey[400],
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Leave',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: (_isSeated && _reservationStatus == 'occupied')
                            ? Colors.black
                            : Colors.grey[400],
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

  Future<void> _leaveSeat() async {
    _reservationTimer?.cancel();
    if (_reservedSpotIndex != null && _reservedSeatIndex != null) {
      final int spotIndex = _reservedSpotIndex!;
      final int seatIndex = _reservedSeatIndex!;

      try {
        // --- Queue Handoff Logic ---
        // Check if anyone is waiting in the queue
        final queueSnapshot = await FirebaseFirestore.instance
            .collection('queue')
            .orderBy('timestamp')
            .limit(1)
            .get();

        if (queueSnapshot.docs.isNotEmpty) {
          // 1. Found a waiter -> Handoff
          final nextUserDoc = queueSnapshot.docs.first;
          final nextUserId = nextUserDoc['userId'] as String;

          // Update seat to Reserved for Next User
          await _updateSeatStatusFirestore(spotIndex, seatIndex, {
            'status': 'reserved',
            'userId': nextUserId,
            'timestamp': FieldValue.serverTimestamp(),
          });

          // Remove Next User from Queue
          await nextUserDoc.reference.delete();
          print("Seat handed off to queue user: $nextUserId");
        } else {
          // 2. Queue Empty -> Make Seat Free
          await _updateSeatStatusFirestore(spotIndex, seatIndex, null);
        }

        // Update Local State (I am leaving regardless)
        if (mounted) {
          setState(() {
            _isSeated = false;
            _reservedSpotIndex = null;
            _reservedSeatIndex = null;
            _reservationStatus = null;
            _reservationStartTime = null;
            // We rely on the StreamListener to update studySpots and occupiedSpots
            // to prevent conflicts with the handoff logic (occupied vs free)
          });
        }
      } catch (e) {
        print("Error leaving seat: $e");
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("Error leaving seat: $e")));
        }
      }
    }
  }

  // Parse QR code to get spot and seat indices
  Map<String, int>? _parseQRCode(String qrCode) {
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid QR code format. Use e.g. 1A, 15C'),
        ),
      );
      return;
    }

    final spotIndex = parsed['spotIndex']!;
    final seatIndex = parsed['seatIndex']!;

    if (spotIndex < 0 ||
        spotIndex >= studySpots.length ||
        seatIndex < 0 ||
        seatIndex >= 4) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invalid seat location')));
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    final isTaken = await _checkSeatAvailabilityFirestore(spotIndex, seatIndex);

    if (mounted) Navigator.of(context).pop();

    if (isTaken) {
      if (_isSeated &&
          _reservedSpotIndex == spotIndex &&
          _reservedSeatIndex == seatIndex) {
        _confirmSeatOccupancy(spotIndex, seatIndex);

        if (mounted) {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              backgroundColor: beigeColor,
              title: const Text("Success"),
              content: const Text("You have confirmed your seat!"),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("OK"),
                ),
              ],
            ),
          );
        }
      } else {
        _showSeatTakenDialog();
      }
    } else {
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
          if (seats.containsKey(seatLetter)) {
            final val = seats[seatLetter];
            if (val == null) return false;

            if (val is Map<String, dynamic>) {
              final status = val['status'];
              final timestamp = val['timestamp'] as Timestamp?;

              if (status == 'reserved' && timestamp != null) {
                final diff = DateTime.now().difference(timestamp.toDate());
                if (diff.inMinutes >= 30) {
                  return false; // Expired, so it is free
                }
              }

              // If status is null/free in map? (Unlikely schema, but safe fallback)
              return true; // Occupied or Reserved (and not expired)
            }
            // Legacy string
            return true;
          }
        }
      }
      return false;
    } catch (e) {
      print('Firestore error: $e');
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
                  'Seat is taken 😓',
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
    if (_reservedSpotIndex != null && _reservedSeatIndex != null) {
      if (_reservedSpotIndex != spotIndex || _reservedSeatIndex != seatIndex) {
        _updateSeatStatusFirestore(
          _reservedSpotIndex!,
          _reservedSeatIndex!,
          null,
        );
        setState(() {
          studySpots[_reservedSpotIndex!][_reservedSeatIndex!] = null;
        });
      }
    }

    setState(() {
      studySpots[spotIndex][seatIndex] = true;
      occupiedSpots++;
      _isSeated = true;
      _reservedSpotIndex = spotIndex;
      _reservedSeatIndex = seatIndex;
      _reservationStatus = 'occupied';
      _reservationStartTime = DateTime.now();
    });

    _updateSeatStatusFirestore(spotIndex, seatIndex, {
      'status': 'occupied',
      'userId': FirebaseAuth.instance.currentUser?.uid,
      'timestamp': FieldValue.serverTimestamp(),
    });

    _startReservationTimer();
  }

  Future<void> _updateSeatStatusFirestore(
    int spotIndex,
    int seatIndex,
    dynamic status,
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

    // Specific free seats: 1A (Spot 1, index 0), 5D (Spot 5, index 3), 6C (Spot 6, index 2), 13A (Spot 13, index 0)
    final freeSeats = ['1A', '5D', '6C', '13A'];

    // Create 15 spots
    for (int i = 1; i <= 15; i++) {
      final docRef = firestore.collection('study_spots').doc('spot_$i');
      Map<String, dynamic> seats = {};

      for (var letter in ['A', 'B', 'C', 'D']) {
        final seatId = '$i$letter';
        if (freeSeats.contains(seatId)) {
          seats[letter] = null; // Free
        } else {
          // Occupied by dummy user
          seats[letter] = {
            'status': 'occupied',
            'userId': 'dummy_user_$seatId',
            'timestamp': Timestamp.now(),
          };
        }
      }

      batch.set(docRef, {'seats': seats});
    }

    try {
      await batch.commit();
      print("Dummy data initialized: 56/60 seats occupied.");
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
