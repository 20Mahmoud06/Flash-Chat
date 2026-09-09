/// Builds playback-safe URLs for Cloudinary videos.
///
/// Cloudinary stores the raw uploaded file, which may use a container/codec a
/// viewer's device can't decode (e.g. HEVC videos from iOS/Android cameras).
/// Requesting the video with the `f_mp4,vc_h264:baseline:3.1,ac_aac`
/// transformation makes Cloudinary re-encode it to a plain H.264/AAC MP4
/// that older Android devices can play.
///
/// `videoPlaybackUrl` returns such an H.264 URL. It is idempotent: passing a
/// URL that already has the transformation returns it unchanged. `videoRawUrl`
/// returns the original (untransformed) URL so a temporarily-failing
/// transformation can fall back to the source file.
///
/// `videoCompatUrl` returns an H.264/AAC URL that is guaranteed to be freshly
/// re-encoded by Cloudinary (resizing forces a re-encode even when the source
/// is already H.264 MP4, which a codec-only transform could otherwise pass
/// through untouched). The stream is capped at 1280px wide and encoded with
/// baseline profile / level 3.1, so it decodes on weak or quirky hardware
/// decoders (older Huawei / Honor HiSilicon chips) that reject high-profile
/// or high-level H.264.
library;

const String _uploadMarker = '/upload/';
const String _playbackTransform = 'f_mp4,vc_h264:baseline:3.1,ac_aac';
const String _compatTransform =
    'f_mp4,vc_h264:baseline,ac_aac,c_limit,w_720,h_1280,q_auto:eco';

bool _hasTransformedPath(String afterUpload) =>
    afterUpload.contains('f_mp4') || afterUpload.contains('vc_h264');

bool _hasCompatTransform(String afterUpload) => afterUpload.contains('w_720');

String videoPlaybackUrl(String url) {
  if (url.isEmpty) return url;
  try {
    final uri = Uri.parse(url);
    final path = uri.path;
    final idx = path.indexOf(_uploadMarker);
    if (idx == -1) return url;
    final after = path.substring(idx + _uploadMarker.length);
    if (_hasTransformedPath(after)) return url;

    final newPath =
        '${path.substring(0, idx + _uploadMarker.length)}$_playbackTransform/$after';
    return uri.replace(path: newPath).toString();
  } catch (_) {
    return url;
  }
}

String videoRawUrl(String url) {
  if (url.isEmpty) return url;
  try {
    final uri = Uri.parse(url);
    final path = uri.path;
    final idx = path.indexOf(_uploadMarker);
    if (idx == -1) return url;

    final after = path.substring(idx + _uploadMarker.length);
    if (!_hasTransformedPath(after)) return url;

    final cleaned = _stripTransformSegment(after);
    if (cleaned == after) return url;

    final newPath = '${path.substring(0, idx + _uploadMarker.length)}$cleaned';
    return uri.replace(path: newPath).toString();
  } catch (_) {
    return url;
  }
}

/// Builds a device-compatibility fallback URL for Cloudinary videos.
///
/// Forces Cloudinary to re-encode the video as H.264 capped at 1280px wide
/// (see the library doc comment). Idempotent: URLs that already request the
/// compat re-encode are returned unchanged.
String videoCompatUrl(String url) {
  if (url.isEmpty) return url;
  try {
    final uri = Uri.parse(url);
    final path = uri.path;
    final idx = path.indexOf(_uploadMarker);
    if (idx == -1) return url;
    final after = path.substring(idx + _uploadMarker.length);
    if (_hasCompatTransform(after)) return url;

    final cleaned = _stripTransformSegment(after);
    final newPath =
        '${path.substring(0, idx + _uploadMarker.length)}$_compatTransform/$cleaned';
    return uri.replace(path: newPath).toString();
  } catch (_) {
    return url;
  }
}

/// Builds a JPEG poster / thumbnail frame from a Cloudinary video URL.
/// Requests the first frame (`so_0`) as a plain JPEG image so it can be shown
/// in `Image.network` / `NetworkImage` (bubble poster, reply preview).
/// Idempotent: URLs that already request an image frame are returned as-is.
String videoThumbnailUrl(String url) {
  if (url.isEmpty) return url;
  try {
    final uri = Uri.parse(url);
    final path = uri.path;
    final idx = path.indexOf(_uploadMarker);
    if (idx == -1) return url;

    final after = path.substring(idx + _uploadMarker.length);
    if (after.contains('f_jpg') || after.contains('.jpg')) return url;

    final cleaned = _stripTransformSegment(after);
    final newPath =
        '${path.substring(0, idx + _uploadMarker.length)}f_jpg,so_0/$cleaned';
    return uri.replace(path: newPath).toString();
  } catch (_) {
    return url;
  }
}

/// Drops a leading Cloudinary transformation segment (a path segment that
/// contains commas, e.g. `f_mp4,vc_h264`). File names never contain commas,
/// so this is safe for both raw and already-transformed URLs.
String _stripTransformSegment(String afterUpload) {
  final segments = afterUpload.split('/');
  if (segments.first.contains(',')) {
    return segments.sublist(1).join('/');
  }
  return afterUpload;
}
