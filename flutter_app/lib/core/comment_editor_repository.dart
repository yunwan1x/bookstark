import 'notes_repository.dart';
import 'topics_repository.dart';

/// Shared native Markdown editor adapter; target identity is immutable.
class CommentEditorRepository implements NotesRepository {
  CommentEditorRepository(this.topics, TopicComment comment)
    : _current = comment;
  final TopicsRepository topics;
  TopicComment _current;
  @override
  Future<Note> read(int id) async {
    var page = 1;
    while (true) {
      final result = await topics.comments(
        _current.topicId,
        target: _current.target,
        targetId: _current.targetId,
        page: page,
      );
      for (final item in result.items) {
        if (item.id == id) {
          _current = item;
          return Note(
            id: id,
            title: '',
            content: item.content,
            updatedAt: item.modifiedAt,
          );
        }
      }
      if (!result.hasMore) throw StateError('评论不存在 / Comment no longer exists');
      if (result.items.isEmpty || result.page != page) {
        throw const FormatException('Invalid comment pagination');
      }
      page++;
    }
  }

  @override
  Future<int> save(Note note) async {
    if (note.id != _current.id || note.isProtected || note.labels.isNotEmpty) {
      throw const FormatException('Invalid comment editor resource');
    }
    final value = TopicComment(
      id: note.id,
      topicId: _current.topicId,
      target: _current.target,
      targetId: _current.targetId,
      content: note.content,
    );
    value.writeBody(updating: note.id != null);
    _current = await topics.saveComment(value);
    return _current.id!;
  }

  @override
  Future<List<Note>> list({String keyword = '', int page = 1}) async =>
      throw UnsupportedError('Use the topic comments list');
  @override
  Future<void> remove(int id) async =>
      throw UnsupportedError('Delete comments from the topic menu');
}
