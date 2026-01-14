import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String firstName;
  final String lastName;
  final String school;
  final String university;
  final String aboutYou;
  final String currentlyStudying;
  final String profilePicUrl;
  final List<String> friendIds;
  final List<String> thoughts; // Just strings for now based on UI
  final List<String> momentUrls; // Image URLs
  final List<String> achievements; // Just strings or IDs based on UI

  UserModel({
    required this.uid,
    required this.firstName,
    required this.lastName,
    required this.school,
    required this.university,
    required this.aboutYou,
    required this.currentlyStudying,
    this.profilePicUrl = '',
    this.friendIds = const [],
    this.thoughts = const [],
    this.momentUrls = const [],
    this.achievements = const [],
  });

  String get fullName => '$firstName $lastName';

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserModel(
      uid: doc.id,
      firstName: data['firstName'] ?? '',
      lastName: data['lastName'] ?? '',
      school: data['school'] ?? '',
      university: data['university'] ?? '',
      aboutYou: data['aboutYou'] ?? '',
      currentlyStudying: data['currentlyStudying'] ?? '',
      profilePicUrl: data['profilePicUrl'] ?? '',
      friendIds: List<String>.from(data['friendIds'] ?? []),
      thoughts: List<String>.from(data['thoughts'] ?? []),
      momentUrls: List<String>.from(data['momentUrls'] ?? []),
      achievements: List<String>.from(data['achievements'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'firstName': firstName,
      'lastName': lastName,
      'school': school,
      'university': university,
      'aboutYou': aboutYou,
      'currentlyStudying': currentlyStudying,
      'profilePicUrl': profilePicUrl,
      'friendIds': friendIds,
      'thoughts': thoughts,
      'momentUrls': momentUrls,
      'achievements': achievements,
    };
  }

  UserModel copyWith({
    String? firstName,
    String? lastName,
    String? school,
    String? university,
    String? aboutYou,
    String? currentlyStudying,
    String? profilePicUrl,
    List<String>? friendIds,
    List<String>? thoughts,
    List<String>? momentUrls,
    List<String>? achievements,
  }) {
    return UserModel(
      uid: uid,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      school: school ?? this.school,
      university: university ?? this.university,
      aboutYou: aboutYou ?? this.aboutYou,
      currentlyStudying: currentlyStudying ?? this.currentlyStudying,
      profilePicUrl: profilePicUrl ?? this.profilePicUrl,
      friendIds: friendIds ?? this.friendIds,
      thoughts: thoughts ?? this.thoughts,
      momentUrls: momentUrls ?? this.momentUrls,
      achievements: achievements ?? this.achievements,
    );
  }
}
