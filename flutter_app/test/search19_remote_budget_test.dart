import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/search_repository.dart';

Map<String,Object?> empty()=>{'counts':{for(final name in searchGroupKeys.values)name:0},
 for(final name in searchGroupKeys.values)name:[]};
class _Wire extends http.BaseClient{
 _Wire(this.stream);final Stream<List<int>> Function() stream;
 int requests=0;Uri? uri;
 @override Future<http.StreamedResponse> send(http.BaseRequest request)async{
  requests++;uri=request.url;
  expect(request.method,'GET');expect(request.followRedirects,isFalse);
  return http.StreamedResponse(stream(),200,request:request,headers:{'content-type':'application/json; charset=utf-8'});
 }
 @override void close(){}
}
void main(){
 test('actual bounded search retains exact prefixed path seven null/list groups and query',( )async{
  final body=empty();final transport=MockClient((r)async{
   expect(r.url.path,'/prefix/api/search');expect(r.url.queryParameters,{'q':'100%_阅读\\'});
   expect(r.method,'GET');expect(r.followRedirects,isFalse);
   return http.Response(jsonEncode({'code':0,'data':body}),200,headers:{'content-type':'application/json'});
  });
  final client=BookstarkClient('https://fixture.invalid/prefix',transport:transport);
  client.restoreSession({'token':'synthetic-search'});
  try{
   final results=await RemoteSearchRepository(client).search(' 100%_阅读\\ ');
   expect(results.query,'100%_阅读\\');expect(results.loaded,0);
  }finally{client.close();}
 });
 test('stream over2MiB aborts before complete body EOF and yields no result',( )async{
  var yielded=0,cancelled=false;
  Stream<List<int>> stream()async*{
   try{for(var i=0;i<1024;i++){yielded++;yield List<int>.filled(4096,32);}}
   finally{cancelled=true;}
  }
  final wire=_Wire(stream);
  final scoped=BookstarkClient('https://fixture.invalid',transport:wire);
  scoped.restoreSession({'token':'synthetic-search'});
  try{
   await expectLater(RemoteSearchRepository(scoped).search('Exact'),throwsA(isA<ApiFailure>().having((e)=>e.status,'status',413)));
   expect(cancelled,isTrue);expect(yielded,lessThanOrEqualTo(513));expect(yielded,lessThan(1024));expect(wire.requests,1);
  }finally{scoped.close();}
 });
 for(final mode in ['duplicate','depth','array','field','invalid-utf8']){
  test('strict complete bounded search rejects $mode without partial groups',()async{
   final data=empty();String raw;
   if(mode=='duplicate'){
    final encoded=jsonEncode(data);raw='{"code":0,"data":$encoded,"data":$encoded}';
   }else if(mode=='depth'){
    Object? nested='tail';for(var i=0;i<12;i++){nested={'nested':nested};}
    raw=jsonEncode({'code':0,'data':data,'ignored':nested});
   }else if(mode=='array'){
    data['books']=List.generate(21,(i)=>{'id':i+1,'name':'Book'});
    (data['counts'] as Map)['books']=21;raw=jsonEncode({'code':0,'data':data});
   }else if(mode=='field'){
    data['books']=[{'id':1,'name':'x'*65537}];(data['counts'] as Map)['books']=1;
    raw=jsonEncode({'code':0,'data':data});
   }else{raw=jsonEncode({'code':0,'data':data});}
   final bytes=[...utf8.encode(raw),if(mode=='invalid-utf8')255];
   final wire=_Wire(()=>Stream.fromIterable([bytes.sublist(0,bytes.length~/2),bytes.sublist(bytes.length~/2)]));
   final client=BookstarkClient('https://fixture.invalid',transport:wire);client.restoreSession({'token':'synthetic-search'});
   try{
    await expectLater(RemoteSearchRepository(client).search('Exact'),throwsA(isA<ApiFailure>()));
    expect(wire.requests,1);
   }finally{client.close();}
  });
 }
}
