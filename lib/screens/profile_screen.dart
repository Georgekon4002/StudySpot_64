import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/user_model.dart';
import 'edit_profile_screen.dart';
import 'studying_users_screen.dart';
import 'colleagues_screen.dart';
import 'welcome_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String userId;
  final bool isCurrentUser;

  const ProfileScreen({
    super.key,
    required this.userId,
    this.isCurrentUser = false,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // We rely on Firestore stream for UI updates now

  Future<void> _toggleFriendship() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid);
      final userSnapshot = await userRef.get();
      if (!userSnapshot.exists) return;

      final userData = UserModel.fromFirestore(userSnapshot);
      final isFriend = userData.friendIds.contains(widget.userId);

      if (isFriend) {
        // Remove friend
        await userRef.update({
          'friendIds': FieldValue.arrayRemove([widget.userId]),
        });
      } else {
        // Add friend
        await userRef.update({
          'friendIds': FieldValue.arrayUnion([widget.userId]),
        });

        // Send Notification
        await FirebaseFirestore.instance.collection('notifications').add({
          'recipientId': widget.userId,
          'senderId': currentUser.uid,
          'type': 'friend_add',
          'timestamp': FieldValue.serverTimestamp(),
          'read': false,
        });
      }
    } catch (e) {
      debugPrint("Error toggling friendship: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error updating friend: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'StudyProfile',
          style: GoogleFonts.alata(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (widget.isCurrentUser) ...[
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.black),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const EditProfileScreen(),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.red),
              onPressed: () {
                FirebaseAuth.instance.signOut().then((_) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (context) => const WelcomeWrapper(),
                    ),
                    (route) => false,
                  );
                });
              },
            ),
          ],
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(widget.userId) // Changed to widget.userId
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text("Profile not found"));
          }

          final user = UserModel.fromFirestore(snapshot.data!);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(user),
                if (!widget.isCurrentUser) ...[
                  // Changed to widget.isCurrentUser
                  const SizedBox(height: 16),
                  _buildActionButtons(user),
                ],
                const SizedBox(height: 24),
                _buildSection(
                  title:
                      widget
                          .isCurrentUser // Changed to widget.isCurrentUser
                      ? 'About You'
                      : 'About ${user.firstName}',
                  content: Text(
                    user.aboutYou.isNotEmpty ? user.aboutYou : "No bio yet.",
                    style: GoogleFonts.alata(
                      fontSize: 14,
                      color: Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _buildSection(
                  title: 'Currently Studying',
                  content: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        user.currentlyStudying.isNotEmpty
                            ? user.currentlyStudying
                            : "Nothing specified.",
                        style: GoogleFonts.alata(
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                      if (user.currentlyStudying.isNotEmpty)
                        TextButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => StudyingUsersScreen(
                                  subject: user.currentlyStudying,
                                ),
                              ),
                            );
                          },
                          child: Text(
                            "See who else",
                            style: GoogleFonts.alata(
                              fontSize: 12,
                              color: Colors.blue,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildSection(
                  title:
                      widget
                          .isCurrentUser // Changed to widget.isCurrentUser
                      ? 'Your Friends'
                      : "${user.firstName}’s Friends",
                  content: _buildFriendsList(user),
                ),
                const SizedBox(height: 16),
                _buildSection(
                  title:
                      widget
                          .isCurrentUser // Changed to widget.isCurrentUser
                      ? 'Your Thoughts'
                      : "${user.firstName}’s Thoughts",
                  content: _buildThoughts(user),
                ),
                const SizedBox(height: 16),
                _buildSection(
                  title:
                      widget
                          .isCurrentUser // Changed to widget.isCurrentUser
                      ? 'Your Moments'
                      : "${user.firstName}’s Moments",
                  content: _buildMoments(user),
                ),
                const SizedBox(height: 16),
                _buildSection(
                  title:
                      widget
                          .isCurrentUser // Changed to widget.isCurrentUser
                      ? 'Your Achievements'
                      : "${user.firstName}’s Achievements",
                  content: _buildAchievements(user),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(UserModel user) {
    return Row(
      children: [
        CircleAvatar(
          radius: 35,
          backgroundColor: Colors.grey[200],
          backgroundImage: user.profilePicUrl.isNotEmpty
              ? NetworkImage(user.profilePicUrl) as ImageProvider
              : const AssetImage('assets/images/default_avatar.png'),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      user.fullName,
                      style: GoogleFonts.alata(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildUserStatusBadge(user.uid),
                ],
              ),
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ColleaguesScreen(
                        school: user.school,
                        university: user.university,
                      ),
                    ),
                  );
                },
                child: Text(
                  '${user.school} ${user.university}',
                  style: GoogleFonts.alata(
                    fontSize: 14,
                    color: Colors
                        .blue, // Make it look clickable (or keep grey but clickable)
                    decoration:
                        TextDecoration.underline, // Add underline for clarity
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUserStatusBadge(String userId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('study_spots').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        String? status; // 'Seated' or 'Coming Soon'

        for (var doc in snapshot.data!.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final seatsMap = data['seats'] as Map<String, dynamic>?;
          if (seatsMap == null) continue;

          for (var seatInfo in seatsMap.values) {
            if (seatInfo is Map<String, dynamic>) {
              if (seatInfo['userId'] == userId) {
                final seatStatus = seatInfo['status'];
                if (seatStatus == 'occupied') {
                  status = 'Seated';
                } else if (seatStatus == 'reserved') {
                  status = 'Coming Soon';
                }
                break;
              }
            }
          }
          if (status != null) break;
        }

        if (status == null) return const SizedBox.shrink();

        final Color badgeColor = status == 'Seated'
            ? const Color(0xFFFF7B00)
            : const Color(0xFFFF2F1C);

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: badgeColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            status,
            style: GoogleFonts.alata(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      },
    );
  }

  // Updated to allow async building of button state
  Widget _buildActionButtons(UserModel profileUser) {
    if (widget.isCurrentUser) return const SizedBox.shrink();

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final currentUserData = UserModel.fromFirestore(snapshot.data!);
        final isFriend = currentUserData.friendIds.contains(widget.userId);

        return Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _toggleFriendship,
                icon: Icon(isFriend ? Icons.check : Icons.person_add, size: 18),
                label: Text(isFriend ? 'Friends' : 'Add Friend'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isFriend
                      ? const Color(0xFF81D4FA) // Light Blue
                      : const Color(0xFFFFECC9), // Original Beige
                  foregroundColor: isFriend
                      ? Colors.white
                      : const Color(0xFFFF7B00),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  // Message logic placeholder
                },
                icon: const Icon(Icons.message_outlined, size: 18),
                label: const Text('Message'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC9FFCF),
                  foregroundColor: const Color(0xFF2E7D32),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSection({required String title, required Widget content}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFECC9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.alata(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          content,
        ],
      ),
    );
  }

  Widget _buildFriendsList(UserModel user) {
    if (user.friendIds.isEmpty) {
      return Text(
        "No Friends",
        style: GoogleFonts.alata(color: Colors.grey[700]),
      );
    }

    return FutureBuilder<List<UserModel>>(
      future: _fetchFriends(user.friendIds),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Text(
            "No Friends", // Should ideally match emptiness check but just safe
            style: GoogleFonts.alata(color: Colors.grey[700]),
          );
        }

        final friends = snapshot.data!;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: friends.map((friend) {
              return GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ProfileScreen(
                        userId: friend.uid,
                        // Needs check if it's me
                        isCurrentUser:
                            friend.uid ==
                            FirebaseAuth.instance.currentUser?.uid,
                      ),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.only(right: 12.0),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: Colors.grey[300],
                        backgroundImage: friend.profilePicUrl.isNotEmpty
                            ? NetworkImage(friend.profilePicUrl)
                                  as ImageProvider
                            : const AssetImage(
                                'assets/images/default_avatar.png',
                              ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        friend.firstName,
                        style: GoogleFonts.alata(
                          fontSize: 12,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Future<List<UserModel>> _fetchFriends(List<String> friendIds) async {
    if (friendIds.isEmpty) return [];

    try {
      // Create chunks of 10 for 'whereIn' query limit if needed, but for now simple
      // Or simply fetch by IDs.
      // Firestore 'whereIn' is limited to 10. If list is large, fetch individually or loops.
      // Simplest for MVP: Fetch all users where ID is in list.

      final chunks = <List<String>>[];
      for (var i = 0; i < friendIds.length; i += 10) {
        chunks.add(
          friendIds.sublist(
            i,
            i + 10 > friendIds.length ? friendIds.length : i + 10,
          ),
        );
      }

      final List<UserModel> friends = [];
      for (final chunk in chunks) {
        final snapshot = await FirebaseFirestore.instance
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        friends.addAll(
          snapshot.docs.map((doc) => UserModel.fromFirestore(doc)),
        );
      }
      return friends;
    } catch (e) {
      debugPrint("Error fetching friends: $e");
      return [];
    }
  }

  Widget _buildThoughts(UserModel user) {
    if (user.thoughts.isEmpty) {
      return Text(
        "No thoughts yet.",
        style: GoogleFonts.alata(color: Colors.grey[700]),
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          user.thoughts.first,
          style: GoogleFonts.alata(color: Colors.grey[700]),
        ),
        Text(
          "19/11",
          style: GoogleFonts.alata(color: Colors.grey[500], fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildMoments(UserModel user) {
    if (user.momentUrls.isEmpty) {
      return Text(
        "No moments yet.",
        style: GoogleFonts.alata(color: Colors.grey[700]),
      );
    }
    return SizedBox(
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: user.momentUrls.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          return Container(
            width: 60,
            height: 80,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: Colors.grey[300],
              image: DecorationImage(
                image: NetworkImage(user.momentUrls[index]),
                fit: BoxFit.cover,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAchievements(UserModel user) {
    if (user.achievements.isEmpty) {
      return Text(
        "No achievements yet.",
        style: GoogleFonts.alata(color: Colors.grey[700]),
      );
    }
    return Row(
      children: [
        const Icon(Icons.emoji_events, color: Colors.purple, size: 32),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "You're so focused - Tier 2",
                style: GoogleFonts.alata(fontWeight: FontWeight.bold),
              ),
              Text(
                "You stayed in focus for 1 hour",
                style: GoogleFonts.alata(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
