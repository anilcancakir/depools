import 'package:flutter/foundation.dart';

import '../../ui/components/label_item_row/label_item_row.dart' show LabelCountMode;

/// One line of a print batch, as the label screen needs it.
///
/// **Replaces `LabelItemFixture`**, which carried the same five fields: `flutter-app.md` says to
/// replace a fixture rather than shadow it, because two types for one thing diverge the moment the API
/// changes.
///
/// `position` is new and it is the load-bearing addition: it is what `settle`, the copy change and the
/// removal are all keyed on, because it is the number a person reprinting names off a sheet. Ids exist
/// on the wire too, and a client holding one already holds the other.
@immutable
class PrintBatchLine {
  /// The number this line carries on the sheet's list. Unique within a batch, never renumbered.
  final int position;

  /// The product name, the label's first line.
  final String name;

  /// The code that will be printed, or null when the server will generate one.
  final String? code;

  /// The serial this line prints, when it prints one.
  final String? serial;

  /// How many stickers this line contributes.
  final int count;

  /// Where the count comes from (D45).
  final LabelCountMode mode;

  /// Whether this line has already been printed in this batch.
  final bool isPrinted;

  /// How many times it has been printed. Two means two sheets of paper went.
  final int printCount;

  /// Creates a [PrintBatchLine].
  const PrintBatchLine({
    required this.position,
    required this.name,
    required this.count,
    this.code,
    this.serial,
    this.mode = LabelCountMode.free,
    this.isPrinted = false,
    this.printCount = 0,
  });

  /// The line a batch payload describes.
  factory PrintBatchLine.fromApi(Map<String, dynamic> json) {
    return PrintBatchLine(
      position: (json['position'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?) ?? '',
      code: json['code'] as String?,
      serial: json['serial'] as String?,
      count: (json['count'] as num?)?.toInt() ?? 1,
      // The safe default is the one WITHOUT a stepper: offering to edit how many units exist is the
      // mistake D45 exists to prevent, so an unrecognised mode does not get the control.
      mode: json['mode'] == 'free' ? LabelCountMode.free : LabelCountMode.perSerial,
      isPrinted: json['is_printed'] == true,
      printCount: (json['print_count'] as num?)?.toInt() ?? 0,
    );
  }

  /// Whether this line's copies may be changed.
  ///
  /// D45 twice over: a serial prints once, and a printed line's count is a record of paper that
  /// already went rather than a number to edit.
  bool get isAdjustable => mode == LabelCountMode.free && !isPrinted;
}

/// A saved set of labels to print together.
@immutable
class PrintBatch {
  /// The batch id, or empty before one exists.
  final String id;

  /// What the user called it, if anything.
  final String? name;

  /// The sheet template key, for example `a4_8_up_105x70`.
  final String template;

  /// Which fields the label carries.
  final List<String> fields;

  /// Every line, in sheet order.
  final List<PrintBatchLine> lines;

  /// How many stickers the whole batch is for.
  final int stickerCount;

  /// How many stickers a print would produce now.
  final int pendingStickerCount;

  /// When the batch finished, or null while anything is left.
  final DateTime? printedAt;

  /// Creates a [PrintBatch].
  const PrintBatch({
    required this.id,
    required this.template,
    this.name,
    this.fields = const <String>['name', 'code'],
    this.lines = const <PrintBatchLine>[],
    this.stickerCount = 0,
    this.pendingStickerCount = 0,
    this.printedAt,
  });

  /// The batch a `labels/batches` payload describes.
  factory PrintBatch.fromApi(Map<String, dynamic> json) {
    final Object? lines = json['items'];

    return PrintBatch(
      id: (json['id'] as String?) ?? '',
      name: json['name'] as String?,
      template: (json['template'] as String?) ?? '',
      fields: <String>[
        if (json['fields'] is List)
          for (final Object? field in json['fields'] as List<Object?>)
            if (field is String) field,
      ],
      lines: <PrintBatchLine>[
        if (lines is List)
          for (final Object? line in lines)
            if (line is Map) PrintBatchLine.fromApi(Map<String, dynamic>.from(line)),
      ],
      stickerCount: (json['sticker_count'] as num?)?.toInt() ?? 0,
      pendingStickerCount: (json['pending_sticker_count'] as num?)?.toInt() ?? 0,
      printedAt: DateTime.tryParse('${json['printed_at']}'),
    );
  }

  /// Whether anything is still waiting for a printer.
  ///
  /// Read from the LINES rather than from `printedAt`, which is what the server does: a batch half
  /// printed by a jammed printer has a null date and unprinted rows.
  bool get isUnfinished => lines.any((PrintBatchLine line) => !line.isPrinted);

  /// The lines already printed, which stay visible so a batch is resumable rather than mysterious.
  List<PrintBatchLine> get printed =>
      lines.where((PrintBatchLine line) => line.isPrinted).toList(growable: false);

  /// Whether [field] is switched on.
  bool shows(String field) => fields.contains(field);

  /// The codes that will be printed, for the fit check.
  ///
  /// A null code means the server will generate one, and a generated code is `DPL` plus eight hex
  /// characters: eleven, which the smallest template cannot carry. So an absent code is not an absent
  /// question, and this reports the length the server will produce rather than skipping the line.
  List<String> get codes => <String>[
    for (final PrintBatchLine line in lines)
      if (line.serial != null) line.serial! else line.code ?? 'DPL00000000',
  ];
}
