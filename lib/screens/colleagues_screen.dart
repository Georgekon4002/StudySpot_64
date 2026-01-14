import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'profile_screen.dart';

class ColleaguesScreen extends StatelessWidget {
  final String school;
  final String university;

  const ColleaguesScreen({
    super.key,
    required this.school,
    required this.university,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'Colleagues',
          style: GoogleFonts.inter(
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .where('school', isEqualTo: school)
            .where('university', isEqualTo: university)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Text(
                'No colleagues found from $school $university.',
                style: GoogleFonts.inter(fontSize: 16, color: Colors.grey),
              ),
            );
          }

          final users = snapshot.data!.docs.where((doc) {
            return doc.id != FirebaseAuth.instance.currentUser?.uid;
          }).toList();

          if (users.isEmpty) {
            return Center(
              child: Text(
                'No other colleagues found from $school $university.',
                style: GoogleFonts.inter(fontSize: 16, color: Colors.grey),
              ),
            );
          }

          return ListView.builder(
            itemCount: users.length,
            padding: const EdgeInsets.all(16),
            itemBuilder: (context, index) {
              final userData = users[index].data() as Map<String, dynamic>;
              final userId = users[index].id;
              final firstName = userData['firstName'] as String? ?? 'Unknown';
              final lastName = userData['lastName'] as String? ?? '';
              final profilePicUrl = userData['profilePicUrl'] as String? ?? '';
              final userSchool = userData['school'] as String? ?? '';
              final userUniversity = userData['university'] as String? ?? '';

              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(12),
                  leading: CircleAvatar(
                    radius: 24,
                    backgroundImage: (profilePicUrl.isNotEmpty)
                        ? NetworkImage(profilePicUrl)
                        : const AssetImage('assets/images/default_avatar.png')
                              as ImageProvider,
                  ),
                  title: Text(
                    '$firstName $lastName',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  subtitle: Text(
                    '$userUniversity - $userSchool',
                    style: GoogleFonts.inter(color: Colors.grey[600]),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            ProfileScreen(userId: userId, isCurrentUser: false),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
