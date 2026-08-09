import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../domain/pin_model.dart';
import '../../../core/storage/b2_upload_service.dart';

/// Pins live at parties/{partyId}/pins/{pinId} instead of a top-level
/// 'pins' collection filtered by coupleId. This makes cross-party leakage
/// structurally impossible rather than dependent on every query
/// remembering a where() clause.
class PinsRepository {
  final _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _pinsRef(String partyId) {
    return _firestore.collection('parties').doc(partyId).collection('pins');
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchPins(String partyId) {
    return _pinsRef(partyId).snapshots();
  }

  /// Creates the pin doc and returns its new ID, so the caller can
  /// immediately start uploading photos against it (B2's presign
  /// endpoint needs a pinId up front to build the object key).
  Future<String> createPin({
    required String partyId,
    required LatLng location,
    required String caption,
  }) async {
    final user = FirebaseAuth.instance.currentUser!;
    final doc = await _pinsRef(partyId).add({
      'ownerUid': user.uid,
      'lat': location.latitude,
      'lng': location.longitude,
      'caption': caption,
      'createdAt': FieldValue.serverTimestamp(),
      'photos': <Map<String, dynamic>>[],
    });
    return doc.id;
  }

  /// Appends one uploaded photo to a pin. Max 5 enforced server-side
  /// too (see notify-server/api/b2.js) — this client-side check just
  /// avoids a wasted round trip when it's already obviously full.
  Future<void> addPhotoToPin({
    required String partyId,
    required String pinId,
    required PinPhoto photo,
  }) async {
    final ref = _pinsRef(partyId).doc(pinId);
    final doc = await ref.get();
    final existing = (doc.data()?['photos'] as List?)?.length ?? 0;
    if (existing >= 5) {
      throw StateError('A pin can only have 5 photos');
    }
    await ref.update({
      'photos': FieldValue.arrayUnion([photo.toMap()]),
    });
  }

  /// Removes one photo from a pin's `photos` array. Firestore's
  /// arrayRemove needs the exact same map that's stored, so this reads
  /// the doc first and matches by photo id rather than trying to
  /// reconstruct the map by hand.
  ///
  /// This only updates Firestore — deleting the actual B2 object is a
  /// separate call (see B2UploadService.deletePhoto), kept separate so
  /// a storage hiccup never leaves the Firestore doc in a half-updated
  /// state relative to what the user sees.
  Future<void> deletePhotoFromPin({
    required String partyId,
    required String pinId,
    required String photoId,
  }) async {
    final ref = _pinsRef(partyId).doc(pinId);
    final doc = await ref.get();
    final rawPhotos = (doc.data()?['photos'] as List?) ?? [];
    final match = rawPhotos.cast<Map<String, dynamic>>().firstWhere(
          (p) => p['id'] == photoId,
          orElse: () => <String, dynamic>{},
        );
    if (match.isEmpty) return;
    await ref.update({
      'photos': FieldValue.arrayRemove([match]),
    });
  }

  /// Deletes every one of a pin's uploaded photos from B2 before the
  /// pin doc itself goes away, so photos don't become orphaned storage
  /// (invisible in the app, but still billed against the bucket). Each
  /// photo delete is best-effort — one flaky network call shouldn't
  /// block the pin from being removed, so failures here are swallowed
  /// rather than propagated; worst case a photo object lingers in B2,
  /// which is far better than the user being unable to delete a pin.
  Future<void> _deletePhotosForPin({
    required String partyId,
    required String pinId,
    List<PinPhoto>? knownPhotos,
  }) async {
    List<PinPhoto> photos = knownPhotos ?? const [];
    if (knownPhotos == null) {
      final doc = await _pinsRef(partyId).doc(pinId).get();
      final raw = (doc.data()?['photos'] as List?) ?? const [];
      photos = raw
          .map((p) => PinPhoto.fromMap(Map<String, dynamic>.from(p as Map)))
          .toList();
    }
    for (final photo in photos) {
      try {
        await B2UploadService.deletePhoto(
          partyId: partyId,
          pinId: pinId,
          objectKey: photo.objectKey,
        );
      } catch (_) {
        // Best-effort cleanup — see doc comment above.
      }
    }
  }

  /// Deletes a single pin. Only the owner may delete their own pin
  /// (also enforced in Firestore security rules). Also deletes every
  /// photo the pin had in B2 first.
  Future<void> deletePin({
    required String partyId,
    required String pinId,
  }) async {
    await _deletePhotosForPin(partyId: partyId, pinId: pinId);
    await _pinsRef(partyId).doc(pinId).delete();
  }

  /// Deletes several pins at once (multi-select delete), cleaning up
  /// each one's B2 photos first.
  Future<void> deletePins({
    required String partyId,
    required List<String> pinIds,
  }) async {
    for (final id in pinIds) {
      await _deletePhotosForPin(partyId: partyId, pinId: id);
    }
    final batch = _firestore.batch();
    for (final id in pinIds) {
      batch.delete(_pinsRef(partyId).doc(id));
    }
    await batch.commit();
  }

  Future<void> deleteAllMyPins({
    required String partyId,
    required String ownerUid,
  }) async {
    final snapshot =
        await _pinsRef(partyId).where('ownerUid', isEqualTo: ownerUid).get();

    for (final doc in snapshot.docs) {
      final raw = (doc.data()['photos'] as List?) ?? const [];
      final photos = raw
          .map((p) => PinPhoto.fromMap(Map<String, dynamic>.from(p as Map)))
          .toList();
      await _deletePhotosForPin(partyId: partyId, pinId: doc.id, knownPhotos: photos);
    }

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}
