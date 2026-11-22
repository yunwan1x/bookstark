import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'complex_editor_document.dart';
import 'complex_reading_protocol.dart';
import 'complex_reading_selection.dart';

/// Canonical public resource proof. It is never a counterfeit book identity.
class PublicSelectionIdentity {
  PublicSelectionIdentity({
    required this.tuple,
    required this.kind,
    required this.sourceDigest,
  }) {
    if (kind == ComplexEditorKind.markdown ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sourceDigest) ||
        utf8.encode(tuple).length > 16384) {
      throw const FormatException('Invalid public source identity');
    }
  }
  final String tuple, sourceDigest;
  final ComplexEditorKind kind;
  String get identityDigest => sha256.convert(utf8.encode(tuple)).toString();
}

class PublicSelectionBinding {
  PublicSelectionBinding(
    this.identity, {
    required this.runtimeLease,
    required this.generation,
  }) {
    if (runtimeLease.length < 16 ||
        runtimeLease.length > 128 ||
        generation < 1) {
      throw const FormatException('Invalid public runtime');
    }
  }
  final PublicSelectionIdentity identity;
  final String runtimeLease;
  final int generation;
  Map<String, Object?> toJson() => {
    'version': 1,
    'resource': 'public-share',
    'identityDigest': identity.identityDigest,
    'kind': identity.kind.name,
    'sourceDigest': identity.sourceDigest,
    'runtimeLease': runtimeLease,
    'generation': generation,
  };
  void verify(Object? value) {
    final expected = toJson();
    if (value is! Map ||
        value.length != expected.length ||
        !expected.entries.every((e) => value[e.key] == e.value)) {
      throw const FormatException('Public selection runtime changed');
    }
  }
}

class PublicSelectionCapture {
  PublicSelectionCapture(this.text, this.kind, this.range, this.anchor);
  final String text;
  final ComplexReadingSelectionKind kind;
  final ComplexReadingSelection range;
  final ComplexReadingAnchor? anchor;
  factory PublicSelectionCapture.parse(
    PublicSelectionBinding binding,
    Object? raw,
  ) {
    if (raw is! Map ||
        raw.keys.toSet().difference({
          'binding',
          'text',
          'anchor',
          'supported',
          'selectionKind',
          'selection',
        }).isNotEmpty ||
        utf8.encode(jsonEncode(raw)).length > 65536) {
      throw const FormatException('Invalid public capture');
    }
    binding.verify(raw['binding']);
    final text = raw['text'];
    if (raw['supported'] != true ||
        text is! String ||
        text.trim().isEmpty ||
        utf8.encode(text).length > 32768) {
      throw const FormatException('No actual readable public selection');
    }
    ComplexEditorDocument.validateText(text);
    final expected = switch (binding.identity.kind) {
      ComplexEditorKind.html || ComplexEditorKind.richdoc => 'text',
      ComplexEditorKind.spreadsheet => 'cells',
      ComplexEditorKind.drawing => 'elements',
      ComplexEditorKind.mindmap => 'nodes',
      ComplexEditorKind.presentation => 'slide',
      _ => 'none',
    };
    if (raw['selectionKind'] != expected || raw['selection'] == null) {
      throw const FormatException('Wrong public selection kind');
    }
    return PublicSelectionCapture(
      text,
      ComplexReadingSelectionKind.values.byName(expected),
      ComplexReadingSelection.parse(binding.identity.kind, raw['selection']),
      raw['anchor'] == null
          ? null
          : ComplexReadingAnchor.parse(binding.identity.kind, raw['anchor']),
    );
  }
}
