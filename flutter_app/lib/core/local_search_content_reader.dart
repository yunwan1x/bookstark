import 'dart:math' as math;
import 'dart:typed_data';
import 'package:sqflite/sqflite.dart';
import 'bounded_note_text_reader.dart';

final class LocalSearchContentLimit implements Exception{
 const LocalSearchContentLimit();
 @override String toString()=>'Search content exceeds the safe reading budget. Narrow the query. / 搜索内容超出安全读取预算，请缩小查询范围。';
}

/// One request, not one candidate: never silently returns partial source/results.
class LocalSearchContentReader{
 LocalSearchContentReader({required this.guard});
 static const maxRecordBytes=20*1024*1024,maxTotalBytes=32*1024*1024,chunkBytes=64*1024;
 final void Function() guard;
 int _used=0;
 void reserve(Object? value){
  guard();
  if(value is! int||value<0||value>maxRecordBytes||_used>maxTotalBytes-value) {
    throw const LocalSearchContentLimit();
  }
  _used+=value;
 }
 Future<String> readTopicField(DatabaseExecutor tx,{
  required int topicId,required String field,required int id,
 })async{
  if(topicId<=0||id<=0)throw const FormatException('Actual topic identity required');
  final (table,key,column,scope)=switch(field){
   'question'=>('topics','topic_id','question','topic_id=? AND deleted=0'),
   'summary'=>('topic_summaries','summary_id','content','topic_id=?'),
   'resourceTitle'=>('topic_resources','topic_resource_id','title_snapshot','topic_id=?'),
   'resourceDescription'=>('topic_resources','topic_resource_id','desc_snapshot','topic_id=?'),
   'task'=>('tasks','task_id','content','topic_id=? AND deleted=0'),
   _=>throw const FormatException('Unknown fixed search field'),
  };
  guard();
  final args=[id,topicId];
  final sizes=await tx.rawQuery('SELECT length(CAST($column AS BLOB)) AS n FROM $table WHERE $key=? AND $scope',args);
  guard();
  if(sizes.length!=1)throw StateError('Topic search source changed');
  final size=sizes.single['n'];
  if(size is! int)throw const FormatException('Invalid topic byte length');
  reserve(size);
  final bytes=Uint8List(size);
  for(var offset=0;offset<size;){
   guard();final count=math.min(chunkBytes,size-offset);
   final rows=await tx.rawQuery('SELECT substr(CAST($column AS BLOB),?,?) AS chunk FROM $table WHERE $key=? AND $scope',[offset+1,count,...args]);
   guard();final chunk=rows.length==1?rows.single['chunk']:null;
   if(chunk is! Uint8List||chunk.length!=count)throw StateError('Topic search source incomplete');
   bytes.setRange(offset,offset+count,chunk);offset+=count;
  }
  guard();return BoundedNoteTextReader.decodeUtf8PreservingBom(bytes);
 }
 Future<({String question,String context})> topicContext(DatabaseExecutor tx,int id)async{
  guard();
  // SQL scalar preflight occurs before fetching any TEXT or child ID arrays.
  final stats=await tx.rawQuery('''
   SELECT length(CAST(t.question AS BLOB)) AS question_bytes,
    (SELECT COUNT(*) FROM topic_summaries s WHERE s.topic_id=t.topic_id) AS summaries,
    (SELECT COUNT(*) FROM topic_resources r WHERE r.topic_id=t.topic_id) AS resources,
    (SELECT COUNT(*) FROM tasks k WHERE k.topic_id=t.topic_id AND k.deleted=0) AS tasks,
    COALESCE((SELECT SUM(length(CAST(s.content AS BLOB))) FROM topic_summaries s WHERE s.topic_id=t.topic_id),0) AS summary_bytes,
    COALESCE((SELECT SUM(length(CAST(r.title_snapshot AS BLOB))+length(CAST(r.desc_snapshot AS BLOB))) FROM topic_resources r WHERE r.topic_id=t.topic_id),0) AS resource_bytes,
    COALESCE((SELECT SUM(length(CAST(k.content AS BLOB))) FROM tasks k WHERE k.topic_id=t.topic_id AND k.deleted=0),0) AS task_bytes
   FROM topics t WHERE t.topic_id=? AND t.deleted=0''',[id]);
  guard();if(stats.length!=1)throw StateError('Topic search source missing');
  final row=stats.single;var count=0,total=0;
  for(final key in ['summaries','resources','tasks']){
   final v=row[key];if(v is! int||v<0)throw const FormatException('Invalid topic child count');count+=v;
  }
  for(final key in ['question_bytes','summary_bytes','resource_bytes','task_bytes']){
   final v=row[key];if(v is! int||v<0)throw const FormatException('Invalid topic byte metadata');total+=v;
  }
  // Newline framing itself is bounded too; no unbounded GROUP_CONCAT CursorWindow.
  final framing=count*2+3;
  if(count>10000||total+framing>maxRecordBytes||_used>maxTotalBytes-total-framing) {
    throw const LocalSearchContentLimit();
  }
  reserve(framing);
  final question=await readTopicField(tx,topicId:id,field:'question',id:id);
  final summaries=StringBuffer(),resources=StringBuffer(),tasks=StringBuffer();
  var summarySeen=false,resourceSeen=false,taskSeen=false;
  for(final source in const [('topic_summaries','summary_id'),('topic_resources','topic_resource_id'),('tasks','task_id')]){
   final (table,key)=source;
   final active=table=='tasks'?' AND deleted=0':'';
   final rows=await tx.rawQuery('SELECT $key AS id FROM $table WHERE topic_id=?$active ORDER BY $key',[id]);
   guard();
   for(final child in rows){
    final childId=child['id'];if(childId is! int||childId<=0)throw const FormatException('Invalid topic child identity');
    if(table=='topic_summaries'){
     if(summarySeen)summaries.write('\n');summarySeen=true;
     summaries.write(await readTopicField(tx,topicId:id,field:'summary',id:childId));
    }else if(table=='topic_resources'){
     if(resourceSeen)resources.write('\n');resourceSeen=true;
     resources.write(await readTopicField(tx,topicId:id,field:'resourceTitle',id:childId));
     resources.write('\n');
     resources.write(await readTopicField(tx,topicId:id,field:'resourceDescription',id:childId));
    }else{
     if(taskSeen)tasks.write('\n');taskSeen=true;
     tasks.write(await readTopicField(tx,topicId:id,field:'task',id:childId));
    }
   }
  }
  guard();return (question:question,context:[question,summaries.toString(),resources.toString(),tasks.toString()].join('\n'));
 }
}
