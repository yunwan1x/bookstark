import 'protected_owned_complex_journal.dart';

/// Slot lookup is independent of the current format or protection flag.
/// This guard runs before Markdown/HTML/complex routing, never after a reader
/// already opened. A corrupt/failed read blocks just like a retained marker.
class ProtectedOwnedResourceGate {
  ProtectedOwnedResourceGate({
    required this.server,
    required this.memberId,
    required this.namespace,
    required this.readValue,
    required this.writeValue,
    required this.deleteValue,
    required this.flush,
    required this.isCurrent,
  });
  final String server, namespace;
  final int memberId;
  final Future<String?> Function(String) readValue;
  final Future<void> Function(String, String) writeValue;
  final Future<void> Function(String) deleteValue;
  final Future<void> Function() flush;
  final bool Function() isCurrent;
  Future<bool> hasRetainedMarker(int resourceId) async {
    if (!isCurrent()) throw StateError('Resource scope retired');
    // The kind argument validates a supported identity but is deliberately not
    // in the stable resource slot; historical kind is bound by the record hash.
    final journal = ProtectedOwnedComplexJournal(
      scope: ProtectedOwnedComplexJournal.scopeFor(
        server: server,
        memberId: memberId,
        namespace: namespace,
        resourceId: resourceId,
        kind: 'drawing',
      ),
      ownerTag: ProtectedOwnedComplexJournal.ownerTagFor(
        server: server,
        memberId: memberId,
        namespace: namespace,
      ),
      isCurrent: isCurrent,
      readValue: readValue,
      writeValue: writeValue,
      deleteValue: deleteValue,
      flush: flush,
    );
    try {
      final marker = await journal.load();
      if (!isCurrent()) throw StateError('Resource scope retired');
      return marker != null;
    } finally {
      journal.retire();
    }
  }
}
