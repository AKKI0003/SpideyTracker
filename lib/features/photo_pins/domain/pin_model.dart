import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

/// A single uploaded photo attached to a pin. [url] is a Backblaze B2
/// signed download URL (the bucket is private — see
/// notify-server/api/b2.js) valid 7 days from upload; [objectKey] is
/// the permanent B2 path, kept around so a photo can be deleted or a
/// fresh signed URL re-issued later without needing anything else.
/// [signedAt] records when [url] was actually signed, so the app can
/// tell a link is getting close to its 7-day expiry and quietly
/// re-sign it before it ever actually breaks — see SelfHealingPinImage.
///
/// [width]/[height] are the original pixel dimensions, read client-side
/// before upload — the photo viewer uses these to size its frame to
/// the real aspect ratio instead of guessing.
class PinPhoto {
  final String id;
  final String url;
  final String objectKey;
  final String caption;
  final DateTime? uploadedAt;
  final DateTime? signedAt;
  final String uploadedByUid;
  final double width;
  final double height;

  const PinPhoto({
    required this.id,
    required this.url,
    required this.objectKey,
    required this.caption,
    required this.uploadedAt,
    this.signedAt,
    required this.uploadedByUid,
    required this.width,
    required this.height,
  });

  double get aspectRatio => height <= 0 ? 1 : width / height;

  factory PinPhoto.fromMap(Map<String, dynamic> map) {
    return PinPhoto(
      id: map['id'] as String,
      url: map['url'] as String,
      objectKey: map['objectKey'] as String,
      caption: map['caption'] as String? ?? '',
      uploadedAt: (map['uploadedAt'] as Timestamp?)?.toDate(),
      // Absent on photos uploaded before this field existed — treated
      // as "unknown age" by SelfHealingPinImage, which then falls back
      // to its reactive (on-load-error) refresh path instead of a
      // proactive one for those.
      signedAt: (map['signedAt'] as Timestamp?)?.toDate(),
      uploadedByUid: map['uploadedByUid'] as String? ?? '',
      width: (map['width'] as num?)?.toDouble() ?? 1,
      height: (map['height'] as num?)?.toDouble() ?? 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'url': url,
      'objectKey': objectKey,
      'caption': caption,
      // Firestore array elements can't use FieldValue.serverTimestamp(),
      // so the caller stamps a real client DateTime before this goes
      // into an arrayUnion() — see PinsRepository.addPhotoToPin.
      'uploadedAt': uploadedAt != null ? Timestamp.fromDate(uploadedAt!) : null,
      'signedAt': signedAt != null ? Timestamp.fromDate(signedAt!) : null,
      'uploadedByUid': uploadedByUid,
      'width': width,
      'height': height,
    };
  }

  PinPhoto copyWith({String? url, DateTime? signedAt}) {
    return PinPhoto(
      id: id,
      url: url ?? this.url,
      objectKey: objectKey,
      caption: caption,
      uploadedAt: uploadedAt,
      signedAt: signedAt ?? this.signedAt,
      uploadedByUid: uploadedByUid,
      width: width,
      height: height,
    );
  }
}

class PinModel {
  final String id;
  final String ownerUid;
  final LatLng location;
  final String caption;
  final DateTime? createdAt;
  final List<PinPhoto> photos;

  PinModel({
    required this.id,
    required this.ownerUid,
    required this.location,
    required this.caption,
    required this.createdAt,
    this.photos = const [],
  });

  factory PinModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    final rawPhotos = data['photos'] as List<dynamic>? ?? const [];
    return PinModel(
      id: doc.id,
      ownerUid: data['ownerUid'] as String,
      location: LatLng(
        (data['lat'] as num).toDouble(),
        (data['lng'] as num).toDouble(),
      ),
      caption: data['caption'] as String? ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      photos: rawPhotos
          .map((p) => PinPhoto.fromMap(Map<String, dynamic>.from(p as Map)))
          .toList(),
    );
  }
}
