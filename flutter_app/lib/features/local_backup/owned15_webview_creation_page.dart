import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/complex_editor_document.dart';
import '../../core/complex_editor_transport.dart';
import '../../core/owned_preview_controller.dart';
import '../../core/owned15_creation_lifetime.dart';
import '../complex_editors/complex_editor_browser.dart';
import '../complex_editors/article_metadata_dialog.dart';

/// All article bodies and complex note bodies use the real engine. Only the
/// explicit Save action captures and submits; retirement never writes SQL.
class Owned15WebViewCreationPage extends StatefulWidget {
  const Owned15WebViewCreationPage({super.key,required this.lifetime,
    required this.operation,required this.collection,required this.initialDocument,
    required this.reviewBuilder,required this.onMemoryReleased,this.english=false});
  final Owned15CreationLifetime lifetime;
  final String operation,collection;
  // Fresh new-resource template only; never a recovered private draft.
  final ComplexEditorDocument initialDocument;
  final Widget Function(BuildContext,ComplexEditorDocument,String) reviewBuilder;
  final Future<void> Function() onMemoryReleased;
  final bool english;
  @override State<Owned15WebViewCreationPage> createState()=>_WebCreationState();
}
class _WebCreationState extends State<Owned15WebViewCreationPage>
    with WidgetsBindingObserver {
  ComplexEditorDocument? _document;
  String? _title='';
  List<String> _labels=[];
  final _password=TextEditingController();
  bool _protect=false,_busy=false,_review=false,_released=false,_ready=false;
  int _epoch=0,_mount=0;
  String? _error;
  OwnedPreviewController _preview=OwnedPreviewController();
  ComplexEditorTransport? _transport;
  Future<void>? _work;
  String t(String zh,String en)=>widget.english?en:zh;
  bool get current=>mounted && !_released && widget.lifetime.current;
  @override void initState() {
    super.initState();
    if(!{'note','article'}.contains(widget.collection) ||
      widget.collection=='note' && widget.initialDocument.kind==ComplexEditorKind.markdown) {
      throw StateError('Typed WebView creation collection/format required');
    }
    _document=widget.initialDocument;
    widget.lifetime.registerMemoryRelease(_release);
    widget.lifetime.registerDrainer(_drain);
    WidgetsBinding.instance.addObserver(this);
  }
  void _release() {
    _epoch++;_transport=null;_document=null;_title=null;_labels=[];
    _password.clear();
    if(mounted)setState(()=>_released=true);
  }
  Future<void> _drain() async {
    await Future.wait<void>([
      _preview.retire(),
      ?_work,
    ]);
  }
  @override void didUpdateWidget(covariant Owned15WebViewCreationPage old) {
    super.didUpdateWidget(old);
    if(!identical(old.lifetime,widget.lifetime)) {
      old.lifetime.unregisterMemoryRelease(_release);
      // Keep the old drainer registered until its real operations complete.
      _release();
      unawaited(old.lifetime.retire().catchError((Object _){}));
    }
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    if(state!=AppLifecycleState.resumed) {
      _release();
      unawaited(widget.lifetime.retire().catchError((Object _){}));
    }
  }
  @override void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.lifetime.unregisterMemoryRelease(_release);
    _document=null;_title=null;_labels=[];
    _password.dispose();
    unawaited(widget.lifetime.retire().catchError((Object _){}));
    super.dispose();
  }
  Future<void> _metadata() async {
    if(!current || _busy || _review || _document==null)return;
    final epoch=_epoch;
    final result=await showDialog<ArticleMetadata>(context:context,
      builder:(context)=>ArticleMetadataDialog(title:_title??'',labels:_labels,
        document:_document!,english:widget.english,
        noteMetadata:widget.collection=='note'));
    if(!current || epoch!=_epoch || result==null)return;
    setState((){_title=result.title;_labels=List.of(result.labels);});
  }
  Future<void> _save() {
    if(!current || _busy || _review || !_ready || _transport==null) {
      return Future<void>.value();
    }
    final job=_saveOnce();
    final consumed=job.then<void>((_){},onError:(Object _,StackTrace _){});
    _work=consumed;
    return job;
  }
  Future<void> _saveOnce() async {
    final epoch=_epoch,lifetime=widget.lifetime,transport=_transport!;
    final title=_title??'',labels=List<String>.of(_labels),
      password=_protect?_password.text:null;
    bool owned()=>current && epoch==_epoch && identical(lifetime,widget.lifetime);
    setState((){_busy=true;_error=null;});
    bool submitted=false;
    try {
      final snapshot=await transport.capture();
      try {
        if(!owned())return;
        _document=snapshot.document;
      } finally {await transport.release(snapshot);}
      if(!owned())return;
      await _preview.retire();
      if(!owned())return;
      setState((){_transport=null;_ready=false;});
      final prepared=await lifetime.controller.creator.prepare(
        creationKey:widget.operation,collection:widget.collection,
        document:_document!,title:title,labels:labels,password:password);
      if(!owned()) {prepared.dispose();return;}
      submitted=true;
      setState(()=>_review=true);
      _password.clear();
      await lifetime.controller.submit(prepared);
    } catch(_) {
      if(owned()) {
        setState((){
        _error=submitted?
          t('结果需只读核对，不会再次创建。','Read-only result review is required; creation will not be repeated.'):
          t('尚未开始创建，请检查标题、格式或密码后重新操作。','Creation has not started. Check the title, format or password.');
        if(!submitted) {
          _preview=OwnedPreviewController();
          _mount++;_ready=false;
        }
      });
      }
    } finally {if(owned())setState(()=>_busy=false);}
  }
  Future<void> _reload() async {
    if(!current || _busy || _review)return;
    // Reload without a captured current draft would silently lose user edits.
    setState(()=>_error=t('请先明确保存或返回；不会自动重载内存稿件。',
      'Save explicitly or go back. The memory draft is not reloaded automatically.'));
  }
  Future<void> _cold() async {
    final lifetime=widget.lifetime,open=widget.onMemoryReleased;
    await lifetime.retire();
    if(!mounted || !identical(lifetime,widget.lifetime) ||
        !lifetime.isCurrentScope()) {
      return;
    }
    await open();
  }
  @override Widget build(BuildContext context) {
    if(_released) {
      return Scaffold(appBar:AppBar(title:Text(t('内存稿件已释放','Memory draft released'))),
      body:SafeArea(child:ListView(padding:const EdgeInsets.all(16),children:[
        Text(t('正文和密码没有保留。只可重新打开真实回执核对，不会再次创建。',
          'Body and password were not retained. Reopen actual receipt review; creation will not be repeated.')),
        OutlinedButton(onPressed:_cold,
          child:Text(t('核对操作记录','Review operation record'))),
      ])));
    }
    final document=_document!;
    if(_review)return widget.reviewBuilder(context,document,_title??'');
    return Scaffold(appBar:AppBar(title:Text(t('新建本机资料','New local content')),
      actions:[IconButton(onPressed:_busy?null:_metadata,icon:const Icon(Icons.edit_outlined),
        tooltip:t('标题和标签','Title and labels'))]),
      body:SafeArea(child:SingleChildScrollView(child:Column(children:[
        Padding(padding:const EdgeInsets.all(12),child:Text(t(
          '稿件仅在内存中。明确保存后才创建；关闭或进入后台会丢失未保存正文。',
          'The draft is memory-only. Only explicit Save creates content. Closing or backgrounding loses unsaved text.'))),
        if(_error!=null)Padding(padding:const EdgeInsets.all(8),child:Text(_error!)),
        SizedBox(height:360,child:ComplexEditorBrowser(key:ValueKey(_mount),
          document:document,title:_title??'',english:widget.english,
          readOnly:false,retirementController:_preview,
          onReady:(transport)async{if(current)setState((){_transport=transport;_ready=true;});},
          onState:(state){if(current && _ready!=state.ready)setState(()=>_ready=state.ready);},
          onSaveRequested:_save,beforeRetire:(transport)async{},
          onReloadRequested:_reload)),
        Padding(padding:const EdgeInsets.all(12),child:Column(
          mainAxisSize:MainAxisSize.min,children:[
            SwitchListTile(contentPadding:EdgeInsets.zero,title:Text(t('保护新资料','Protect new content')),
              value:_protect,onChanged:_busy?null:(value)=>setState(()=>_protect=value)),
            if(_protect)TextField(controller:_password,obscureText:true,
              enabled:!_busy,autocorrect:false,enableSuggestions:false,
              decoration:InputDecoration(labelText:t('仅本次内存密码','Memory-only password'))),
            FilledButton(onPressed:_busy || !_ready?null:_save,
              child:Text(t('明确保存并创建','Save and create explicitly'))),
          ])),
      ]))));
  }
}
