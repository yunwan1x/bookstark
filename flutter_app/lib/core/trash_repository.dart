import 'api_client.dart';
import 'profile_repository.dart';

const trashTypes = {'book', 'blog', 'bookmark', 'document', 'task', 'topic'};

enum TrashOperation { restore, delete }

class TrashEntry {
  const TrashEntry({
    required this.id,
    required this.memberId,
    required this.type,
    required this.name,
    required this.deletedAt,
    this.resourceUrl = '',
  });
  final int id, memberId;
  final String type, name, deletedAt, resourceUrl;
  factory TrashEntry.fromJson(Map row, int owner) {
    final id = row['trash_id'],
        member = row['member_id'],
        type = row['resource_type'],
        name = row['resource_name'],
        date = row['delete_time'],
        url = row['resource_url'] ?? '';
    if (id is! int ||
        id <= 0 ||
        member != owner ||
        type is! String ||
        !trashTypes.contains(type) ||
        name is! String ||
        name.length > 16384 ||
        date is! String ||
        date.length > 80 ||
        DateTime.tryParse(date) == null ||
        url is! String ||
        url.length > 16384) {
      throw const FormatException('Invalid owned trash metadata');
    }
    return TrashEntry(
      id: id,
      memberId: owner,
      type: type,
      name: name,
      deletedAt: date,
      resourceUrl: url,
    );
  }
  bool same(TrashEntry other) =>
      id == other.id &&
      memberId == other.memberId &&
      type == other.type &&
      name == other.name &&
      deletedAt == other.deletedAt;
}

class TrashPageData {
  TrashPageData({
    required List<TrashEntry> entries,
    required this.total,
    required this.page,
    required this.pageSize,
  }) : entries = List.unmodifiable(entries);
  final List<TrashEntry> entries;
  final int total, page, pageSize;
  int get pages => total == 0 ? 1 : (total + pageSize - 1) ~/ pageSize;
}

class TrashPreflightFailure implements Exception {
  const TrashPreflightFailure();
}

abstract interface class TrashRepository {
  Future<TrashPageData> read({String type = '', int page = 1});
  Future<void> apply(TrashEntry entry, TrashOperation operation);
  Future<bool> isAbsent(TrashEntry entry);
  void dispose();
}

class RemoteTrashRepository implements TrashRepository {
  RemoteTrashRepository(this.client, {required this.memberId}) {
    if (memberId <= 0) {
      throw const FormatException('Owned trash requires member');
    }
  }
  final BookstarkClient client;
  final int memberId;
  bool _closed = false;
  final _observed = <int, TrashEntry>{};
  Future<String> _owner() async {
    if (_closed) {
      throw const TrashPreflightFailure();
    }
    final session = client.exportSession()['token'];
    if (session == null || session.isEmpty) {
      throw const TrashPreflightFailure();
    }
    await RemoteProfileRepository(client, memberId: memberId).read();
    _check(session);
    return session;
  }

  void _check(String session) {
    if (_closed || client.exportSession()['token'] != session) {
      throw const TrashPreflightFailure();
    }
  }

  @override
  Future<TrashPageData> read({String type = '', int page = 1}) async {
    if (type.isNotEmpty && !trashTypes.contains(type) ||
        page < 1 ||
        page > 1000000) {
      throw const FormatException('Invalid trash query');
    }
    final session = await _owner();
    final data = await client.trashListJson(type: type, page: page);
    _check(session);
    final rows = data['data'],
        total = data['total'],
        actualPage = data['page'],
        size = data['page_size'],
        pages = data['total_pages'];
    if (rows is! List ||
        rows.length > 20 ||
        total is! int ||
        total < 0 ||
        actualPage != page ||
        size != 20 ||
        pages is! int ||
        pages != (total == 0 ? 1 : (total + 19) ~/ 20)) {
      throw const FormatException('Invalid trash pagination');
    }
    final entries = rows.map((v) {
      if (v is! Map) {
        throw const FormatException('Invalid trash entry');
      }
      return TrashEntry.fromJson(v, memberId);
    }).toList();
    if (entries.map((v) => v.id).toSet().length != entries.length ||
        entries.any((v) => type.isNotEmpty && v.type != type) ||
        entries.length > total) {
      throw const FormatException('Invalid trash list');
    }
    for (final row in entries) {
      _observed[row.id] = row;
    }
    return TrashPageData(
      entries: entries,
      total: total,
      page: page,
      pageSize: 20,
    );
  }

  Future<List<TrashEntry>> _scan(String type) async {
    final first = await read(type: type);
    // A bounded, stable complete scan is necessary to infer absence. An
    // incomplete scan must fail rather than treat a hidden row as deleted.
    if (first.total > 10000) {
      throw StateError('Trash verification requires narrower scope');
    }
    final all = [...first.entries];
    for (var page = 2; page <= first.pages; page++) {
      final next = await read(type: type, page: page);
      if (next.total != first.total) {
        throw StateError('Trash changed during verification');
      }
      all.addAll(next.entries);
    }
    if (all.length != first.total ||
        all.map((v) => v.id).toSet().length != all.length) {
      throw StateError('Trash pagination changed during verification');
    }
    final last = await read(type: type);
    if (last.total != first.total ||
        last.entries.length != first.entries.length ||
        !List.generate(
          first.entries.length,
          (i) => first.entries[i].same(last.entries[i]),
        ).every((v) => v)) {
      throw StateError('Trash changed during verification');
    }
    return all;
  }

  @override
  Future<void> apply(TrashEntry entry, TrashOperation operation) async {
    final known = _observed[entry.id];
    if (known == null || !known.same(entry) || entry.memberId != memberId) {
      throw const TrashPreflightFailure();
    }
    final rows = await _scan(entry.type);
    if (!rows.any((v) => v.same(entry))) {
      throw const TrashPreflightFailure();
    }
    final session = await _owner();
    final receipt = await client.trashMutationJson(
      entry.id,
      restore: operation == TrashOperation.restore,
    );
    _check(session);
    if (receipt['code'] != 0 || receipt['message'] is! String) {
      throw const FormatException('Unrecognized trash receipt');
    }
  }

  @override
  Future<bool> isAbsent(TrashEntry entry) async =>
      !(await _scan(entry.type)).any((v) => v.id == entry.id);
  @override
  void dispose() {
    _closed = true;
    _observed.clear();
  }
}
