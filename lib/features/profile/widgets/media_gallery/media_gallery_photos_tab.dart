import 'package:flash_chat_app/core/utils/full_image_viewer.dart';
import 'package:flash_chat_app/features/chat/models/message_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'media_gallery_helpers.dart';

/// 3-column photo grid; each image tile opens [FullImageViewer] on tap.
class MediaGalleryPhotosTab extends StatelessWidget {
  final List<MessageModel> messages;

  const MediaGalleryPhotosTab({super.key, required this.messages});

  @override
  Widget build(BuildContext context) {
    final items = <({String url, MessageModel message, int mediaIndex})>[];
    for (final msg
        in messages.where((m) => m.messageType == MessageType.image)) {
      final urls = msg.mediaUrls ?? const [];
      for (var i = 0; i < urls.length; i++) {
        items.add((url: urls[i], message: msg, mediaIndex: i));
      }
    }
    if (items.isEmpty) {
      return const MediaGalleryEmptyState(
        label: 'No photos',
        icon: Icons.photo_library_outlined,
      );
    }
    return GridView.builder(
      padding: EdgeInsets.all(2.w),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        return GestureDetector(
          onTap: () {
            showDialog(
              context: context,
              barrierColor: Colors.transparent,
              builder: (_) => FullImageViewer(
                imageUrl: item.url,
                heroTag: 'media_gallery_${item.message.id}_${item.mediaIndex}',
              ),
            );
          },
          child: Image.network(
            item.url,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : Container(
                    color: Colors.black12,
                    child: const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.lightBlueAccent,
                        ),
                      ),
                    ),
                  ),
            errorBuilder: (context, error, stackTrace) => Container(
              color: Colors.black12,
              child: const Icon(Icons.broken_image_outlined,
                  color: Colors.grey, size: 28),
            ),
          ),
        );
      },
    );
  }
}