import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/owned15_creation_target.dart';
import 'package:bookstark_flutter/features/local_backup/owned15_creation_target_dialog.dart';
import 'package:bookstark_flutter/features/local_backup/owned15_creation_protection_dialog.dart';
void main() {
  test('all seven fresh templates parse without changing article dispatch',(){
    for(final collection in ['note','article']) {
      for(final kind in ComplexEditorKind.values) {
        final target=Owned15CreationTarget(collection:collection,kind:kind);
        final document=target.newDocument('a'*32);
        expect(document.kind,kind);
        expect(target.nativeMarkdownNote,collection=='note' && kind==ComplexEditorKind.markdown);
      }
    }
  });
  testWidgets('English320 font2 keyboard180 target controls reachable, selection never creates', (tester)async{
    tester.view.physicalSize=const Size(320,800);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Owned15CreationTarget? choice;
    await tester.pumpWidget(MaterialApp(
      builder:(context,child)=>MediaQuery(
        data:MediaQuery.of(context).copyWith(textScaler:TextScaler.linear(2),
          viewInsets:const EdgeInsets.only(bottom:180)),child:child!),
      home:Builder(builder:(context)=>Scaffold(body:TextButton(
        onPressed:()async{choice=await showDialog<Owned15CreationTarget>(
          context:context,builder:(context)=>const Owned15CreationTargetDialog(english:true));},
        child:const Text('Choose'))))));
    await tester.tap(find.text('Choose'));await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Article'));await tester.tap(find.text('Article'));
    await tester.pumpAndSettle();
    final start=find.text('Start editing');
    await tester.ensureVisible(start);await tester.pumpAndSettle();
    expect(start.hitTestable(),findsOneWidget);
    await tester.tap(start);await tester.pumpAndSettle();
    expect(choice!.collection,'article');expect(choice!.nativeMarkdownNote,false);
    expect(tester.takeException(),isNull);
  });
  testWidgets('protection cancel retains no result and empty password cannot continue',(tester)async{
    Owned15MemoryProtection? choice;
    await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(
      body:TextButton(onPressed:()async{choice=await showDialog<Owned15MemoryProtection>(
        context:context,builder:(context)=>const Owned15CreationProtectionDialog(english:true));},
        child:const Text('Open'))))));
    await tester.tap(find.text('Open'));await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,isNull);
    await tester.enterText(find.byType(TextField),'runtime-only-test');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,isNotNull);
    await tester.tap(find.text('Cancel'));await tester.pumpAndSettle();
    expect(choice,isNull);expect(tester.takeException(),isNull);
  });
}
