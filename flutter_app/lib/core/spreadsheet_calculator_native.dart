import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'spreadsheet_document.dart' show spreadsheetMaxBytes;

typedef _AllocNative = Pointer<Uint8> Function(UintPtr);
typedef _Alloc = Pointer<Uint8> Function(int);
typedef _FreeInputNative = Void Function(Pointer<Uint8>, UintPtr);
typedef _FreeInput = void Function(Pointer<Uint8>, int);
typedef _CalculateNative = Pointer<Uint8> Function(Pointer<Uint8>, UintPtr);
typedef _Calculate = Pointer<Uint8> Function(Pointer<Uint8>, int);
typedef _LengthNative = UintPtr Function(Pointer<Uint8>);
typedef _Length = int Function(Pointer<Uint8>);
typedef _FreeNative = Void Function(Pointer<Uint8>);
typedef _Free = void Function(Pointer<Uint8>);

Future<String> calculate(String payload, {String? libraryPath}) =>
    Isolate.run(() => _calculate(payload, libraryPath));

String _calculate(String payload, String? libraryPath) {
  final bytes = utf8.encode(payload);
  if (bytes.isEmpty || bytes.length > spreadsheetMaxBytes) {
    throw const FormatException('Calculation input exceeds bounds');
  }
  final library = DynamicLibrary.open(
    libraryPath ?? 'libbookstark_spreadsheet_calc.so',
  );
  final alloc = library.lookupFunction<_AllocNative, _Alloc>('bs_alloc_input');
  final freeInput = library.lookupFunction<_FreeInputNative, _FreeInput>(
    'bs_free_input',
  );
  final invoke = library.lookupFunction<_CalculateNative, _Calculate>(
    'bs_calculate',
  );
  final length = library.lookupFunction<_LengthNative, _Length>(
    'bs_result_len',
  );
  final free = library.lookupFunction<_FreeNative, _Free>('bs_free_result');
  final input = alloc(bytes.length);
  if (input == nullptr) throw StateError('Calculation allocation failed');
  Pointer<Uint8> output = nullptr;
  try {
    input.asTypedList(bytes.length).setAll(0, bytes);
    output = invoke(input, bytes.length);
    if (output == nullptr) throw StateError('Calculation returned no result');
    final count = length(output);
    if (count <= 0 || count > 10 * 1024 * 1024) {
      throw const FormatException('Calculation response exceeds bounds');
    }
    return utf8.decode(output.asTypedList(count));
  } finally {
    if (output != nullptr) free(output);
    freeInput(input, bytes.length);
  }
}
