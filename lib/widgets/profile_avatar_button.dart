import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../screens/profile_screen.dart';
import '../screens/welcome_screen.dart';

class ProfileAvatarButton extends StatelessWidget {
  const ProfileAvatarButton({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      // Fallback for no user, though unlikely in this context
      return const CircleAvatar(
        backgroundColor: Colors.grey,
        child: Icon(Icons.person, color: Colors.white),
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .snapshots(),
      builder: (context, snapshot) {
        String? profilePicUrl;
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          profilePicUrl = data['profilePicUrl'] as String?;
        }

        // Use user's cached photoURL if stream is waiting, or default
        // Actually, stream is better.

        ImageProvider? backgroundImage;
        if (profilePicUrl != null && profilePicUrl.isNotEmpty) {
          backgroundImage = NetworkImage(profilePicUrl);
        } else {
          backgroundImage = const AssetImage(
            'assets/images/default_avatar.png',
          );
        }

        return PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'profile') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ProfileScreen(
                    userId: currentUser.uid,
                    isCurrentUser: true,
                  ),
                ),
              );
            } else if (value == 'logout') {
              FirebaseAuth.instance.signOut().then((_) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (context) => const WelcomeWrapper(),
                  ),
                  (route) => false,
                );
              });
            }
          },
          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
            PopupMenuItem<String>(
              value: 'profile',
              child: Row(
                children: [
                  Icon(Icons.person, color: Colors.black87, size: 20),
                  const SizedBox(width: 12),
                  Text(
                    'View Profile',
                    style: GoogleFonts.alata(
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
                  Icon(Icons.logout, color: Colors.red[400], size: 20),
                  const SizedBox(width: 12),
                  Text(
                    'Sign Out',
                    style: GoogleFonts.alata(
                      color: Colors.red[400],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
          child: Container(
            width: 50, // Adjusted size to fit header nicely
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey[200],
              border: Border.all(color: Colors.grey[300]!, width: 1),
              image: DecorationImage(
                image: backgroundImage!,
                fit: BoxFit.cover,
              ),
            ),
          ),
        );
      },
    );
  }
}
