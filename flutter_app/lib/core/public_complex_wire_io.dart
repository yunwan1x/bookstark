import 'strict_single_gzip.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

http.Client anonymousClient() => IOClient(HttpClient()..autoUncompress = false);
Future<Uint8List> bounded(
  Stream<List<int>> input,
  String? encoding, {
  required int maxWire,
  required int maxPlain,
  required Future<void> abort,
}) async {
  var wire = 0, plain = 0;
  Stream<List<int>> limited() async* {
    await for (final part in input) {
      wire += part.length;
      if (wire > maxWire) throw const FormatException('Wire bound');
      yield part;
    }
  }

  final name = (encoding ?? 'identity').trim().toLowerCase();
  if (!{'identity', 'gzip', ''}.contains(name)) {
    throw const FormatException('Unsupported encoding');
  }
  if (name == 'gzip') {
    return decodeStrictSingleGzip(
      input,
      maxWire: maxWire,
      maxPlain: maxPlain,
      abort: abort,
    );
  }
  final decoded = limited();
  final bytes = BytesBuilder(copy: false);
  final iterator = StreamIterator<List<int>>(decoded);
  try {
    while (await Future.any<bool>([
      iterator.moveNext(),
      abort.then<bool>((_) => throw const FormatException('Read cancelled')),
    ])) {
      final part = iterator.current;
      plain += part.length;
      if (plain > maxPlain) throw const FormatException('Plain bound');
      bytes.add(part);
    }
    return bytes.takeBytes();
  } finally {
    await iterator.cancel();
  }
}
