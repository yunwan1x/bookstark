part of 'owned_writable_generation15.dart';

/// SQL receipt is durable creation evidence. Its historical table name is
/// html_creation_receipts; the unchanged schema has no format restriction.
final class Owned15CreationReceipt {
  const Owned15CreationReceipt({
    required this.creationKey,
    required this.id,
    required this.collection,
    required this.inputHash,
    required this.createdAt,
  });
  final String creationKey, collection, inputHash;
  final int id, createdAt;
}

enum Owned15CreationResourceState { matching, changed, missing, deleted }

final class Owned15CreationObservation {
  const Owned15CreationObservation({
    required this.receipt,
    required this.state,
    this.kind,
    this.currentFingerprint,
  });
  final Owned15CreationReceipt receipt;
  final Owned15CreationResourceState state;
  final ComplexEditorKind? kind;
  final String? currentFingerprint;
}

final class Owned15CreationSubmissionUncertain implements Exception {
  const Owned15CreationSubmissionUncertain({this.knownReceipt});
  final Owned15CreationReceipt? knownReceipt;
}

final class Owned15CreationAlreadySubmitted implements Exception {
  const Owned15CreationAlreadySubmitted();
}

/// A consumed prepared value can be reviewed in memory, never submitted again.
final class Owned15PreparedCreation {
  Owned15PreparedCreation._(
    this._creator,
    this.creationKey,
    this.collection,
    this.kind,
    this.inputHash,
    this._title,
    this._labelsJson,
    this._document,
    this._body,
    this._passwordHash,
    this.createdAt,
    this._createTime,
    this.isProtected,
  );
  final Owned15GenerationCreator _creator;
  final String creationKey, collection, inputHash;
  final ComplexEditorKind kind;
  final int createdAt;
  final bool isProtected;
  String? _title, _labelsJson, _body, _passwordHash, _createTime;
  ComplexEditorDocument? _document;
  bool _consumed = false, _closed = false;
  String get title {
    _check();
    return _title!;
  }

  ComplexEditorDocument get document {
    _check();
    return _document!;
  }

  List<String> get labels {
    _check();
    return List<String>.unmodifiable(
      (jsonDecode(_labelsJson!) as List).cast<String>(),
    );
  }

  void _check() {
    if (_closed || !_creator.current) {
      throw const GenerationContentFailure(GenerationContentReason.retired);
    }
  }

  void dispose() {
    _closed = true;
    _title = _labelsJson = _body = _passwordHash = _createTime = null;
    _document = null;
    _creator._prepared.remove(this);
  }
}

/// No Database/path/readonly repository constructor exists. This library part
/// borrows only its sealed owner's maintenance gate and actual SQL handle.
final class Owned15GenerationCreator {
  Owned15GenerationCreator._(this.owner, this._clock);
  factory Owned15GenerationCreator(
    OwnedWritableGeneration15 owner, {
    DateTime Function()? clock,
  }) {
    if (!owner.current || owner._creationOwners.length >= 4) {
      throw const GenerationContentFailure(GenerationContentReason.retired);
    }
    final result = Owned15GenerationCreator._(owner, clock ?? DateTime.now);
    owner._creationOwners.add(result);
    return result;
  }
  final OwnedWritableGeneration15 owner;
  final DateTime Function() _clock;
  final Set<Owned15PreparedCreation> _prepared = {};
  final Set<AttachmentCancellation> _requests = {};
  final Set<Future<void>> _inflight = {};
  bool _retired = false;
  bool _preparing = false;
  Future<void>? _closing;
  bool get current => !_retired && owner.current;
  void _check([AttachmentCancellation? request]) {
    if (!current) {
      throw const GenerationContentFailure(GenerationContentReason.retired);
    }
    request?.check();
  }

  Future<T> _run<T>(
    Future<T> Function(AttachmentCancellation) work,
    AttachmentCancellation? cancellation,
  ) async {
    _check();
    final request = cancellation ?? AttachmentCancellation();
    final done = Completer<void>();
    _requests.add(request);
    _inflight.add(done.future);
    try {
      return await owner._maintenance.use(() async {
        _check(request);
        return work(request);
      });
    } finally {
      _requests.remove(request);
      _inflight.remove(done.future);
      done.complete();
    }
  }

  static bool _hex(String value, int length) => RegExp(
    '^[a-f0-9]{$length}'
    r'$',
  ).hasMatch(value);
  static String _inputHash({
    required String collection,
    required ComplexEditorKind kind,
    required String title,
    required String labelsJson,
    required String body,
    required String passwordHash,
    required int stamp,
    required String createTime,
    int revision = 1,
    int deleted = 0,
    int pinned = 0,
    int pinOrder = 0,
    int visibility = 0,
    int legacyVersion = 0,
  }) => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            'owned15-stored-creation-v1',
            collection,
            kind.name,
            title,
            labelsJson,
            sha256.convert(utf8.encode(body)).toString(),
            passwordHash,
            stamp,
            createTime,
            revision,
            deleted,
            pinned,
            pinOrder,
            visibility,
            legacyVersion,
          ]),
        ),
      )
      .toString();

  Future<Owned15PreparedCreation> prepare({
    required String creationKey,
    required String collection,
    required ComplexEditorDocument document,
    required String title,
    required List<String> labels,
    String? password,
    AttachmentCancellation? cancellation,
  }) {
    _check();
    if (_preparing || _prepared.isNotEmpty) {
      throw const GenerationContentFailure(GenerationContentReason.invalidEdit);
    }
    _preparing = true;
    return _prepare(
      creationKey: creationKey,
      collection: collection,
      document: document,
      title: title,
      labels: List<String>.of(labels),
      password: password,
      cancellation: cancellation,
    ).whenComplete(() {
      _preparing = false;
    });
  }

  Future<Owned15PreparedCreation> _prepare({
    required String creationKey,
    required String collection,
    required ComplexEditorDocument document,
    required String title,
    required List<String> labels,
    String? password,
    AttachmentCancellation? cancellation,
  }) => _run((request) async {
    if (_prepared.isNotEmpty ||
        !_hex(creationKey, 32) ||
        !{'note', 'article'}.contains(collection) ||
        !localProtectionUnicode(title) ||
        title.trim().isEmpty ||
        utf8.encode(title).length > 200 ||
        labels.length > 100 ||
        labels.toSet().length != labels.length ||
        labels.any((v) => v.isEmpty || !localProtectionUnicode(v)) ||
        utf8.encode(jsonEncode(labels)).length > 60 * 1024 ||
        !localProtectionUnicode(document.source) ||
        document.kind == ComplexEditorKind.markdown &&
            (document.byteLength > localGenerationMarkdownSaveBytes ||
                !localProtectedPlaintext(document.source))) {
      throw const GenerationContentFailure(GenerationContentReason.invalidEdit);
    }
    // A new value is parsed without normalizing any source bytes.
    final validated = ComplexEditorDocument.parse(
      document.kind,
      document.source,
    );
    final protected = password != null;
    if (!protected && document.source.startsWith('ENC:')) {
      throw const GenerationContentFailure(GenerationContentReason.invalidEdit);
    }
    await owner.confirmCurrent();
    _check(request);
    var body = validated.source, passwordHash = '';
    if (password != null) {
      final value = await owner.content.crypto.protectNew(
        password: password,
        plaintext: validated.source,
        cancellation: request,
      );
      _check(request);
      body = value.body;
      passwordHash = value.passwordHash;
      if (!localProtectedRecordSupported(passwordHash, body)) {
        throw const GenerationContentFailure(
          GenerationContentReason.invalidRecord,
        );
      }
    }
    await owner.confirmCurrent();
    _check(request);
    final stamp = _clock();
    if (stamp.millisecondsSinceEpoch <= 0) {
      throw const GenerationContentFailure(GenerationContentReason.invalidEdit);
    }
    final labelsJson = jsonEncode(List<String>.of(labels));
    final hash = _inputHash(
      collection: collection,
      kind: document.kind,
      title: title,
      labelsJson: labelsJson,
      body: body,
      passwordHash: passwordHash,
      stamp: stamp.millisecondsSinceEpoch,
      createTime: stamp.toUtc().toIso8601String(),
    );
    final result = Owned15PreparedCreation._(
      this,
      creationKey,
      collection,
      document.kind,
      hash,
      title,
      labelsJson,
      validated,
      body,
      passwordHash,
      stamp.millisecondsSinceEpoch,
      stamp.toUtc().toIso8601String(),
      protected,
    );
    _prepared.add(result);
    return result;
  }, cancellation);

  /// The caller must durably claim unknown inside beforeInsert. It is awaited
  /// once, after immutable crypto preparation, before any note/receipt INSERT.
  Future<Owned15CreationReceipt> submit(
    Owned15PreparedCreation prepared, {
    required Future<void> Function(String inputHash) beforeInsert,
    AttachmentCancellation? cancellation,
  }) => _run((request) async {
    prepared._check();
    if (!identical(prepared._creator, this) ||
        !_prepared.contains(prepared) ||
        prepared._consumed) {
      throw const Owned15CreationAlreadySubmitted();
    }
    prepared._consumed = true; // before the first await; cannot race a retry
    try {
      await beforeInsert(prepared.inputHash);
    } catch (_) {
      throw const Owned15CreationSubmissionUncertain();
    }
    _check(request);
    prepared._check();
    await owner.confirmCurrent();
    _check(request);
    Owned15CreationReceipt? committed;
    try {
      final receipt = await owner._database.transaction((tx) async {
        await _schema(tx);
        _check(request);
        final previous = await tx.rawQuery(
          'SELECT creation_key FROM html_creation_receipts WHERE creation_key=?',
          [prepared.creationKey],
        );
        _check(request);
        if (previous.isNotEmpty) throw const Owned15CreationAlreadySubmitted();
        final id = await tx.rawInsert(
          'INSERT INTO notes (collection,editor_type,title,content,labels,updated_at,'
          'password_hash,is_pinned,pin_order,visibility,legacy_version,create_time,revision,deleted) '
          'VALUES (?,?,CAST(? AS TEXT),CAST(? AS TEXT),CAST(? AS TEXT),?,'
          'CAST(? AS TEXT),0,0,0,0,CAST(? AS TEXT),1,0)',
          [
            prepared.collection,
            prepared.kind.name,
            Uint8List.fromList(utf8.encode(prepared._title!)),
            Uint8List.fromList(utf8.encode(prepared._body!)),
            Uint8List.fromList(utf8.encode(prepared._labelsJson!)),
            prepared.createdAt,
            Uint8List.fromList(utf8.encode(prepared._passwordHash!)),
            Uint8List.fromList(utf8.encode(prepared._createTime!)),
          ],
        );
        _check(request);
        if (id <= 0) {
          throw const GenerationContentFailure(
            GenerationContentReason.invalidRecord,
          );
        }
        await tx.insert('html_creation_receipts', {
          'creation_key': prepared.creationKey,
          'note_id': id,
          'collection': prepared.collection,
          'input_hash': prepared.inputHash,
          'created_at': prepared.createdAt,
        });
        final verified = await _readRow(tx, id, request);
        _check(request);
        if (verified == null ||
            verified.hash != prepared.inputHash ||
            verified.deleted ||
            verified.kind != prepared.kind ||
            verified.collection != prepared.collection) {
          throw const GenerationContentFailure(
            GenerationContentReason.invalidRecord,
          );
        }
        return Owned15CreationReceipt(
          creationKey: prepared.creationKey,
          id: id,
          collection: prepared.collection,
          inputHash: prepared.inputHash,
          createdAt: prepared.createdAt,
        );
      });
      committed = receipt;
      _check(request);
      await owner.confirmCurrent();
      _check(request);
      return receipt;
    } on Owned15CreationAlreadySubmitted {
      rethrow;
    } catch (_) {
      throw Owned15CreationSubmissionUncertain(knownReceipt: committed);
    }
  }, cancellation);

  Future<void> _schema(DatabaseExecutor tx) async {
    final rows = await tx.rawQuery('PRAGMA user_version');
    if (rows.length != 1 || rows.single.values.single != 15) {
      throw const GenerationContentFailure(
        GenerationContentReason.incompatibleSchema,
      );
    }
  }

  Future<Owned15CreationObservation?> inspect(
    String creationKey, {
    AttachmentCancellation? cancellation,
  }) => _run((request) async {
    if (!_hex(creationKey, 32)) {
      throw const FormatException('Invalid creation key');
    }
    await owner.confirmCurrent();
    _check(request);
    final observation = await owner._database.transaction((tx) async {
      await _schema(tx);
      final rows = await tx.rawQuery(
        'SELECT creation_key,note_id,collection,input_hash,created_at '
        'FROM html_creation_receipts WHERE creation_key=?',
        [creationKey],
      );
      _check(request);
      if (rows.isEmpty) return null;
      if (rows.length != 1) {
        throw const GenerationContentFailure(
          GenerationContentReason.invalidRecord,
        );
      }
      final row = rows.single;
      final id = row['note_id'],
          collection = row['collection'],
          hash = row['input_hash'],
          stamp = row['created_at'];
      if (row['creation_key'] != creationKey ||
          id is! int ||
          id <= 0 ||
          collection is! String ||
          !{'note', 'article'}.contains(collection) ||
          hash is! String ||
          !_hex(hash, 64) ||
          stamp is! int ||
          stamp <= 0) {
        throw const GenerationContentFailure(
          GenerationContentReason.invalidRecord,
        );
      }
      final receipt = Owned15CreationReceipt(
        creationKey: creationKey,
        id: id,
        collection: collection,
        inputHash: hash,
        createdAt: stamp,
      );
      final actual = await _readRow(tx, id, request);
      _check(request);
      return Owned15CreationObservation(
        receipt: receipt,
        state: actual == null
            ? Owned15CreationResourceState.missing
            : actual.deleted
            ? Owned15CreationResourceState.deleted
            : actual.collection == collection && actual.hash == hash
            ? Owned15CreationResourceState.matching
            : Owned15CreationResourceState.changed,
        kind: actual?.kind,
        currentFingerprint: actual?.fingerprint,
      );
    }, exclusive: false);
    await owner.confirmCurrent();
    _check(request);
    return observation;
  }, cancellation);

  Future<_Owned15CreationStored?> _readRow(
    DatabaseExecutor tx,
    int id,
    AttachmentCancellation request,
  ) async {
    _check(request);
    // Never transfer unbounded text through the SQLite bridge before checking
    // its storage class and byte length inside this same read transaction.
    final bounds = await tx.rawQuery(
      'SELECT typeof(collection) AS ct,length(CAST(collection AS BLOB)) AS cn,'
      'typeof(editor_type) AS ft,length(CAST(editor_type AS BLOB)) AS fn,'
      'typeof(title) AS tt,length(CAST(title AS BLOB)) AS tn,'
      'typeof(labels) AS lt,length(CAST(labels AS BLOB)) AS ln,'
      'typeof(password_hash) AS pt,length(CAST(password_hash AS BLOB)) AS pn,'
      'typeof(create_time) AS dt,length(CAST(create_time AS BLOB)) AS dn,'
      'typeof(content) AS bt,length(CAST(content AS BLOB)) AS bn '
      'FROM notes WHERE id=?',
      [id],
    );
    _check(request);
    if (bounds.isEmpty) return null;
    if (bounds.length != 1) {
      throw const FormatException('Invalid creation resource');
    }
    final bound = bounds.single;
    const maxima = {
      'c': 7,
      'f': 32,
      't': 200,
      'l': 60 * 1024,
      'p': 1024,
      'd': 128,
      'b': localCryptoMaxWireBytes,
    };
    for (final entry in maxima.entries) {
      final size = bound['${entry.key}n'];
      if (bound['${entry.key}t'] != 'text' ||
          size is! int ||
          size < 0 ||
          size > entry.value) {
        throw const FormatException('Creation resource metadata bound');
      }
    }
    final rows = await tx.rawQuery(
      'SELECT id,collection,editor_type,CAST(title AS BLOB) AS title_blob,'
      'CAST(labels AS BLOB) AS labels_blob,password_hash,updated_at,create_time,'
      'revision,deleted,is_pinned,pin_order,visibility,legacy_version,'
      'typeof(title) AS title_type,typeof(content) AS content_type,'
      'typeof(labels) AS labels_type,typeof(password_hash) AS password_type '
      'FROM notes WHERE id=?',
      [id],
    );
    if (rows.isEmpty) return null;
    if (rows.length != 1) {
      throw const FormatException('Invalid creation resource');
    }
    final row = rows.single;
    final collection = row['collection'],
        format = row['editor_type'],
        titleBytes = row['title_blob'],
        labelsBytes = row['labels_blob'],
        passwordHash = row['password_hash'],
        createTime = row['create_time'];
    if (row['id'] != id ||
        collection is! String ||
        !{'note', 'article'}.contains(collection) ||
        format is! String ||
        titleBytes is! List<int> ||
        titleBytes.length > 200 ||
        labelsBytes is! List<int> ||
        labelsBytes.length > 60 * 1024 ||
        passwordHash is! String ||
        createTime is! String ||
        createTime.length > 128 ||
        ![
          'title_type',
          'content_type',
          'labels_type',
          'password_type',
        ].every((key) => row[key] == 'text') ||
        ![
          'updated_at',
          'revision',
          'deleted',
          'is_pinned',
          'pin_order',
          'visibility',
          'legacy_version',
        ].every((key) => row[key] is int) ||
        (row['revision'] as int) <= 0 ||
        !{0, 1}.contains(row['deleted']) ||
        !{0, 1}.contains(row['is_pinned'])) {
      throw const FormatException('Invalid typed creation resource');
    }
    final kind = ComplexEditorKind.parse(format);
    final body = await _readBody(tx, id, collection, format, request);
    final title = BoundedNoteTextReader.decodeUtf8PreservingBom(
      Uint8List.fromList(titleBytes),
    );
    final labelsJson = BoundedNoteTextReader.decodeUtf8PreservingBom(
      Uint8List.fromList(labelsBytes),
    );
    final values = jsonDecode(labelsJson);
    if (values is! List ||
        values.length > 100 ||
        values.any((v) => v is! String) ||
        !localProtectionUnicode(title) ||
        !localProtectionUnicode(labelsJson) ||
        passwordHash.isNotEmpty &&
            !localProtectedRecordSupported(passwordHash, body)) {
      throw const FormatException('Invalid stored creation input');
    }
    final hash = _inputHash(
      collection: collection,
      kind: kind,
      title: title,
      labelsJson: labelsJson,
      body: body,
      passwordHash: passwordHash,
      stamp: row['updated_at'] as int,
      createTime: createTime,
      revision: row['revision'] as int,
      deleted: row['deleted'] as int,
      pinned: row['is_pinned'] as int,
      pinOrder: row['pin_order'] as int,
      visibility: row['visibility'] as int,
      legacyVersion: row['legacy_version'] as int,
    );
    return _Owned15CreationStored(
      collection,
      kind,
      hash,
      sha256
          .convert(
            utf8.encode(jsonEncode(['owned15-created-current-v1', id, hash])),
          )
          .toString(),
      row['deleted'] == 1,
    );
  }

  Future<String> _readBody(
    DatabaseExecutor tx,
    int id,
    String collection,
    String format,
    AttachmentCancellation request,
  ) async {
    _check(request);
    final lengths = await tx.rawQuery(
      'SELECT length(CAST(content AS BLOB)) AS n FROM notes '
      'WHERE id=? AND collection=? AND editor_type=?',
      [id, collection, format],
    );
    _check(request);
    if (lengths.length != 1 || lengths.single['n'] is! int) {
      throw const FormatException('Invalid creation body');
    }
    final length = lengths.single['n'] as int;
    if (length < 0 || length > localCryptoMaxWireBytes) {
      throw const FormatException('Creation body exceeds bound');
    }
    final output = BytesBuilder(copy: false);
    try {
      for (var offset = 0; offset < length;) {
        _check(request);
        final count = (length - offset).clamp(0, 64 * 1024).toInt();
        final chunks = await tx.rawQuery(
          'SELECT substr(CAST(content AS BLOB),?,?) AS bytes FROM notes '
          'WHERE id=? AND collection=? AND editor_type=?',
          [offset + 1, count, id, collection, format],
        );
        _check(request);
        if (chunks.length != 1 ||
            chunks.single['bytes'] is! Uint8List ||
            (chunks.single['bytes'] as Uint8List).length != count) {
          throw const FormatException('Creation body changed');
        }
        output.add(chunks.single['bytes'] as Uint8List);
        offset += count;
      }
      final bytes = output.takeBytes();
      try {
        return BoundedNoteTextReader.decodeUtf8PreservingBom(bytes);
      } finally {
        bytes.fillRange(0, bytes.length, 0);
      }
    } finally {
      final discarded = output.takeBytes();
      discarded.fillRange(0, discarded.length, 0);
    }
  }

  void _cancel() {
    _retired = true;
    for (final request in _requests.toList()) {
      request.cancel();
    }
    for (final prepared in _prepared.toList()) {
      prepared.dispose();
    }
  }

  Future<void> retire() {
    final pending = _closing;
    if (pending != null) return pending;
    _cancel();
    final completer = Completer<void>();
    _closing = completer.future;
    () async {
      try {
        while (_inflight.isNotEmpty) {
          await Future.wait(_inflight.toList());
        }
        await owner.content.crypto.drain();
        owner._creationOwners.remove(this);
        completer.complete();
      } catch (error, stack) {
        _closing = null;
        completer.completeError(error, stack);
      }
    }();
    return completer.future;
  }
}

final class _Owned15CreationStored {
  const _Owned15CreationStored(
    this.collection,
    this.kind,
    this.hash,
    this.fingerprint,
    this.deleted,
  );
  final String collection, hash, fingerprint;
  final ComplexEditorKind kind;
  final bool deleted;
}
