import 'complex_editor_document.dart';
import 'spreadsheet_document.dart';

/// Immutable pre-editor choice. It cannot retarget an existing operation.
final class Owned15CreationTarget {
  Owned15CreationTarget({required this.collection,required this.kind}) {
    if(!{'note','article'}.contains(collection)) {
      throw ArgumentError('Owned15 note/article collection required');
    }
  }
  final String collection;
  final ComplexEditorKind kind;
  bool get nativeMarkdownNote=>collection=='note' && kind==ComplexEditorKind.markdown;
  ComplexEditorDocument newDocument(String operation) {
    if(!RegExp(r'^[a-f0-9]{32}$').hasMatch(operation)) {
      throw ArgumentError('Fresh operation identity required');
    }
    final source=switch(kind) {
      ComplexEditorKind.markdown=>'',
      ComplexEditorKind.html=>'<!doctype html>\n<html><body></body></html>\n',
      ComplexEditorKind.spreadsheet=>SpreadsheetDocument.empty(
        workbookId:'w$operation',sheetId:'s$operation').source,
      ComplexEditorKind.drawing=>'{"elements":[],"appState":{}}',
      ComplexEditorKind.mindmap=>'{"nodeData":{"id":"root","topic":"New","children":[]}}',
      ComplexEditorKind.richdoc=>'{"schema":"bookstark-richdoc","schema_version":1,"data":{"main":[{"value":""}]}}',
      ComplexEditorKind.presentation=>'{"width":1000,"height":562.5,"slides":[{"id":"slide","elements":[]}]}',
    };
    return ComplexEditorDocument.parse(kind,source);
  }
}
