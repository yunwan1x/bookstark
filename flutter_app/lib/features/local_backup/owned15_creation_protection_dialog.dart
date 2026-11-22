import 'package:flutter/material.dart';

/// Ephemeral result only. The route owner must clear this holder on retirement.
final class Owned15MemoryProtection {
  Owned15MemoryProtection(this.password);
  String? password;
  bool get protected=>password!=null;
  void clear(){password=null;}
}
class Owned15CreationProtectionDialog extends StatefulWidget {
  const Owned15CreationProtectionDialog({super.key,this.english=false});
  final bool english;
  @override State<Owned15CreationProtectionDialog> createState()=>_ProtectionState();
}
class _ProtectionState extends State<Owned15CreationProtectionDialog> {
  bool _protected=false;
  final _password=TextEditingController();
  String t(String zh,String en)=>widget.english?en:zh;
  @override void dispose(){_password.clear();_password.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>AlertDialog(scrollable:true,
    title:Text(t('新资料保护状态','Protection for new content')),
    content:SizedBox(width:380,child:Column(mainAxisSize:MainAxisSize.min,children:[
      SwitchListTile(contentPadding:EdgeInsets.zero,
        title:Text(t('保护此资料','Protect this content')),value:_protected,
        onChanged:(value)=>setState(()=>_protected=value)),
      if(_protected)TextField(controller:_password,obscureText:true,
        autocorrect:false,enableSuggestions:false,
        onChanged:(_)=>setState((){}),
        decoration:InputDecoration(labelText:t('仅本次内存密码','Memory-only password'))),
      Text(t('正文与密码不写入恢复记录。关闭未保存的编辑器会丢失稿件。',
        'Body and password are not written to recovery records. Closing an unsaved editor loses the draft.')),
    ])),
    actions:[TextButton(onPressed:()=>Navigator.pop(context),
      child:Text(t('取消','Cancel'))),
      FilledButton(onPressed:_protected && _password.text.isEmpty?null:
        ()=>Navigator.pop(context,Owned15MemoryProtection(_protected?_password.text:null)),
        child:Text(t('开始编辑','Start editing')))],
  );
}
