import 'package:flutter/material.dart';
import '../../core/complex_editor_document.dart';
import '../../core/owned15_creation_target.dart';

/// Reuses the selected creation-v1 collection/format controls. Selection happens
/// before allocating an operation, showing an editor or issuing any mutation.
class Owned15CreationTargetDialog extends StatefulWidget {
  const Owned15CreationTargetDialog({super.key,this.english=false});
  final bool english;
  @override State<Owned15CreationTargetDialog> createState()=>_TargetState();
}
class _TargetState extends State<Owned15CreationTargetDialog> {
  String _collection='note';
  ComplexEditorKind _kind=ComplexEditorKind.markdown;
  String t(String zh,String en)=>widget.english?en:zh;
  @override Widget build(BuildContext context)=>AlertDialog(
    scrollable:true,title:Text(t('新建本机资料','New local content')),
    content:SizedBox(width:380,child:Column(mainAxisSize:MainAxisSize.min,children:[
      SegmentedButton<String>(
        segments:[ButtonSegment(value:'note',label:Text(t('笔记','Note'))),
          ButtonSegment(value:'article',label:Text(t('文章','Article')))],
        selected:{_collection},onSelectionChanged:(values)=>setState(()=>_collection=values.single)),
      const SizedBox(height:16),
      DropdownButtonFormField<ComplexEditorKind>(initialValue:_kind,isExpanded:true,
        decoration:InputDecoration(labelText:t('格式','Format')),
        items:[for(final kind in ComplexEditorKind.values)
          DropdownMenuItem(value:kind,child:Text(kind.name))],
        onChanged:(kind){if(kind!=null)setState(()=>_kind=kind);}),
      const SizedBox(height:12),
      Text(t('稿件仅存于内存。只有编辑器中的明确保存才会创建；文章始终使用 WebView。',
        'Drafts stay in memory. Only explicit Save in the editor creates content. Articles always use WebView.')),
    ])),
    actions:[TextButton(onPressed:()=>Navigator.pop(context),
      child:Text(t('取消','Cancel'))),
      FilledButton(onPressed:()=>Navigator.pop(context,
        Owned15CreationTarget(collection:_collection,kind:_kind)),
        child:Text(t('开始编辑','Start editing')))],
  );
}
