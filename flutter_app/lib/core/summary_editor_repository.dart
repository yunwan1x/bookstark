import 'notes_repository.dart';
import 'topics_repository.dart';

/// Native Markdown editor adapter. These writes never go to the notes API.
class SummaryEditorRepository implements NotesRepository {
  SummaryEditorRepository(this.topics, TopicSummary summary)
    : _current = summary;
  final TopicsRepository topics;
  TopicSummary _current;
  @override
  Future<Note> read(int id) async {
    if (id != _current.id) {
      throw const FormatException('Summary editor identity changed');
    }
    final writer = topics;
    if (writer is SummaryContentWriter) {
      _current = await (writer as SummaryContentWriter).readSummaryForEditing(
        _current.topicId,
        id,
      );
      return Note(
        id: id,
        title: '',
        content: _current.content,
        updatedAt: _current.modifiedAt,
      );
    }
    final detail = await topics.read(_current.topicId);
    final matches = detail.summaries.where((item) => item.id == id);
    if (matches.length != 1) {
      throw StateError('小结不存在 / Summary no longer exists');
    }
    _current = matches.single;
    return Note(
      id: id,
      title: '',
      content: _current.content,
      updatedAt: _current.modifiedAt,
    );
  }

  @override
  Future<int> save(Note note) async {
    if (note.id != _current.id || note.isProtected || note.labels.isNotEmpty) {
      throw const FormatException('Invalid summary editor resource');
    }
    final writer = topics;
    if (note.id != null && writer is SummaryContentWriter) {
      _current = await (writer as SummaryContentWriter).saveSummaryContent(
        _current,
        note.content,
      );
      return _current.id!;
    }
    final value = TopicSummary(
      id: note.id,
      topicId: _current.topicId,
      content: note.content,
      type: _current.type,
      order: _current.order,
    );
    value.writeBody();
    _current = await topics.saveSummary(value);
    return _current.id!;
  }

  @override
  Future<List<Note>> list({String keyword = '', int page = 1}) async =>
      throw UnsupportedError('Use the topic summary list');
  @override
  Future<void> remove(int id) async =>
      throw UnsupportedError('Delete summaries from the topic menu');
}
