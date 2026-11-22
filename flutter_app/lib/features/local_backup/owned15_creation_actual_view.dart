import 'package:flutter/material.dart';
import '../../core/complex_editor_document.dart';
import '../../core/local_generation_content_repository.dart';
import '../../core/owned15_creation_lifetime.dart';
import '../../core/owned_preview_controller.dart';
import '../../widgets/bookstark_markdown.dart';
import '../complex_editors/complex_editor_browser.dart';

/// Only a freshly opened sealed owner's handle can populate this view.
/// No editing, saving, upload, AI, export, external URLs or network fallback.
class Owned15CreationActualView extends StatefulWidget {
  const Owned15CreationActualView({super.key,required this.handle,
    required this.lifetime,required this.preview,this.english=false});
  final GenerationContentHandle handle;
  final Owned15CreationLifetime lifetime;
  final OwnedPreviewController preview;
  final bool english;
  @override State<Owned15CreationActualView> createState()=>_ActualViewState();
}
class _ActualViewState extends State<Owned15CreationActualView> {
  bool _released=false,_ready=false;
  String t(String zh,String en)=>widget.english?en:zh;
  bool get current=>mounted && !_released && widget.lifetime.current &&
    widget.handle.isCurrent;
  @override void initState() {
    super.initState();
    widget.lifetime.registerMemoryRelease(_release);
    widget.lifetime.registerDrainer(widget.preview.retire);
    final metadata=widget.handle.metadata;
    _ready=metadata.collection=='note' && metadata.format.name=='markdown';
  }
  void _release() {
    widget.handle.close();
    if(mounted)setState(()=>_released=true);
  }
  @override void dispose() {
    widget.lifetime.unregisterMemoryRelease(_release);
    widget.handle.close();
    super.dispose();
  }
  @override Widget build(BuildContext context) {
    if(!current) {
      return Scaffold(appBar:AppBar(title:Text(t('资料已关闭','Content closed'))),
      body:Center(child:Text(t('空间或会话已变化，正文已释放。','The space or session changed. Content was released.'))));
    }
    final metadata=widget.handle.metadata;
    final document=ComplexEditorDocument.parse(
      ComplexEditorKind.parse(metadata.format.name),widget.handle.source);
    final native=metadata.collection=='note' && document.kind==ComplexEditorKind.markdown;
    return Scaffold(appBar:AppBar(title:Text(metadata.title)),body:SafeArea(child:Column(children:[
      Padding(padding:const EdgeInsets.all(12),child:Text(
        t('当前实际资料 ID：','Actual current resource ID: ')+metadata.id.toString())),
      Expanded(child:native?
        SingleChildScrollView(padding:const EdgeInsets.all(16),child:BookstarkMarkdown(
          data:document.source,english:widget.english,
          imageBuilder:(uri,title,alt)=>Text(alt??t('图片未载入','Image unavailable')),
          onLink:(text,href)async{})):
        ComplexEditorBrowser(document:document,title:metadata.title,
          english:widget.english,readOnly:true,retirementController:widget.preview,
          onReady:(transport)async{if(current)setState(()=>_ready=true);},
          onReloadRequested:()async{if(current)setState(()=>_ready=false);})),
      Padding(padding:const EdgeInsets.all(12),child:TextButton(
        onPressed:!_ready?null:()=>Navigator.pop(context,true),
        child:Text(t('完成只读查看','Finish read-only review')))),
    ])));
  }
}
