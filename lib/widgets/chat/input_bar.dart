import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/matrix.dart';
import 'package:mime/mime.dart';

class InputBar extends StatelessWidget {
  final TextEditingController sendController;
  final FocusNode composerFocusNode;
  final Room room;
  final bool isSendingMedia;
  final Function onSendMessage;
  final Function onStartSendingMedia;
  final Function onFinishedSendingMedia;

  const InputBar({
    super.key,
    required this.sendController,
    required this.composerFocusNode,
    required this.isSendingMedia,
    required this.room,
    required this.onSendMessage,
    required this.onStartSendingMedia,
    required this.onFinishedSendingMedia,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF10151D),
        border: Border(
          top: BorderSide(color: Color(0xFF1D2530), width: 1),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            onPressed: () {
              _showAttachmentMenu(context);
            },
            icon: const Icon(Icons.add_circle_outline,
            color: Color(0xFFF2F4F7)),
          ),
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48, maxHeight: 140),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1A212C),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFF263041)),
                ),
                child: Scrollbar(
                  child: TextField(
                    controller: sendController,
                    focusNode: composerFocusNode,
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.multiline,
                    minLines: 1,
                    maxLines: 6,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      hintText: 'Message',
                      hintStyle: TextStyle(color: Color(0xFF8B96A5)),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          InkWell(
            onTap: _send,
            borderRadius: BorderRadius.circular(24),
            child: Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: Color(0xFF2E7DFF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.send_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAttachmentMenu(BuildContext context) async {
    if (isSendingMedia) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF10151D),
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.image_outlined, color: Colors.white),
                title: const Text('Photo',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _pickImageOrVideo(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam_outlined,
                    color: Colors.white),
                title: const Text(
                  'Video',
                  style: TextStyle(color: Colors.white)
                ),
                onTap: () {
                  Navigator.pop(context);
                  _pickVideo();
                },
              ),
              ListTile(
                leading: const Icon(Icons.attach_file, color: Colors.white),
                title: const Text('File', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _pickDocument();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _send() {
    final message = sendController.text.trim();
    if (message.isEmpty) return;
    room.sendTextEvent(message);
    sendController.clear();
    onSendMessage();
  }

  Future<void> _pickImageOrVideo(BuildContext context) async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: const Color(0xFF10151D),
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.white),
                title: const Text('Gallery',
                    style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera, color: Colors.white),
                title: const Text('Camera',
                    style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
            ],
          ),
        );
      },
    );

    if (source == null) return;

    final picked = await picker.pickImage(source: source, imageQuality: 85);
    if (picked == null) return;

    await _sendPickedFile(
      File(picked.path),
      forcedMime: 'image/jpeg',
    );
  }

  Future<void> _sendPickedFile(File file, {String? forcedMime}) async {
    if (isSendingMedia) return;
    onStartSendingMedia();

    try {
      final mimeType =
          forcedMime ?? lookupMimeType(file.path) ?? 'application/octet-stream';
      final fileName = file.path.split(Platform.pathSeparator).last;
      final bytes = await file.readAsBytes();

      final matrixFile = MatrixFile(
        bytes: bytes,
        name: fileName,
        mimeType: mimeType,
      );

      await room.sendFileEvent(matrixFile);
    } finally {
      onFinishedSendingMedia();
    }
  }

  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final picked = await picker.pickVideo(source: ImageSource.gallery);
    if (picked == null) return;

    await _sendPickedFile(
      File(picked.path),
      forcedMime: 'video/mp4',
    );
  }

  Future<void> _pickDocument() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.any,
      withData: false,
    );

    if (result == null || result.files.single.path == null) return;

    await _sendPickedFile(File(result.files.single.path!));
  }
}
