import 'package:cloud_firestore/cloud_firestore.dart';

/// Live location now lives at parties/{partyId}/liveLocation/{uid} instead
/// of couples/{coupleId}/liveLocation/{uid}. A user sharing location in
/// Party A will not appear in Party B's map — each party's liveLocation
/// subcollection is independent, so switching the active party is the
/// only thing that changes what's rendered.
class LiveLocationRepository {
  final _firestore = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _docRef(String partyId, String uid) {
    return _firestore
        .collection('parties')
        .doc(partyId)
        .collection('liveLocation')
        .doc(uid);
  }

  Future<void> updateLocation({
    required String partyId,
    required String uid,
    required double lat,
    required double lng,
    double heading = 0,
    double speed = 0,
  }) async {
    await _docRef(partyId, uid).set({
      'sharingEnabled': true,
      'lat': lat,
      'lng': lng,
      'heading': heading,
      'speed': speed,
      'lastUpdated': FieldValue.serverTimestamp(),
    });
  }

  Future<void> disableSharing({
    required String partyId,
    required String uid,
  }) async {
    await _docRef(partyId, uid).set({
      'sharingEnabled': false,
      'lat': FieldValue.delete(),
      'lng': FieldValue.delete(),
    }, SetOptions(merge: true));
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchLocation({
    required String partyId,
    required String uid,
  }) {
    return _docRef(partyId, uid).snapshots();
  }

  /// New: watch every member's live location in a party at once, needed
  /// now that a party can have up to 8 members instead of just one partner.
  Stream<QuerySnapshot<Map<String, dynamic>>> watchAllLocations(String partyId) {
    return _firestore
        .collection('parties')
        .doc(partyId)
        .collection('liveLocation')
        .where('sharingEnabled', isEqualTo: true)
        .snapshots();
  }
}
