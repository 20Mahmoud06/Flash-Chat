// ignore_for_file: avoid_print

import 'package:flash_chat_app/core/utils/video_playback_url.dart';

void main() {
  const raw =
      'https://res.cloudinary.com/dixsmmll8/video/upload/v1712345678/clip_abc123.mp4';
  final p = videoPlaybackUrl(raw);
  final c = videoCompatUrl(raw);
  final r = videoRawUrl(p);
  final rc = videoRawUrl(c);
  final p2 = videoPlaybackUrl(p);
  print('raw    : $raw');
  print('play   : $p');
  print('compat : $c');
  print('play2  : $p2 (idempotent: ${p == p2})');
  print('back   : $r (roundtrip: ${r == raw})');
  print('back-c : $rc (roundtrip: ${rc == raw})');

  assert(p.contains('/upload/f_mp4,vc_h264:baseline:3.1,ac_aac/'));
  assert(c.contains(
      '/upload/f_mp4,vc_h264:baseline:3.1,ac_aac,c_limit,w_1280,q_auto:good/'));
  assert(videoPlaybackUrl(p) == p);
  assert(videoCompatUrl(c) == c);
  assert(videoPlaybackUrl(c) == c);
  assert(videoRawUrl(p) == raw);
  assert(videoRawUrl(c) == raw);
  assert(videoRawUrl(raw) == raw);
  assert(videoCompatUrl(p) == c);

  const nonCloud = 'https://example.com/x.mp4';
  assert(videoPlaybackUrl(nonCloud) == nonCloud);
  assert(videoCompatUrl(nonCloud) == nonCloud);
  assert(videoRawUrl(nonCloud) == nonCloud);

  print('OK');
}
