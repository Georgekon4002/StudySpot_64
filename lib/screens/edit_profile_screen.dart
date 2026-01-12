import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/user_model.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _firstNameController;
  late TextEditingController
  _lastNameController; // Not in screenshot explicitly as field but in name
  late TextEditingController _schoolController;
  late TextEditingController _universityController;
  late TextEditingController _aboutController;
  late TextEditingController _studyingController;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _firstNameController = TextEditingController();
    _lastNameController = TextEditingController();
    _schoolController = TextEditingController();
    _universityController = TextEditingController();
    _aboutController = TextEditingController();
    _studyingController = TextEditingController();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        final userData = UserModel.fromFirestore(doc);
        _firstNameController.text = userData.firstName;
        _lastNameController.text = userData.lastName;
        _schoolController.text = userData.school;
        _universityController.text = userData.university;
        _aboutController.text = userData.aboutYou;
        _studyingController.text = userData.currentlyStudying;
      }
    }
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final updatedUser = UserModel(
      uid: user.uid,
      firstName: _firstNameController.text,
      lastName:
          _lastNameController.text, // Assuming keeping last name or combining
      school: _schoolController.text,
      university: _universityController.text,
      aboutYou: _aboutController.text,
      currentlyStudying: _studyingController.text,
      // Keep existing arrays or empty
      friendIds: [],
      thoughts: [],
      momentUrls: [],
      achievements: [],
    );

    // Merge update
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .set(updatedUser.toMap(), SetOptions(merge: true));

    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'StudyProfile',
          style: GoogleFonts.inter(
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
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Profile Pic Edit
                    Center(
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 40,
                            backgroundColor: Colors.grey[200],
                            backgroundImage: const NetworkImage(
                              'https://i.pravatar.cc/150',
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.black,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.edit,
                                color: Colors.white,
                                size: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Screenshot shows:
                    // Name label on top border of textfield? Or just standard InputDecorator
                    // "Name"
                    // [ Marios Pappas ]
                    _buildLabelInput(
                      "Name",
                      _firstNameController,
                      hint: "First Name",
                    ), // Using First Name for now as combined might be complex to parse back

                    // Ideally we should have separate fields or just one Name field.
                    // Let's assume Name field updates firstName and we keep lastName hidden or empty if not provided?
                    // Or more likely, the screenshot shows "Name: Marios Pappas".
                    // I'll stick to simple fields for now.
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildLabelInput("School", _schoolController),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildLabelInput(
                            "University",
                            _universityController,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildLabelInput(
                      "About You",
                      _aboutController,
                      maxLines: 4,
                      maxLength: 300,
                    ),
                    const SizedBox(height: 16),
                    _buildLabelInput("Currently Studying", _studyingController),

                    const SizedBox(height: 32),
                    SizedBox(
                      width: 200,
                      child: ElevatedButton.icon(
                        onPressed: _saveProfile,
                        icon: const Icon(Icons.check, size: 20),
                        label: Text(
                          'Save',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFECC9),
                          foregroundColor: const Color(0xFFFF7B00),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildLabelInput(
    String label,
    TextEditingController controller, {
    int maxLines = 1,
    int? maxLength,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Custom label styling to match "floating" label look in screenshot somewhat
        // Actually screenshot uses standard looking outlined inputs with label.
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          maxLength: maxLength,
          decoration: InputDecoration(
            labelText: label,
            alignLabelWithHint: true,
            hintText: hint,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.grey),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.grey),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.black),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ],
    );
  }
}
