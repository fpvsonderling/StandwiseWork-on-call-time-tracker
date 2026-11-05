import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// Hands a CSV file to the user: a Save dialog on Windows and macOS, the
/// share sheet on Android and iOS (spec §5.3 "CSV on every platform").
abstract interface class CsvSaver {
  /// Returns `false` when the user cancelled.
  Future<bool> save(BuildContext context, String fileName, String csv);
}

class PlatformCsvSaver implements CsvSaver {
  const PlatformCsvSaver();

  static bool get _desktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  @override
  Future<bool> save(BuildContext context, String fileName, String csv) async {
    final bytes = Uint8List.fromList(utf8.encode(csv));
    final file = XFile.fromData(bytes, mimeType: 'text/csv', name: fileName);
    if (_desktop) {
      final location = await getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: const [
          XTypeGroup(label: 'CSV', extensions: ['csv']),
        ],
      );
      if (location == null) return false;
      await file.saveTo(location.path);
      return true;
    }
    final box = context.findRenderObject() as RenderBox?;
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [file],
        fileNameOverrides: [fileName],
        // iPad needs an anchor for the share popover.
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
    return result.status != ShareResultStatus.dismissed;
  }
}

final csvSaverProvider = Provider<CsvSaver>((ref) => const PlatformCsvSaver());

/// `standwise-<what>-2026-11-01_2026-11-30.csv`
String csvFileName(String what, DateTime first, DateTime lastInclusive) {
  String d(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  return 'standwise-$what-${d(first)}_${d(lastInclusive)}.csv';
}
