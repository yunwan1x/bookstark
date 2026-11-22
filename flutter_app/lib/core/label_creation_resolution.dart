import 'label_creation_attempt.dart';
export 'label_creation_attempt.dart' show LabelCreationOrigin;

/// A manually adopted global label is never represented as a POST receipt.
class LabelCreationResolution {
  LabelCreationResolution({
    required this.origin,
    required Map<String, Object?> wire,
  }) : wire = Map.unmodifiable(wire);
  final LabelCreationOrigin origin;
  final Map<String, Object?> wire;
}
