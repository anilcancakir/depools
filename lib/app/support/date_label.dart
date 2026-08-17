import 'package:magic/magic.dart';

/// Formats [date] the way a person reads a shelf date: `5 Ağu`, or `5 Ağu 2027` outside the
/// current year.
///
/// Extracted from `stock_in_sheet.dart` at its THIRD caller (the receipt list label and the
/// receipt detail header each need it once more), which is this project's own bar for pulling a
/// block out rather than leaving a second copy of the same month table. The table lives under
/// `common.months.1` through `common.months.12` because it is locale DATA, not screen copy: the
/// real answer is a proper date formatter, and this keeps the abbreviation out of hand-rolled Dart
/// until one exists.
String dateLabel(DateTime date) {
  final DateTime now = DateTime.now();
  final List<String> months = [
    for (int m = 1; m <= 12; m++) Lang.get('common.months.$m'),
  ];

  // The YEAR appears whenever it is not this one. A two-year warranty rendered "5 Ağu" and read
  // as this week, which is the opposite of what it meant. Omitting it inside the current year
  // keeps the common perishable case short.
  final String day = '${date.day} ${months[date.month - 1]}';

  return date.year == now.year ? day : '$day ${date.year}';
}
