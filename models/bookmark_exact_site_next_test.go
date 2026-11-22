package models

import "testing"

func TestBookmarkSiteMatchesRootAndExactAuthorityAcrossQueryAndIDs(t *testing.T) {
 initAssetTestDB(t)
 urls:=[]string{
  "https://example.test","http://example.test","https://example.test/",
  "https://example.test?x=1","https://example.test#anchor","https://EXAMPLE.test/path",
  "https://example.test:8443","https://example.test:8443?x=1","http://example.test:8443/path",
  "https://example.test.evil/path","https://evil-example.test/path",
  "https://example.test:84430/path","https://example.test@evil.test/path",
 }
 ids:=map[string]int64{}
 for _,u:=range urls{
  b:=&Bookmark{Title:"unchanged "+u,URL:u,MemberID:1}
  if err:=b.Insert();err!=nil{t.Fatal(err)}
  ids[u]=b.BookmarkID
 }
 cases:=[]struct{site string;want []string}{
  {"example.test",urls[:6]},
  {"example.test:8443",urls[6:9]},
  {"EXAMPLE.TEST",urls[:6]},
 }
 for _,tc:=range cases{
  q:=BookmarkQuery{MemberID:1,Site:tc.site,Page:1,PageSize:200}
  result,err:=QueryBookmarks(q);if err!=nil{t.Fatal(err)}
  gotIDs,err:=QueryBookmarkIDsByFilter(q);if err!=nil{t.Fatal(err)}
  expected:=map[int64]bool{}
  for _,u:=range tc.want{expected[ids[u]]=true}
  if result.Total!=len(expected)||len(result.Data)!=len(expected)||len(gotIDs)!=len(expected){
   t.Fatalf("site %q incorrect row/total/IDs counts: %d/%d/%d",tc.site,result.Total,len(result.Data),len(gotIDs))
  }
  for _,b:=range result.Data{if !expected[b.BookmarkID]{t.Fatalf("site %q escaped authority: %q",tc.site,b.URL)}}
  for _,id:=range gotIDs{if !expected[id]{t.Fatalf("site %q wrong ID %d",tc.site,id)}}
 }
 for u,id:=range ids{
  var actual string
  if err:=DB.QueryRow("SELECT url FROM md_bookmark WHERE bookmark_id=?",id).Scan(&actual);err!=nil{t.Fatal(err)}
  if actual!=u{t.Fatalf("filter changed URL bytes %q",u)}
 }
}
