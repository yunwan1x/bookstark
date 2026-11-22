import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/owned15_creation_lifetime.dart';
import '../../core/owned15_native_creation_repository.dart';

/// Mounts the real NoteEditorPage through editorBuilder (drafts:null). Unknown
/// replaces its subtree immediately; it is never a disabled-but-still-editable
/// underlying route. Background removes the subtree before real owner drain.
class Owned15NativeCreationHost extends StatefulWidget {
  const Owned15NativeCreationHost({super.key,required this.repository,
    required this.lifetime,required this.editorBuilder,
    required this.reviewBuilder,required this.openColdReview,this.english=false});
  final Owned15NativeCreationRepository repository;
  final Owned15CreationLifetime lifetime;
  final Widget Function(BuildContext) editorBuilder;
  final Widget Function(BuildContext) reviewBuilder;
  final Future<void> Function() openColdReview;
  final bool english;
  @override State<Owned15NativeCreationHost> createState()=>_HostState();
}
class _HostState extends State<Owned15NativeCreationHost> with WidgetsBindingObserver {
  bool _released=false,_busy=false;
  @override void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.repository.reviewRequired.addListener(_changed);
    widget.lifetime.registerMemoryRelease(_release);
  }
  void _changed(){if(mounted)setState((){});}
  void _release() {
    widget.repository.releaseMemory();
    if(mounted)setState(()=>_released=true);
  }
  @override void didUpdateWidget(covariant Owned15NativeCreationHost old) {
    super.didUpdateWidget(old);
    if(!identical(old.lifetime,widget.lifetime) ||
        !identical(old.repository,widget.repository)) {
      old.repository.reviewRequired.removeListener(_changed);
      old.lifetime.unregisterMemoryRelease(_release);
      old.repository.releaseMemory();
      unawaited(old.lifetime.retire().catchError((Object _){}));
      _released=true; // A reused route never mounts another principal's editor.
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
    widget.repository.reviewRequired.removeListener(_changed);
    widget.lifetime.unregisterMemoryRelease(_release);
    widget.repository.releaseMemory();
    unawaited(widget.lifetime.retire().catchError((Object _){}));
    super.dispose();
  }
  Future<void> _cold() async {
    if(_busy)return;
    final lifetime=widget.lifetime,open=widget.openColdReview;
    setState(()=>_busy=true);
    try {
      await lifetime.retire();
      if(!mounted || !identical(lifetime,widget.lifetime) ||
        !lifetime.isCurrentScope()) {
        return;
      }
      await open();
    } finally {if(mounted)setState(()=>_busy=false);}
  }
  @override Widget build(BuildContext context) {
    if(_released) {
      return Scaffold(
      appBar:AppBar(title:Text(widget.english?'Memory draft released':'内存稿件已释放')),
      body:SafeArea(child:ListView(padding:const EdgeInsets.all(16),children:[
        Text(widget.english?
          'The previous body and password were not retained. Recovery checks actual receipts only; creation is never repeated.':
          '上次正文和密码没有保留。恢复只核对真实回执，不会再次创建。'),
        OutlinedButton(onPressed:_busy?null:_cold,
          child:Text(widget.english?'Open receipt review':'打开回执核对')),
      ])));
    }
    if(widget.repository.reviewRequired.value)return widget.reviewBuilder(context);
    return widget.editorBuilder(context);
  }
}
