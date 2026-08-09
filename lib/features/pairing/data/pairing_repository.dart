import 'package:cloud_firestore/cloud_firestore.dart';

class PairingRepository {
  final _firestore = FirebaseFirestore.instance;

  Future<void> leaveCouple({
    required String uid,
    required String coupleId,
  }) async {
    await _firestore.collection('couples').doc(coupleId).update({
      'memberUids': FieldValue.arrayRemove([uid]),
    });
    await _firestore.collection('users').doc(uid).update({
      'coupleId': null,
    });
  }
}