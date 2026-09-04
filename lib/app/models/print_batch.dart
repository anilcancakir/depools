import 'package:magic/magic.dart';

import '../../ui/components/label_item_row/label_item_row.dart' show LabelCountMode;

/// One line of a print batch, as the label screen needs it.
///
/// **Replaces `LabelItemFixture`**, which carried the same five fields: `flutter-app.md` says to
/// replace a fixture rather than shadow it, because two types for one thing diverge the moment the API
/// changes.
///
/// `position` is the load-bearing field: it is what `settle`, the copy change and the removal are all
/// keyed on, because it is the number a person reprinting names off a sheet. Ids exist on the wire
/// too, and a client holding one already holds the other.
///
/// **Read-only from this client's side of the write path.** Every mutation goes through
/// `LabelBatchController`'s own endpoints, which answer with the whole batch again; nothing here
/// calls `save()`, so [fillable] stays empty.
class PrintBatchLine extends Model {
  @override
  String get table => 'print_batch_lines';

  @override
  String get resource => 'labels/batches';

  /// Set to false because this app uses string UUIDs as primary keys.
  @override
  bool get incrementing => false;

  @override
  List<String> get fillable => [];

  @override
  Map<String, dynamic> get casts => <String, dynamic>{
    'position': 'int',
    'count': 'int',
    'print_count': 'int',
    'is_printed': 'bool',
  };

  /// The number this line carries on the sheet's list. Unique within a batch, never renumbered.
  int get position => get<int>('position') ?? 0;

  /// The product name, the label's first line.
  String get name => get<String>('name') ?? '';

  /// The code that will be printed.
  ///
  /// **Null means the server did not say, not that one will be generated**, and the difference cost a
  /// whole feature: the resource used to omit this field entirely, so this was always null and every
  /// consumer ran on a placeholder. What actually gets printed is a policy the server owns (a GTIN, a
  /// Code 128 row, or a generated `DPL` code), which is why it travels rather than being guessed.
  String? get code => get<String>('code');

  /// The serial this line prints, when it prints one.
  String? get serial => get<String>('serial');

  /// How many stickers this line contributes.
  int get count => get<int>('count') ?? 1;

  /// Where the count comes from (D45).
  ///
  /// Read straight off the raw string rather than through an [EnumCast]: the wire spells the second
  /// mode `per_serial` and the Dart enum spells it `perSerial`, so a name-matching cast would never
  /// resolve it. The safe fallback is the mode WITHOUT a stepper, matching the server's own default:
  /// offering to edit how many units exist is the mistake D45 exists to prevent.
  LabelCountMode get mode => get<String>('mode') == 'free' ? LabelCountMode.free : LabelCountMode.perSerial;

  /// Whether this line has already been printed in this batch.
  bool get isPrinted => get<bool>('is_printed') ?? false;

  /// How many times it has been printed. Two means two sheets of paper went.
  int get printCount => get<int>('print_count') ?? 0;

  /// Whether this line's copies may be changed.
  ///
  /// D45 twice over: a serial prints once, and a printed line's count is a record of paper that
  /// already went rather than a number to edit.
  bool get isAdjustable => mode == LabelCountMode.free && !isPrinted;

  /// Creates a [PrintBatchLine] for a fixture or a preview, not for hydrating a payload.
  ///
  /// Writes the same wire shape [fromApi] reads, so a getter never has to ask which path built it.
  PrintBatchLine({
    required int position,
    required String name,
    required int count,
    String? code,
    String? serial,
    LabelCountMode mode = LabelCountMode.free,
    bool isPrinted = false,
    int printCount = 0,
  }) {
    setRawAttributes(<String, dynamic>{
      'position': position,
      'name': name,
      'code': code,
      'serial': serial,
      'count': count,
      'mode': mode == LabelCountMode.free ? 'free' : 'per_serial',
      'is_printed': isPrinted,
      'print_count': printCount,
    }, sync: true);
  }

  PrintBatchLine._raw();

  /// The line a batch payload describes.
  static PrintBatchLine fromApi(Map<String, dynamic> json) {
    return PrintBatchLine._raw()
      ..setRawAttributes(json, sync: true)
      ..exists = true;
  }
}

/// A saved set of labels to print together.
///
/// **Read-only from this client's side of the write path.** Every mutation goes through
/// `LabelBatchController`'s own endpoints, which answer with the whole batch again; nothing here
/// calls `save()`, so [fillable] stays empty.
class PrintBatch extends Model {
  @override
  String get table => 'print_batches';

  @override
  String get resource => 'labels/batches';

  /// Set to false because this app uses string UUIDs as primary keys.
  @override
  bool get incrementing => false;

  @override
  List<String> get fillable => [];

  @override
  Map<String, dynamic> get casts => <String, dynamic>{
    'sticker_count': 'int',
    'pending_sticker_count': 'int',
    'printed_at': 'datetime',
  };

  /// The nested line list. `getRelations` resolves it whether the attribute holds raw maps (a
  /// `labels/batches` payload, under its own wire key `items`) or already-built [PrintBatchLine]
  /// instances (a fixture), since it checks `data is List<T>` before reaching for this factory.
  ///
  /// **`PrintBatchLine._raw`, not `PrintBatchLine.new`.** `getRelations` invokes the factory with no
  /// arguments, and the public constructor's `position`/`name`/`count` are required for the fixture
  /// path; the zero-argument private constructor is what a bare hydration needs.
  @override
  Map<String, Model Function()> get relations => <String, Model Function()>{
    'items': PrintBatchLine._raw,
  };

  /// The batch id, or empty before one exists.
  @override
  String get id => get<String>('id') ?? '';

  /// What the user called it, if anything.
  String? get name => get<String>('name');

  /// The sheet template key, for example `a4_8_up_105x70`.
  String get template => get<String>('template') ?? '';

  /// Which fields the label carries.
  ///
  /// A stray non-string entry or a missing/malformed `fields` value both fall back to an EMPTY list
  /// rather than to the constructor's `['name', 'code']` default: an API payload that omitted the
  /// key never meant "the defaults", and guessing otherwise would show fields the server never chose.
  List<String> get fields {
    final Object? raw = getAttribute('fields');

    if (raw is! List) return const <String>[];

    return <String>[for (final Object? field in raw) if (field is String) field];
  }

  /// Every line, in sheet order.
  List<PrintBatchLine> get lines => getRelations<PrintBatchLine>('items');

  /// How many stickers the whole batch is for.
  int get stickerCount => get<int>('sticker_count') ?? 0;

  /// How many stickers a print would produce now.
  int get pendingStickerCount => get<int>('pending_sticker_count') ?? 0;

  /// When the batch finished, or null while anything is left.
  DateTime? get printedAt => get<Carbon>('printed_at')?.toDateTime;

  /// Whether anything is still waiting for a printer.
  ///
  /// Read from the LINES rather than from `printedAt`, which is what the server does: a batch half
  /// printed by a jammed printer has a null date and unprinted rows.
  bool get isUnfinished => lines.any((PrintBatchLine line) => !line.isPrinted);

  /// Whether this is the batch to carry on filling.
  ///
  /// **Not the same question as [isUnfinished], and conflating them stranded batches.** An EMPTY batch
  /// has no unprinted lines, so it read as finished and was never resumed; the client never deletes
  /// one either, so a user who removed their last line got a fresh batch on every visit and the
  /// abandoned ones piled up at the top of a list ordered nulls-first.
  ///
  /// `printedAt` is the server's own answer: it is derived, written only when nothing is left, so a
  /// null means this batch has never been finished. An empty batch is exactly the one to add to.
  bool get isResumable => printedAt == null;

  /// The lines already printed, which stay visible so a batch is resumable rather than mysterious.
  List<PrintBatchLine> get printed =>
      lines.where((PrintBatchLine line) => line.isPrinted).toList(growable: false);

  /// Whether [field] is switched on.
  bool shows(String field) => fields.contains(field);

  /// The codes that will be printed, for the fit check.
  ///
  /// **Only the ones the server named.** This used to substitute `DPL00000000` for a null, on the
  /// premise that null meant "one will be generated"; the resource simply was not sending the field, so
  /// the fit verdict compared a constant against every template's ceiling and was wrong in both
  /// directions. A line whose code is genuinely unknown is left out rather than guessed at, because a
  /// callout naming a code nobody will print is worse than no callout.
  List<String> get codes => <String>[
    for (final PrintBatchLine line in lines)
      if (line.serial != null) line.serial! else if (line.code != null) line.code!,
  ];

  /// Creates a [PrintBatch] for a fixture or a preview, not for hydrating a payload.
  ///
  /// Writes the same wire shape [fromApi] reads (`fields` and `items` mirror the server's own keys),
  /// so a getter never has to ask which path built the instance.
  PrintBatch({
    required String id,
    required String template,
    String? name,
    List<String> fields = const <String>['name', 'code'],
    List<PrintBatchLine> lines = const <PrintBatchLine>[],
    int stickerCount = 0,
    int pendingStickerCount = 0,
    DateTime? printedAt,
  }) {
    setRawAttributes(<String, dynamic>{
      'id': id,
      'name': name,
      'template': template,
      'fields': fields,
      'items': lines,
      'sticker_count': stickerCount,
      'pending_sticker_count': pendingStickerCount,
      'printed_at': printedAt,
    }, sync: true);
  }

  PrintBatch._raw();

  /// The batch a `labels/batches` payload describes.
  static PrintBatch fromApi(Map<String, dynamic> json) {
    return PrintBatch._raw()
      ..setRawAttributes(json, sync: true)
      ..exists = true;
  }
}
