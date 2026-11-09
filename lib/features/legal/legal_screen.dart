import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/l10n.dart';

/// The privacy policy and terms, bundled from `docs/` so they open offline.
/// The same files are public on GitHub for the store listings (Brand URLs).
enum LegalDocument {
  privacy('docs/PRIVACY.md'),
  terms('docs/TERMS.md');

  const LegalDocument(this.asset);
  final String asset;
}

/// Opens [doc] full screen above every other route, so it also works on the
/// signed-out welcome screen.
Future<void> showLegalDocument(BuildContext context, LegalDocument doc) =>
    Navigator.of(
      context,
      rootNavigator: true,
    ).push(MaterialPageRoute<void>(builder: (_) => LegalScreen(doc: doc)));

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.doc, this.bundle});

  final LegalDocument doc;

  /// Overridable for tests; defaults to [rootBundle].
  final AssetBundle? bundle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          doc == LegalDocument.privacy
              ? l10n.settingsPrivacyPolicy
              : l10n.settingsTerms,
        ),
      ),
      body: FutureBuilder<String>(
        future: (bundle ?? rootBundle).loadString(doc.asset),
        builder: (context, snapshot) {
          final text = snapshot.data;
          if (text == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return SelectionArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: markdownBlocks(context, text),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Renders the small Markdown subset the legal documents use: `#`/`##`
/// headings, `- ` bullets, paragraphs, `**bold**` and `[text](url)` (shown as
/// plain text).
@visibleForTesting
List<Widget> markdownBlocks(BuildContext context, String source) {
  final theme = Theme.of(context).textTheme;
  final blocks = <Widget>[];
  final paragraph = <String>[];

  void flush() {
    if (paragraph.isEmpty) return;
    blocks.add(
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text.rich(_inline(paragraph.join(' '), theme.bodyMedium)),
      ),
    );
    paragraph.clear();
  }

  for (final raw in source.split('\n')) {
    final line = raw.trimRight();
    if (line.isEmpty) {
      flush();
    } else if (line.startsWith('## ')) {
      flush();
      blocks.add(
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Text(line.substring(3), style: theme.titleMedium),
        ),
      );
    } else if (line.startsWith('# ')) {
      flush();
      blocks.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(line.substring(2), style: theme.headlineSmall),
        ),
      );
    } else if (line.startsWith('- ')) {
      flush();
      blocks.add(
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('•  ', style: theme.bodyMedium),
              Expanded(
                child: Text.rich(_inline(line.substring(2), theme.bodyMedium)),
              ),
            ],
          ),
        ),
      );
    } else {
      paragraph.add(line.trim());
    }
  }
  flush();
  return blocks;
}

final _link = RegExp(r'\[([^\]]+)\]\([^)]*\)');

TextSpan _inline(String text, TextStyle? style) {
  final plain = text.replaceAllMapped(_link, (m) => m[1]!);
  final parts = plain.split('**');
  return TextSpan(
    style: style,
    children: [
      for (var i = 0; i < parts.length; i++)
        TextSpan(
          text: parts[i],
          style: i.isOdd ? const TextStyle(fontWeight: FontWeight.w600) : null,
        ),
    ],
  );
}
