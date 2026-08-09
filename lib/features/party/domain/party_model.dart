import 'package:cloud_firestore/cloud_firestore.dart';

/// A party is a group of up to [PartyModel.maxMembers] users who share
/// pins, live location, messages, and an activity log — completely
/// isolated from every other party a user belongs to.
class PartyModel {
  static const int maxMembers = 8;

  final String id;
  final String name;
  final String ownerUid;
  final List<String> memberUids;
  final Map<String, String> memberRoles; // uid -> role, future-ready
  final String iconId; // future-ready, e.g. which spider icon represents the party
  final String themeId; // future-ready, party-level color theme
  final String inviteCode;
  final DateTime? createdAt;

  PartyModel({
    required this.id,
    required this.name,
    required this.ownerUid,
    required this.memberUids,
    required this.memberRoles,
    required this.iconId,
    required this.themeId,
    required this.inviteCode,
    required this.createdAt,
  });

  bool get isFull => memberUids.length >= maxMembers;

  bool isOwner(String uid) => ownerUid == uid;

  factory PartyModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return PartyModel(
      id: doc.id,
      name: data['name'] as String? ?? 'Unnamed Party',
      ownerUid: data['ownerUid'] as String,
      memberUids: List<String>.from(data['memberUids'] as List? ?? const []),
      memberRoles: Map<String, String>.from(
        (data['memberRoles'] as Map?) ?? const {},
      ),
      iconId: data['iconId'] as String? ?? 'default',
      themeId: data['themeId'] as String? ?? 'default',
      inviteCode: data['inviteCode'] as String? ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'ownerUid': ownerUid,
        'memberUids': memberUids,
        'memberRoles': memberRoles,
        'iconId': iconId,
        'themeId': themeId,
        'inviteCode': inviteCode,
      };
}
