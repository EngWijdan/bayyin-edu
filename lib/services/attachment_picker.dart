import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Extensions and byte ceiling the server accepts. Checking them before the
/// upload is a courtesy to the teacher; the server decides for real.
const attachmentExtensions = ['jpg', 'jpeg', 'png', 'pdf'];
const maxAttachmentBytes = 10 * 1024 * 1024;

/// A file the teacher chose, reduced to what an upload needs.
class PickedAttachment {
  const PickedAttachment({required this.filename, required this.bytes});

  final String filename;
  final Uint8List bytes;

  String get extension {
    final dot = filename.lastIndexOf('.');
    return dot == -1 ? '' : filename.substring(dot + 1).toLowerCase();
  }

  bool get hasSupportedExtension => attachmentExtensions.contains(extension);
  bool get isWithinSizeLimit => bytes.length <= maxAttachmentBytes;
}

/// Choosing a file goes through the platform, which widget tests cannot reach,
/// so screens take this rather than calling [FilePicker] directly.
abstract class AttachmentPicker {
  /// The chosen file, or null when the teacher backs out of the dialog.
  Future<PickedAttachment?> pick();
}

class PlatformAttachmentPicker implements AttachmentPicker {
  const PlatformAttachmentPicker();

  @override
  Future<PickedAttachment?> pick() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: attachmentExtensions,
    );
    if (file == null) return null;
    return PickedAttachment(
      filename: file.name,
      bytes: await file.readAsBytes(),
    );
  }
}
