import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'qr_scan_screen.dart';

import 'profile_screen.dart';
import 'chat_screen.dart';
import 'feed_screen.dart';
import 'focus_screen.dart';
import '../widgets/profile_avatar_button.dart';

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

  StreamSubscription? _userSubscription;
  StreamSubscription? _spotsSubscription;
  Set<String> _friendIds = {};
  Set<String> _friendsOnSpot = {}; // Friends currently in a seat
  bool _isFirstFriendLoad = true;
  bool _isFirstSpotLoad = true;

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
    _setupHapticListeners();
  }

  void _setupHapticListeners() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // 1. Listen for Friends (Added as friend)
      _userSubscription = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen((snapshot) {
        if (snapshot.exists) {
          final data = snapshot.data();
          if (data != null) {
            final newFriendIds = Set<String>.from(data['friendIds'] ?? []);
            
            // "When you have been added as a friend" -> Heavy Impact
            // If it's NOT the first load, and the new list is larger than the old list
            // Or if first load was empty and now we have friends? No, only on increase during session.
            // Actually user wants "When you have been added". If I open app and I have a new friend since last time?
            // The requirement likely implies real-time updates.
            // Logic: If NOT first load, and size increased.
            if (!_isFirstFriendLoad && newFriendIds.length > _friendIds.length) {
               print("DEBUG: Friend Added Triggered");
               _triggerHeavyHaptic("You have a new friend! 🤝");
            }
            
            _friendIds = newFriendIds;
            _isFirstFriendLoad = false;
          }
        }
      });

      // 2. Listen for "Friend on the house"
      _spotsSubscription = FirebaseFirestore.instance
          .collection('study_spots')
          .snapshots()
          .listen((snapshot) {
        final Set<String> currentFriendsHere = {};

        for (var doc in snapshot.docs) {
           // Basic parsing to find occupants
           final data = doc.data();
           final seatsMap = data['seats'] as Map<String, dynamic>? ?? {};
           
           seatsMap.forEach((key, value) {
             if (value is Map<String, dynamic>) {
               final userId = value['userId'];
               final status = value['status'];
               final timestamp = value['timestamp'] as Timestamp?;
               
               if (userId != null && _friendIds.contains(userId)) {
                 bool isExpired = false;
                 // Check expiry if reserved
                 if (status == 'reserved' && timestamp != null) {
                    final diff = DateTime.now().difference(timestamp.toDate());
                    if (diff.inMinutes >= 30) isExpired = true;
                 }
                 
                 if (!isExpired) {
                   currentFriendsHere.add(userId);
                 }
               }
             }
           });
        }

        // Check for new arrivals
        // If a friend is now here, who wasn't here before
        final newArrivals = currentFriendsHere.difference(_friendsOnSpot);
        
        if (newArrivals.isNotEmpty) {
           if (_isFirstSpotLoad) {
               // First load: Friend is already here
               print("DEBUG: Friend Already Here Triggered");
               _triggerHeavyHaptic("Your friends are already studying here! 🏠");
           } else {
               // Subsequent update: Friend just arrived
               print("DEBUG: Friend Arrival Triggered");
               _triggerHeavyHaptic("A friend is on the house! 🏠");
           }
        }
        
        _friendsOnSpot = currentFriendsHere;
        _isFirstSpotLoad = false;
      });
    }
  }

  Future<void> _triggerHeavyHaptic(String message) async {
    await HapticFeedback.heavyImpact();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: GoogleFonts.alata(color: Colors.white),
          ),
          backgroundColor: Colors.black87,
          duration: const Duration(seconds: 3),
        ),
      );
    }
    print("DEBUG: Heavy Haptic Triggered: $message");
  }

  @override
  void dispose() {
    _userSubscription?.cancel();
    _spotsSubscription?.cancel();
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
                        seatVal = {
                          'status': status,
                          'userId': userId,
                          'timestamp': timestamp,
                          'profilePicUrl': seatData['profilePicUrl'],
                        };
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
              backgroundColor: _selectedIndex == 0
                  ? Colors.white
                  : Colors.transparent, // Let body define color
              body: _selectedIndex == 0
                  ? SafeArea(
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
                                    style: GoogleFonts.alata(
                                      fontSize: 34,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                    ),
                                    children: [
                                      const TextSpan(text: 'Study'),
                                      TextSpan(
                                        text: 'Spot',
                                        style: GoogleFonts.alata(
                                          fontSize: 34,
                                          fontWeight: FontWeight.bold,
                                          color: orangeColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Profile Picture
                                const ProfileAvatarButton(),
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
                              crossAxisAlignment: CrossAxisAlignment
                                  .center, // Ensure vertical alignment
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    // Circular Progress Indicator
                                    SizedBox(
                                      width: 60,
                                      height: 60,
                                      child: Stack(
                                        alignment: Alignment.center,
                                        fit: StackFit.expand,
                                        children: [
                                          // Background circle
                                          CircularProgressIndicator(
                                            value: 1.0,
                                            strokeWidth: 8,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  beigeColor,
                                                ),
                                            backgroundColor: Colors.transparent,
                                          ),
                                          // Progress arc
                                          CircularProgressIndicator(
                                            value: progress,
                                            strokeWidth: 8,
                                            valueColor:
                                                const AlwaysStoppedAnimation<
                                                  Color
                                                >(orangeColor),
                                            backgroundColor: Colors.transparent,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 15),
                                    // Count Text
                                    Text(
                                      '$occupiedSpots/$totalSpots',
                                      style: GoogleFonts.alata(
                                        fontSize: 32,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black,
                                      ),
                                    ),
                                  ],
                                ),
                                const Spacer(),

                                // OLD QUEUE UI REPLACED WITH NEW LOGIC
                                Builder(
                                  builder: (context) {
                                    if (myQueuePosition != null) {
                                      return Text(
                                        'Queue No.: $myQueuePosition',
                                        style: GoogleFonts.alata(
                                          fontSize: 18,
                                          fontWeight: FontWeight
                                              .bold, // Bold to match screenshot
                                          color:
                                              orangeColor, // Orange color as per screenshot usually
                                        ),
                                      );
                                    } else if (occupiedSpots == totalSpots &&
                                        !_isSeated) {
                                      // Hide if seated
                                      return ElevatedButton(
                                        onPressed: () {
                                          HapticFeedback.lightImpact();
                                          _enqueueUser();
                                        },
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
                                          'Enqueue',
                                          style: GoogleFonts.alata(
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
                    )
                  : _selectedIndex == 1
                  ? const ChatScreen()
                  : _selectedIndex == 2
                  ? const FeedScreen()
                  : const FocusScreen(),

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
                        _buildNavItem(Icons.home, 0, orangeColor, beigeColor),
                        _buildNavItem(
                          Icons.chat_bubble_outline,
                          1,
                          const Color(0xFF2D9800),
                          const Color(0xFFC8FFC9),
                        ),
                        _buildNavItem(
                          Icons.article_outlined,
                          2,
                          Colors.blue,
                          Colors.blue.withValues(alpha: 0.2),
                        ),
                        _buildNavItem(
                          Icons.center_focus_strong_outlined,
                          3,
                          Colors.purple,
                          Colors.purple.withValues(alpha: 0.2),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              floatingActionButton: _selectedIndex == 0 ? _buildFab() : null,
            );
          }, // end queue builder
        );
      },
    );
  }

  Widget _buildFab() {
    bool showFab = false;
    bool isLeave = false;

    if (_isSeated) {
      if (_reservationStatus == 'occupied') {
        showFab = true;
        isLeave = true;
      } else {
        // Reserved -> Scan to confirm
        showFab = true;
        isLeave = false;
      }
    } else {
      if (_hasAvailableSeats()) {
        showFab = true;
        isLeave = false; // Scan to reserve
      }
    }

    if (!showFab) return const SizedBox.shrink();

    final iconData = isLeave ? Icons.exit_to_app : Icons.qr_code_scanner;
    final VoidCallback action = isLeave ? _showLeaveDialog : _openQRScanner;

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SizedBox(
        width: 75,
        height: 75,
        child: FloatingActionButton(
          onPressed: action,
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            width: 75,
            height: 75,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: orangeColor,
            ),
            child: Icon(iconData, color: Colors.white, size: 36),
          ),
        ),
      ),
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

    String profilePicUrl = '';
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      if (userDoc.exists) {
        profilePicUrl = userDoc.data()?['profilePicUrl'] ?? '';
      }
    } catch (e) {
      print("Error fetching user profile for reservation: $e");
    }

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
        'profilePicUrl': profilePicUrl,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // 2. Remove from Queue
      await FirebaseFirestore.instance.collection('queue').doc(userId).delete();

      // 3. Notify User
      if (mounted) {
        print("DEBUG: Auto-Reserve Heavy Haptic Triggered");
        await HapticFeedback.heavyImpact(); // Heavy vibration on assignment
        showDialog(
          context: context,
          barrierDismissible: false, // Force them to acknowledge
          builder: (_) => AlertDialog(
            backgroundColor: beigeColor,
            title: Text(
              "Seat Assigned!",
              style: GoogleFonts.alata(fontWeight: FontWeight.bold),
            ),
            content: Text(
              "Seat ${spotIndex + 1}${['A', 'B', 'C', 'D'][seatIndex]} is now free and you're entitled to it! It has been reserved for you for 30 minutes.",
              style: GoogleFonts.alata(),
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
                  style: GoogleFonts.alata(
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
              style: GoogleFonts.alata(
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
    String? profilePicUrl;

    if (seatState == true) {
      isOccupied = true;
    } else if (seatState is String) {
      if (seatState == 'occupied') isOccupied = true;
      if (seatState == 'reserved' || seatState == 'reserved_by_me')
        isReserved = true;
    } else if (seatState is Map) {
      final status = seatState['status'];
      seatedUserId = seatState['userId'];
      profilePicUrl = seatState['profilePicUrl'];
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
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.grey[800],
          border: Border.all(color: Colors.grey[800]!, width: 1),
          image: (profilePicUrl != null && profilePicUrl.isNotEmpty)
              ? DecorationImage(
                  image: NetworkImage(profilePicUrl),
                  fit: BoxFit.cover,
                )
              : const DecorationImage(
                  image: AssetImage('assets/images/default_avatar.png'),
                  fit: BoxFit.cover,
                ),
        ),
      );
    } else if (isReserved) {
      DateTime? timestamp;
      if (seatState is Map && seatState['timestamp'] is Timestamp) {
        timestamp = (seatState['timestamp'] as Timestamp).toDate();
      } else if (isUserReserved && _reservationStartTime != null) {
        timestamp = _reservationStartTime;
      }

      // If we have a timestamp, show the timer
      if (timestamp != null) {
        final now = DateTime.now();
        final elapsed = now.difference(timestamp);
        final remaining = const Duration(minutes: 30) - elapsed;
        final progress = remaining.inSeconds / (30 * 60);

        final timerColor = isUserReserved ? Colors.red : Colors.black;

        seatWidget = SizedBox(
          width: 42,
          height: 42,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 42,
                height: 42,
                child: CircularProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(timerColor),
                  backgroundColor: timerColor.withOpacity(0.2),
                ),
              ),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey[300], // Light grey for reserved
                  border: Border.all(color: Colors.white, width: 1),
                  image: (profilePicUrl != null && profilePicUrl.isNotEmpty)
                      ? DecorationImage(
                          image: NetworkImage(profilePicUrl),
                          fit: BoxFit.cover,
                        )
                      : const DecorationImage(
                          image: AssetImage('assets/images/default_avatar.png'),
                          fit: BoxFit.cover,
                        ),
                ),
              ),
            ],
          ),
        );
      } else {
        // Fallback if no timestamp
        seatWidget = Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.grey[300], // Light grey for reserved
            image: (profilePicUrl != null && profilePicUrl.isNotEmpty)
                ? DecorationImage(
                    image: NetworkImage(profilePicUrl),
                    fit: BoxFit.cover,
                  )
                : const DecorationImage(
                    image: AssetImage('assets/images/default_avatar.png'),
                    fit: BoxFit.cover,
                  ),
          ),
        );
      }
    } else {
      seatWidget = Container(
        width: 34,
        height: 34,
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
          HapticFeedback.lightImpact(); // Tactile feedback
          // Case 1: Empty -> Reserve
          if (isEmpty) {
            if (_isSeated) {
              // User is already seated, do nothing for other empty seats
              // (They can only unreserve their own seat via its tap handler)
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
            // Only allow unreserve if NOT yet occupied (still in reservation phase)
            if (_reservationStatus == 'reserved') {
              _showUnreserveMenu(context, details.globalPosition);
            }
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
                      style: GoogleFonts.alata(
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
                      style: GoogleFonts.alata(
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

    // 1.5 Fetch profile pic
    String profilePicUrl = '';
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      FirebaseFirestore.instance.collection('users').doc(user.uid).get().then((
        doc,
      ) {
        if (doc.exists) {
          profilePicUrl = doc.data()?['profilePicUrl'] ?? '';
          // 2. Firestore Update (Source of Truth)
          _updateSeatStatusFirestore(spotIndex, seatIndex, {
            'status': 'reserved',
            'userId': user.uid,
            'profilePicUrl': profilePicUrl,
            'timestamp': FieldValue.serverTimestamp(),
          });
        }
      });
    } else {
      // Fallback if no user? Should not happen
      _updateSeatStatusFirestore(spotIndex, seatIndex, {
        'status': 'reserved',
        'userId': FirebaseAuth.instance.currentUser?.uid,
        'timestamp': FieldValue.serverTimestamp(),
      });
    }

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
        _handleReservationExpired();
      }
    } else {
      _reservationTimer = Timer(remaining, () {
        if (mounted) {
          _handleReservationExpired();
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

  Future<void> _handleReservationExpired() async {
    await _triggerHeavyHaptic("Reservation expired ⏳");
    _leaveSeat();
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
                  style: GoogleFonts.alata(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'Your seat is now free for someone else who needs to focus 😊',
                  style: GoogleFonts.alata(
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
                      style: GoogleFonts.alata(
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

          // Fetch next user's profile pic
          String nextUserProfilePic = '';
          try {
            final userDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(nextUserId)
                .get();
            if (userDoc.exists) {
              nextUserProfilePic = userDoc.data()?['profilePicUrl'] ?? '';
            }
          } catch (e) {
            print("Error fetching next user profile: $e");
          }

          // Update seat to Reserved for Next User
          await _updateSeatStatusFirestore(spotIndex, seatIndex, {
            'status': 'reserved',
            'userId': nextUserId,
            'profilePicUrl': nextUserProfilePic,
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
          HapticFeedback.lightImpact(); // Confirm feedback
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
                  style: GoogleFonts.alata(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'You want to sit here to focus and study?',
                  style: GoogleFonts.alata(
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
                        style: GoogleFonts.alata(
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
                        style: GoogleFonts.alata(
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
                  style: GoogleFonts.alata(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'Unfortunately this seat is already taken. You can find which seat is free on the map.',
                  style: GoogleFonts.alata(
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
                      style: GoogleFonts.alata(
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

  Future<void> _confirmSeatOccupancy(int spotIndex, int seatIndex) async {
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

    // Fetch profile pic
    String profilePicUrl = '';
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (doc.exists) {
          profilePicUrl = doc.data()?['profilePicUrl'] ?? '';
        }
      } catch (e) {
        print("Error fetching profile pic for confirmation: $e");
      }
    }

    _updateSeatStatusFirestore(spotIndex, seatIndex, {
      'status': 'occupied',
      'userId': FirebaseAuth.instance.currentUser?.uid,
      'profilePicUrl': profilePicUrl,
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

  Widget _buildNavItem(
    IconData icon,
    int index,
    Color activeColor,
    Color activeBgColor,
  ) {
    final isSelected = _selectedIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedIndex = index;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? activeBgColor : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Icon(
          icon,
          color: isSelected ? activeColor : Colors.grey[600],
          size: 28,
        ),
      ),
    );
  }
}
