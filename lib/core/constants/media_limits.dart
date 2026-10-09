/// Maximum number of photos allowed in a single message.
const int kMaxPhotosPerMessage = 9;

/// Maximum number of videos allowed in a single message.
const int kMaxVideosPerMessage = 4;

/// How many media items of a single message may be uploaded at the same time.
///
/// Sequential uploads make the user wait for the sum of every request's
/// latency; overlapping them makes it the slowest single upload. The cap
/// keeps a batch from opening one socket per file at once, which is wasteful
/// on a free Cloudinary preset and heavy on an emulator.
const int kMaxConcurrentMediaUploads = 3;
