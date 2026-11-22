import 'dart:async';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

http.Client anonymousClient() =>
    throw UnsupportedError('Native anonymous reading only');
Future<Uint8List> bounded(
  Stream<List<int>> input,
  String? encoding, {
  required int maxWire,
  required int maxPlain,
  required Future<void> abort,
}) async => throw UnsupportedError('Native decoding only');
