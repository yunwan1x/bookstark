import 'spreadsheet_calculation.dart';
import 'spreadsheet_document.dart';
import 'spreadsheet_calculator_stub.dart'
    if (dart.library.ffi) 'spreadsheet_calculator_native.dart'
    as platform;

Future<SpreadsheetCalculationResult> calculateSpreadsheet(
  SpreadsheetDocument document, {
  String? libraryPath,
}) async {
  final input = SpreadsheetCalculationInput.fromDocument(document);
  final response = await platform.calculate(
    input.payload,
    libraryPath: libraryPath,
  );
  return input.decode(response);
}
