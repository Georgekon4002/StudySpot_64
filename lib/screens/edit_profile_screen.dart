import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import '../models/user_model.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;

  // Dropdown state
  String? _selectedSchool;
  String? _selectedUni;
  final List<String> _uniOptions = ['NTUA'];
  final List<String> _schoolOptions = [
    'ECE',
    'Mech',
    'Civil',
    'Chem',
    'AMPS',
    'Arch',
    'Metal',
    'Survey',
    'Naval',
  ];

  late TextEditingController _aboutController;
  late TextEditingController _studyingController; // Read-only for display
  String _profilePicUrl = '';
  File? _localImageFile;

  bool _isLoading = true;
  bool _isSaving = false;

  final List<String> _studyingOptions = [
    'No Subject',
    'ProgIntro',
    'ProgTech',
    'HCI',
    'FoCS',
    'SoftEng',
    'CompArch',
    'ProgLang',
  ];

  @override
  void initState() {
    super.initState();
    _firstNameController = TextEditingController();
    _lastNameController = TextEditingController();
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

        if (_schoolOptions.contains(userData.school)) {
          _selectedSchool = userData.school;
        }
        if (_uniOptions.contains(userData.university)) {
          _selectedUni = userData.university;
        }
        _aboutController.text = userData.aboutYou;
        _studyingController.text = userData.currentlyStudying;
        setState(() {
          _profilePicUrl = userData.profilePicUrl;
        });
      }
    }
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _pickImage() async {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Take Photo'),
                onTap: () async {
                  Navigator.pop(context);
                  final picker = ImagePicker();
                  final pickedFile = await picker.pickImage(
                    source: ImageSource.camera,
                  );
                  if (pickedFile != null) {
                    setState(() {
                      _localImageFile = File(pickedFile.path);
                    });
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from Gallery'),
                onTap: () async {
                  Navigator.pop(context);
                  final picker = ImagePicker();
                  final pickedFile = await picker.pickImage(
                    source: ImageSource.gallery,
                  );
                  if (pickedFile != null) {
                    setState(() {
                      _localImageFile = File(pickedFile.path);
                    });
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<String> _uploadImage(String uid) async {
    if (_localImageFile == null) return _profilePicUrl;

    try {
      // Use a unique name to prevent caching issues
      final String fileName =
          'profile_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = FirebaseStorage.instance
          .ref()
          .child('users')
          .child(uid)
          .child(fileName);

      // Await the task snapshot to ensure upload is complete
      final TaskSnapshot snapshot = await ref.putFile(_localImageFile!);

      if (snapshot.state == TaskState.success) {
        final url = await ref.getDownloadURL();
        debugPrint("Image uploaded successfully: $url");
        return url;
      } else {
        throw FirebaseException(
          plugin: 'firebase_storage',
          code: 'upload-failed',
          message: 'Upload task was not successful',
        );
      }
    } catch (e) {
      debugPrint("Error uploading image: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to upload image: $e')));
      return _profilePicUrl;
    }
  }

  void _showStudyingSearch() {
    // Only show options if NTUA and ECE are selected
    if (_selectedUni == 'NTUA' && _selectedSchool == 'ECE') {
      _showSearchSheet(_studyingOptions);
    } else {
      // Otherwise show empty list (or message)
      _showSearchSheet([]);
    }
  }

  void _showSearchSheet(List<String> options) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return _StudyingSearchModal(
              options: options,
              onSelected: (selected) {
                setState(() {
                  _studyingController.text = (selected == 'No Subject')
                      ? ''
                      : selected;
                });
                Navigator.pop(context);
              },
            );
          },
        );
      },
    );
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Upload image first
    String newProfilePicUrl = _profilePicUrl;
    if (_localImageFile != null) {
      newProfilePicUrl = await _uploadImage(user.uid);
    }

    final Map<String, dynamic> updateData = {
      'firstName': _firstNameController.text,
      'lastName': _lastNameController.text,
      'school': _selectedSchool ?? '',
      'university': _selectedUni ?? '',
      'aboutYou': _aboutController.text,
      'currentlyStudying': _studyingController.text,
      'profilePicUrl': newProfilePicUrl,
    };

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(updateData, SetOptions(merge: true));

      if (mounted) {
        setState(() {
          _profilePicUrl = newProfilePicUrl;
          _localImageFile = null;
        });
      }
    } catch (e) {
      debugPrint("Error saving profile: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save profile: $e')));
      }
    }

    if (mounted) {
      setState(() => _isSaving = false);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    ImageProvider? imageProvider;
    if (_localImageFile != null) {
      imageProvider = FileImage(_localImageFile!);
    } else if (_profilePicUrl.isNotEmpty) {
      imageProvider = NetworkImage(_profilePicUrl);
    } else {
      imageProvider = const AssetImage('assets/images/default_avatar.png');
    }

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
      body: (_isLoading || _isSaving)
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Profile Pic Edit
                    Center(
                      child: GestureDetector(
                        onTap: _pickImage,
                        child: Stack(
                          children: [
                            CircleAvatar(
                              radius: 40,
                              backgroundColor: Colors.grey[200],
                              backgroundImage: imageProvider,
                              onBackgroundImageError: (_, __) {},
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
                    ),
                    const SizedBox(height: 20),

                    _buildLabelInput(
                      "First Name",
                      _firstNameController,
                      hint: "First Name",
                    ),
                    const SizedBox(height: 16),
                    _buildLabelInput(
                      "Last Name",
                      _lastNameController,
                      hint: "Last Name",
                    ),

                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              DropdownButtonFormField<String>(
                                value: _selectedSchool,
                                items: _schoolOptions.map((String value) {
                                  return DropdownMenuItem<String>(
                                    value: value,
                                    child: Text(value),
                                  );
                                }).toList(),
                                onChanged: (newValue) {
                                  setState(() {
                                    _selectedSchool = newValue;
                                  });
                                },
                                decoration: InputDecoration(
                                  labelText: 'School',
                                  alignLabelWithHint: true,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                      color: Colors.grey,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                      color: Colors.grey,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                      color: Colors.black,
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                ),
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Colors.black,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              DropdownButtonFormField<String>(
                                value: _selectedUni,
                                items: _uniOptions.map((String value) {
                                  return DropdownMenuItem<String>(
                                    value: value,
                                    child: Text(value),
                                  );
                                }).toList(),
                                onChanged: (newValue) {
                                  setState(() {
                                    _selectedUni = newValue;
                                  });
                                },
                                decoration: InputDecoration(
                                  labelText: 'University',
                                  alignLabelWithHint: true,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                      color: Colors.grey,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                      color: Colors.grey,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                      color: Colors.black,
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                ),
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Colors.black,
                                ),
                              ),
                            ],
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

                    GestureDetector(
                      onTap: _showStudyingSearch,
                      child: AbsorbPointer(
                        child: _buildLabelInput(
                          "Currently Studying",
                          _studyingController,
                          hint: "Select Subject",
                        ),
                      ),
                    ),

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

class _StudyingSearchModal extends StatefulWidget {
  final List<String> options;
  final ValueChanged<String> onSelected;

  const _StudyingSearchModal({required this.options, required this.onSelected});

  @override
  State<_StudyingSearchModal> createState() => _StudyingSearchModalState();
}

class _StudyingSearchModalState extends State<_StudyingSearchModal> {
  late List<String> _filteredOptions;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filteredOptions = widget.options;
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _filteredOptions = widget.options
          .where(
            (option) => option.toLowerCase().contains(
              _searchController.text.toLowerCase(),
            ),
          )
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Text(
            "Select Subject",
            style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          if (widget.options.isEmpty) ...[
            Expanded(
              child: Center(
                child: Text(
                  "No subjects available for this school.",
                  style: GoogleFonts.inter(fontSize: 14, color: Colors.grey),
                ),
              ),
            ),
          ] else ...[
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: "Search...",
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _filteredOptions.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    title: Text(
                      _filteredOptions[index],
                      style: GoogleFonts.inter(),
                    ),
                    onTap: () => widget.onSelected(_filteredOptions[index]),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
