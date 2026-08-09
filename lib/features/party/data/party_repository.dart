import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../domain/party_model.dart';

/// Thrown for any expected, user-facing failure (full party, bad code, etc.)
/// so screens can show a specific message instead of a generic error.
class PartyException implements Exception {
  final String message;
  PartyException(this.message);
  @override
  String toString() => message;
}

class PartyRepository {
  final _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _parties =>
      _firestore.collection('parties');

  CollectionReference<Map<String, dynamic>> get _inviteCodes =>
      _firestore.collection('inviteCodes');

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _firestore.collection('users').doc(uid);

  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O/1/I ambiguity
    final rand = Random.secure();
    return List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  /// Live stream of every party the given user currently belongs to.
  /// Used to drive the party switcher UI.
  Stream<List<PartyModel>> watchUserParties(String uid) {
    // No .orderBy() here on purpose: arrayContains + orderBy on a
    // different field requires a Firestore composite index, which
    // doesn't exist by default and makes the query fail silently from
    // the UI's point of view (stream errors, spinner never resolves).
    // Sorting client-side avoids that footgun entirely.
    return _parties
        .where('memberUids', arrayContains: uid)
        .snapshots()
        .map((snap) {
      final parties = snap.docs.map(PartyModel.fromDoc).toList();
      parties.sort((a, b) {
        final aTime = a.createdAt ?? DateTime(0);
        final bTime = b.createdAt ?? DateTime(0);
        return aTime.compareTo(bTime);
      });
      return parties;
    });
  }

  Stream<PartyModel?> watchParty(String partyId) {
    return _parties.doc(partyId).snapshots().map(
          (doc) => doc.exists ? PartyModel.fromDoc(doc) : null,
        );
  }

  /// Creates a new party owned by [uid], adds it to their party list, and
  /// makes it their active party. Returns the new party's id.
  Future<String> createParty({
    required String uid,
    required String name,
    String iconId = 'default',
    String themeId = 'default',
  }) async {
    final partyRef = _parties.doc();
    final inviteCode = _generateInviteCode();

    await partyRef.set({
      'name': name.trim().isEmpty ? 'New Party' : name.trim(),
      'ownerUid': uid,
      'memberUids': [uid],
      'memberRoles': {uid: 'owner'},
      'iconId': iconId,
      'themeId': themeId,
      'inviteCode': inviteCode,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await _inviteCodes.doc(inviteCode).set({
      'partyId': partyRef.id,
      'createdBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await _userDoc(uid).update({
      'partyIds': FieldValue.arrayUnion([partyRef.id]),
      'activePartyId': partyRef.id,
    });

    return partyRef.id;
  }

  /// Joins an existing party by its 6-character invite code.
  /// Codes stay valid and reusable until the party is full — they are not
  /// single-use, since a party can have multiple invitees.
  Future<String> joinWithCode({
    required String uid,
    required String rawCode,
  }) async {
    final code = rawCode.trim().toUpperCase();
    final codeSnap = await _inviteCodes.doc(code).get();
    if (!codeSnap.exists) {
      throw PartyException('Invalid invite code');
    }

    final partyId = codeSnap.data()!['partyId'] as String;
    final partyRef = _parties.doc(partyId);

    return _firestore.runTransaction<String>((tx) async {
      final partySnap = await tx.get(partyRef);
      if (!partySnap.exists) {
        throw PartyException('This party no longer exists');
      }
      final party = PartyModel.fromDoc(partySnap);

      if (party.memberUids.contains(uid)) {
        // Already a member — just make it active, don't error.
        tx.update(_userDoc(uid), {'activePartyId': partyId});
        return partyId;
      }
      if (party.isFull) {
        throw PartyException('This party is full (max ${PartyModel.maxMembers})');
      }

      tx.update(partyRef, {
        'memberUids': FieldValue.arrayUnion([uid]),
        'memberRoles.$uid': 'member',
      });
      tx.update(_userDoc(uid), {
        'partyIds': FieldValue.arrayUnion([partyId]),
        'activePartyId': partyId,
      });
      return partyId;
    });
  }

  /// Sets which party is currently shown in the UI. Does not affect
  /// membership — every party's pins/messages/locations stay untouched.
  Future<void> setActiveParty({required String uid, required String partyId}) {
    return _userDoc(uid).update({'activePartyId': partyId});
  }

  Future<void> renameParty({required String partyId, required String newName}) {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) throw PartyException('Party name cannot be empty');
    return _parties.doc(partyId).update({'name': trimmed});
  }

  /// Removes [uid] from a party. If they were the owner and members remain,
  /// ownership transfers to the next-oldest member rather than orphaning
  /// the party.
  Future<void> leaveParty({required String uid, required String partyId}) async {
    final partyRef = _parties.doc(partyId);
    final userRef = _userDoc(uid);

    await _firestore.runTransaction((tx) async {
      // Firestore transactions require every read to happen before any
      // write — this used to read userRef AFTER already calling
      // tx.delete()/tx.update() on partyRef above, which throws every
      // single time ("all reads must be executed before all writes").
      // That's what was actually breaking leave, not a security rule.
      final snap = await tx.get(partyRef);
      final userSnap = await tx.get(userRef);
      if (!snap.exists) return;
      final party = PartyModel.fromDoc(snap);

      final remaining = party.memberUids.where((m) => m != uid).toList();

      if (remaining.isEmpty) {
        tx.delete(partyRef);
      } else {
        final updates = <String, dynamic>{
          'memberUids': FieldValue.arrayRemove([uid]),
          'memberRoles.$uid': FieldValue.delete(),
        };
        if (party.ownerUid == uid) {
          updates['ownerUid'] = remaining.first;
          updates['memberRoles.${remaining.first}'] = 'owner';
        }
        tx.update(partyRef, updates);
      }

      final userData = userSnap.data();
      final currentActive = userData?['activePartyId'] as String?;
      tx.update(userRef, {
        'partyIds': FieldValue.arrayRemove([partyId]),
        if (currentActive == partyId) 'activePartyId': null,
      });
    });
  }

  /// Owner-only. Deletes the party outright. Subcollections (pins,
  /// messages, liveLocation, activityLog) must be cleaned up by a backend
  /// job / Cloud Function since Firestore doesn't cascade-delete —
  /// documented here so it isn't forgotten during Feature 3/5 buildout.
  Future<void> deleteParty({required String uid, required String partyId}) async {
    final partyRef = _parties.doc(partyId);
    final snap = await partyRef.get();
    if (!snap.exists) return;
    final party = PartyModel.fromDoc(snap);
    if (party.ownerUid != uid) {
      throw PartyException('Only the party owner can delete this party');
    }

    // Only the CALLER's own user doc is touched here — a user can only
    // write their own doc (see firestore.rules), so looping over every
    // other member's doc the way this used to always made the whole
    // batch fail (Firestore batches are atomic: one illegal write
    // aborts everything, including the party delete itself). Other
    // members don't need cleanup here anyway: watchUserParties queries
    // the `parties` collection directly (memberUids array-contains),
    // not each user's own partyIds bookkeeping field, so deleting the
    // party doc itself already removes it from their party list.
    final batch = _firestore.batch();
    batch.update(_userDoc(uid), {
      'partyIds': FieldValue.arrayRemove([partyId]),
    });
    batch.delete(partyRef);
    batch.delete(_inviteCodes.doc(party.inviteCode));
    await batch.commit();
  }
}
