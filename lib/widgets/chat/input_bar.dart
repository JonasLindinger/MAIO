import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/matrix.dart';
import 'package:mime/mime.dart';
import 'emoji_picker_sheet.dart';
import '../chat/message_bubble.dart'; // for MessageBubbleState.stripReplyFallback

class InputBar extends StatefulWidget {
  final TextEditingController sendController;
  final FocusNode composerFocusNode;
  final Room room;
  final bool isSendingMedia;
  final Function onSendMessage;
  final Function onStartSendingMedia;
  final Function onFinishedSendingMedia;

  final Event? replyToEvent;
  final VoidCallback? onCancelReply;

  const InputBar({
    super.key,
    required this.sendController,
    required this.composerFocusNode,
    required this.isSendingMedia,
    required this.room,
    required this.onSendMessage,
    required this.onStartSendingMedia,
    required this.onFinishedSendingMedia,
    this.replyToEvent,
    this.onCancelReply,
  });

  @override
  State<InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<InputBar> {
  bool _showEmojiPicker = false;

  @override
  void initState() {
    super.initState();
    widget.composerFocusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.composerFocusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (widget.composerFocusNode.hasFocus && _showEmojiPicker) {
      setState(() => _showEmojiPicker = false);
    }
  }

  void _toggleEmojiPicker() {
    if (_showEmojiPicker) {
      widget.composerFocusNode.requestFocus();
    } else {
      widget.composerFocusNode.unfocus();
      setState(() => _showEmojiPicker = true);
    }
  }

  void _send() {
    final message = widget.sendController.text.trim();
    if (message.isEmpty) return;

    if (widget.replyToEvent != null) {
      widget.room.sendTextEvent(message, inReplyTo: widget.replyToEvent);
      widget.onCancelReply?.call();
    } else {
      widget.room.sendTextEvent(message);
    }

    widget.sendController.clear();
    widget.onSendMessage();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF10151D),
        border: Border(top: BorderSide(color: Color(0xFF1D2530), width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.replyToEvent != null)
            _ReplyBanner(
              event: widget.replyToEvent!,
              onCancel: widget.onCancelReply ?? () {},
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: () => _showAttachmentMenu(context),
                  icon: const Icon(Icons.add_circle_outline,
                      color: Color(0xFFF2F4F7)),
                ),
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                        minHeight: 48, maxHeight: 140),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A212C),
                        borderRadius: BorderRadius.circular(24),
                        border:
                        Border.all(color: const Color(0xFF263041)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Scrollbar(
                              child: TextField(
                                controller: widget.sendController,
                                focusNode: widget.composerFocusNode,
                                style: const TextStyle(color: Colors.white),
                                keyboardType: TextInputType.multiline,
                                minLines: 1,
                                maxLines: 6,
                                textInputAction: TextInputAction.newline,
                                decoration: const InputDecoration(
                                  hintText: 'Message',
                                  hintStyle:
                                  TextStyle(color: Color(0xFF8B96A5)),
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 14),
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                                _showEmojiPicker
                                    ? Icons.keyboard_alt_outlined
                                    : Icons.emoji_emotions_outlined,
                                color: const Color(0xFF8B96A5)),
                            onPressed: _toggleEmojiPicker,
                          ),
                        ],
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
                    child: const Icon(Icons.send_rounded,
                        color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
          if (_showEmojiPicker)
            EmojiPickerSheet(
              onPick: (emoji) {
                final text = widget.sendController.text;
                final selection = widget.sendController.selection;
                final newText = text.replaceRange(
                  selection.start.clamp(0, text.length),
                  selection.end.clamp(0, text.length),
                  emoji,
                );
                widget.sendController.value = TextEditingValue(
                  text: newText,
                  selection: TextSelection.collapsed(
                    offset: (selection.start.clamp(0, text.length)) + emoji.length,
                  ),
                );
              },
              onBackspacePressed: () {
                final text = widget.sendController.text;
                final selection = widget.sendController.selection;
                if (selection.start > 0) {
                  final newText = text.replaceRange(
                    selection.start - 1,
                    selection.start,
                    '',
                  );
                  widget.sendController.value = TextEditingValue(
                    text: newText,
                    selection: TextSelection.collapsed(
                      offset: selection.start - 1,
                    ),
                  );
                }
              },
            ),
        ],
      ),
    );
  }

  Future<void> _showAttachmentMenu(BuildContext context) async {
    if (widget.isSendingMedia) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF10151D),
      shape: const RoundedRectangleBorder(
          borderRadius:
          BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Wrap(children: [
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.image_outlined,
                color: Colors.white),
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
            title: const Text('Video',
                style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              _pickVideo();
            },
          ),
          ListTile(
            leading: const Icon(Icons.attach_file, color: Colors.white),
            title: const Text('File',
                style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              _pickDocument();
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _pickImageOrVideo(BuildContext context) async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: const Color(0xFF10151D),
      builder: (context) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.photo_library,
                color: Colors.white),
            title: const Text('Gallery',
                style: TextStyle(color: Colors.white)),
            onTap: () =>
                Navigator.pop(context, ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera,
                color: Colors.white),
            title: const Text('Camera',
                style: TextStyle(color: Colors.white)),
            onTap: () =>
                Navigator.pop(context, ImageSource.camera),
          ),
        ]),
      ),
    );
    if (source == null) return;
    final picked =
    await picker.pickImage(source: source, imageQuality: 85);
    if (picked == null) return;
    await _sendPickedFile(File(picked.path),
        forcedMime: 'image/jpeg');
  }

  Future<void> _sendPickedFile(File file,
      {String? forcedMime}) async {
    if (widget.isSendingMedia) return;
    widget.onStartSendingMedia();
    try {
      final mimeType = forcedMime ??
          lookupMimeType(file.path) ??
          'application/octet-stream';
      final fileName =
          file.path.split(Platform.pathSeparator).last;
      final bytes = await file.readAsBytes();
      await widget.room.sendFileEvent(
          MatrixFile(bytes: bytes, name: fileName, mimeType: mimeType));
    } finally {
      widget.onFinishedSendingMedia();
    }
  }

  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final picked =
    await picker.pickVideo(source: ImageSource.gallery);
    if (picked == null) return;
    await _sendPickedFile(File(picked.path),
        forcedMime: 'video/mp4');
  }

  Future<void> _pickDocument() async {
    final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.any,
        withData: false);
    if (result == null || result.files.single.path == null) return;
    await _sendPickedFile(File(result.files.single.path!));
  }
}

// ─── Reply banner ─────────────────────────────────────────────────────────────

class _ReplyBanner extends StatelessWidget {
  final Event event;
  final VoidCallback onCancel;

  const _ReplyBanner({required this.event, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final name = event.senderFromMemoryOrFallback.calcDisplayname();
    final rawBody = event.body.trim();
    // Strip the Matrix reply-fallback prefix so we never show
    // "> <@user:server> quoted text" in the composer banner.
    final cleanBody = MessageBubbleState.stripReplyFallback(rawBody);
    final preview = event.hasAttachment
        ? '📎 Attachment'
        : (cleanBody.length > 60
        ? '${cleanBody.substring(0, 60)}…'
        : cleanBody);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      decoration: const BoxDecoration(
        color: Color(0xFF0F1720),
        border: Border(
          top: BorderSide(color: Color(0xFF1D2530)),
          left: BorderSide(color: Color(0xFF4C8DF6), width: 3),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.reply, color: Color(0xFF4C8DF6), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Replying to $name',
                  style: const TextStyle(
                      color: Color(0xFF4C8DF6),
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  preview,
                  style: const TextStyle(
                      color: Color(0xFF9AA4B2), fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close,
                color: Color(0xFF9AA4B2), size: 18),
            onPressed: onCancel,
            padding: EdgeInsets.zero,
            constraints:
            const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}
