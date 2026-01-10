import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Seat states: null = empty, true = occupied, 'reserved' = reserved by user
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  int occupiedSpots = 26;
  int totalSpots = 52;
  int? queueNumber; // null = not in queue, number = position in queue
  int totalQueueSize = 0; // Total people in queue

  // Color constants
  static const Color orangeColor = Color(0xFFFF7B00);
  static const Color beigeColor = Color(0xFFFFECC9);

  // Sample data for study spots (15 spots, each with 4 seats)
  // null = empty, true = occupied, 'reserved' = reserved by user
  List<List<dynamic>> studySpots = [
    [true, null, true, null], // Spot 1
    [true, true, true, null],  // Spot 2
    [null, null, null, null], // Spot 3
    [null, null, true, true],   // Spot 4
    [true, true, true, true],     // Spot 5
    [true, null, true, true],    // Spot 6
    [null, null, true, null],  // Spot 7
    [null, null, null, null], // Spot 8
    [null, null, true, true],   // Spot 9
    [true, true, true, null],    // Spot 10
    [true, true, true, true],     // Spot 11
    [null, true, null, true],   // Spot 12
    [true, true, true, true],     // Spot 13
    [null, null, true, true],   // Spot 14
    [true, null, true, null],   // Spot 15
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
    super.dispose();
  }

  void _startQueueTimer() {
    _queueTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (queueNumber != null && queueNumber! > 1 && occupiedSpots == totalSpots) {
        // Simulate someone ahead in queue getting a seat
        setState(() {
          queueNumber = queueNumber! - 1;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final progress = occupiedSpots / totalSpots;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Header Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                      // Handle profile tap
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Profile tapped')),
                      );
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.grey[300],
                        border: Border.all(color: Colors.grey[400]!, width: 1),
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
                                  horizontal: 16, vertical: 12),
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
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: studySpots.length,
                  itemBuilder: (context, index) {
                    return _buildStudySpotCard(index, studySpots[index]);
                  },
                ),
              ),
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
      // Floating Action Button (only show when in queue)
      floatingActionButton: queueNumber != null
          ? FloatingActionButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Add new study spot')),
                );
              },
              backgroundColor: orangeColor,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
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

  Widget _buildStudySpotCard(int spotIndex, List<dynamic> seats) {
    return Container(
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
        child: const Icon(
          Icons.person,
          color: Colors.white,
          size: 16,
        ),
      );
    } else if (isReserved) {
      seatWidget = SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: const AlwaysStoppedAnimation<Color>(
            Colors.red,
          ),
        ),
      );
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

    if (isEmpty) {
      return GestureDetector(
        onTapDown: (TapDownDetails details) => _showReserveMenu(
            context, details.globalPosition, spotIndex, seatIndex),
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: seatWidget,
        ),
      );
    } else {
      return Center(
        child: seatWidget,
      );
    }
  }

  void _showReserveMenu(
      BuildContext context, Offset position, int spotIndex, int seatIndex) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Rect.fromLTWH(0, 0, overlay.size.width, overlay.size.height),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
      
      // If user was in queue and reserved a seat, remove from queue
      if (queueNumber != null) {
        queueNumber = null;
        totalQueueSize = totalQueueSize > 0 ? totalQueueSize - 1 : 0;
      }
    });

    // After 2 seconds, mark as occupied
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          studySpots[spotIndex][seatIndex] = true;
        });
      }
    });
  }

  Widget _buildNavItem(IconData icon, String label, int index, bool isHome) {
    final isSelected = _selectedIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedIndex = index;
        });
        if (index != 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$label tapped')),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? orangeColor.withOpacity(0.15) : Colors.transparent,
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
