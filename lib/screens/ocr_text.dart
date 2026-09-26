import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_language.dart';
import '../theme/app_layout.dart';
import '../widgets/responsive.dart';

/// Full extracted text for one page of the student's paper. Editing is out
/// of scope; copying is here so the teacher can paste it into the answer fields.
class OcrTextPage extends StatelessWidget {
  const OcrTextPage({
    super.key,
    required this.filename,
    required this.text,
  });

  final String filename;
  final String text;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.extractedText,
              style: Theme.of(context).appBarTheme.titleTextStyle,
            ),
            Text(filename, style: const TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          if (text.trim().isNotEmpty)
            IconButton(
              tooltip: strings.copyText,
              icon: const Icon(Icons.copy_rounded),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: text));
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(strings.textCopied)));
              },
            ),
        ],
      ),
      body: ResponsivePage(
        maxWidth: AppLayout.compactMaxWidth,
        children: [
          if (text.trim().isEmpty)
            Text(strings.noExtractedText)
          else
            SelectableText(text, style: const TextStyle(height: 1.6)),
        ],
      ),
    );
  }
}
