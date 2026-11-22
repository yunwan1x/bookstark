import 'dart:convert';
import 'secure_record_store.dart';

enum OwnedImageUploadPhase { unknown, confirmedUrl, inserted }

/// Only metadata. A server URL confirms neither ownership nor a new media row.
class OwnedImageUploadRecord {
  const OwnedImageUploadRecord({
    required this.bindingId,
    required this.inputSHA256,
    required this.phase,
    this.uploadId,
    this.url,
  });
  final String bindingId, inputSHA256;
  final OwnedImageUploadPhase phase;
  final int? uploadId;
  final Uri? url;
  String encode() => jsonEncode({
    'v': 1,
    'binding': bindingId,
    'sha256': inputSHA256,
    'phase': phase.name,
    'uploadId': uploadId,
    'url': url?.toString(),
  });
  static OwnedImageUploadRecord decode(
    String raw, {
    required String bindingId,
  }) {
    if (raw.length > 8192) {
      throw const FormatException('Upload record too large');
    }
    final value = jsonDecode(raw);
    if (value is! Map<String, dynamic> ||
        value['v'] != 1 ||
        value['binding'] != bindingId ||
        value['sha256'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(value['sha256'] as String)) {
      throw const FormatException('Invalid upload record');
    }
    final phase = OwnedImageUploadPhase.values
        .where((p) => p.name == value['phase'])
        .toList();
    if (phase.length != 1) throw const FormatException('Invalid upload phase');
    final id = value['uploadId'], u = value['url'];
    if (phase.single == OwnedImageUploadPhase.unknown) {
      if (id != null || u != null) {
        throw const FormatException('Unknown upload has no receipt');
      }
      return OwnedImageUploadRecord(
        bindingId: bindingId,
        inputSHA256: value['sha256'] as String,
        phase: phase.single,
      );
    }
    if (id is! int || id <= 0 || u is! String || u.length > 2048) {
      throw const FormatException('Invalid upload receipt');
    }
    final uri = Uri.tryParse(u);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('Invalid upload URL');
    }
    return OwnedImageUploadRecord(
      bindingId: bindingId,
      inputSHA256: value['sha256'] as String,
      phase: phase.single,
      uploadId: id,
      url: uri,
    );
  }
}

/// flush must acknowledge the real backing store. Readback is mandatory.
/// The caller supplies an opaque hashed account/document namespace.
class OwnedComplexImageUploadJournal {
  OwnedComplexImageUploadJournal({
    required this.store,
    required this.bindingId,
    required this.flush,
    String? storageId,
  }) : storageId = storageId ?? bindingId {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(bindingId) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(this.storageId) ||
        store.prefix != prefix ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(store.namespace)) {
      throw ArgumentError('Opaque upload journal namespace required');
    }
  }
  static const prefix = 'bookstark.owned-image-upload.v1';
  static const keyPrefix = 'bookstark.owned-image-upload.v1.';
  final SecureRecordStore store;
  final String bindingId, storageId;
  final Future<void> Function() flush;
  String get identity => store.metadataKey(storageId);
  Future<OwnedImageUploadRecord?> read() async {
    final raw = await store.readRecord(storageId);
    return raw == null
        ? null
        : OwnedImageUploadRecord.decode(raw, bindingId: bindingId);
  }

  Future<void> write(OwnedImageUploadRecord record) async {
    if (record.bindingId != bindingId) {
      throw StateError('Upload binding changed');
    }
    final encoded = record.encode();
    await store.writeRecord(storageId, encoded);
    await flush();
    if (await store.readRecord(storageId) != encoded) {
      throw StateError('Upload record not durable');
    }
  }

  // A completed insertion may be explicitly dismissed. Unknown results remain.
  Future<void> clearInserted() async {
    final value = await read();
    if (value == null) return;
    if (value.phase != OwnedImageUploadPhase.inserted) {
      throw StateError('Upload unresolved');
    }
    await store.removeRecord(storageId);
    await flush();
    if (await store.readRecord(storageId) != null) {
      throw StateError('Upload cleanup not durable');
    }
  }
}
