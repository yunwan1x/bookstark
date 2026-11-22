package models

import (
 "database/sql"
 "encoding/json"
 "path/filepath"
 "reflect"
 "testing"
)

func labelMergeFixture(t *testing.T)*sql.DB {
 t.Helper()
 db,err:=sql.Open("sqlite",filepath.Join(t.TempDir(),"label-merge.db"));if err!=nil{t.Fatal(err)}
 db.SetMaxOpenConns(1)
 previous:=DB;DB=db;t.Cleanup(func(){DB=previous;db.Close()})
 for _,query:=range []string{
  "CREATE TABLE md_label(label_id INTEGER PRIMARY KEY,label_name TEXT NOT NULL UNIQUE)",
  "CREATE TABLE md_label_relation(id INTEGER PRIMARY KEY,label_id INTEGER,resource_id INTEGER,relation_type TEXT,created_at TEXT)",
  "CREATE TABLE md_books(book_id INTEGER PRIMARY KEY,label TEXT,book_name TEXT,modify_time TEXT)",
  "CREATE TABLE md_bookmark(bookmark_id INTEGER PRIMARY KEY,label TEXT,title TEXT,url TEXT,modify_time TEXT)",
  "INSERT INTO md_label VALUES(1,'Target'),(2,' Source '),(3,'Other')",
  "INSERT INTO md_books VALUES(10,' Source ,Other','Exact book','old-book-time')",
  "INSERT INTO md_bookmark VALUES(20,' Source ,Other','Exact bookmark','https://example.invalid/exact','old-bookmark-time')",
  "INSERT INTO md_label_relation VALUES(1,2,10,'book','t1'),(2,1,10,'book','t2'),(3,3,10,'book','t3'),(4,2,20,'bookmark','t4'),(5,3,20,'bookmark','t5')",
 } {if _,err=db.Exec(query);err!=nil{t.Fatal(err)}}
 return db
}
func labelMergeSnapshot(t *testing.T,db *sql.DB)map[string]string {
 t.Helper();out:=map[string]string{}
 for _,table:=range []string{"md_label","md_label_relation","md_books","md_bookmark"} {
  rows,err:=db.Query("SELECT * FROM "+table+" ORDER BY 1");if err!=nil{t.Fatal(err)}
  cols,err:=rows.Columns();if err!=nil{rows.Close();t.Fatal(err)}
  all:=[][]interface{}{}
  for rows.Next(){
   values:=make([]interface{},len(cols));ptrs:=make([]interface{},len(cols))
   for i:=range values{ptrs[i]=&values[i]}
   if err=rows.Scan(ptrs...);err!=nil{rows.Close();t.Fatal(err)}
   all=append(all,values)
  }
  if err=rows.Err();err!=nil{rows.Close();t.Fatal(err)};rows.Close()
  raw,err:=json.Marshal(all);if err!=nil{t.Fatal(err)};out[table]=string(raw)
 }
 return out
}
func TestLabelMergeAtomicRelationsCachesAndUnrelatedMetadata(t *testing.T){
 db:=labelMergeFixture(t)
 if err:=MergeLabels(1,[]int64{2});err!=nil{t.Fatal(err)}
 var count int
 if err:=db.QueryRow("SELECT COUNT(*) FROM md_label WHERE label_id=2").Scan(&count);err!=nil||count!=0{t.Fatal("source retained",err)}
 if err:=db.QueryRow("SELECT COUNT(*) FROM md_label_relation WHERE label_id=1 AND resource_id=10 AND relation_type='book'").Scan(&count);err!=nil||count!=1{t.Fatal("duplicate target relation",err)}
 var label,title,modified,url string
 if err:=db.QueryRow("SELECT label,book_name,modify_time FROM md_books WHERE book_id=10").Scan(&label,&title,&modified);err!=nil||label!="Target,Other"||title!="Exact book"||modified!="old-book-time"{t.Fatal("book cache/metadata mismatch",err,label,title,modified)}
 if err:=db.QueryRow("SELECT label,title,url,modify_time FROM md_bookmark WHERE bookmark_id=20").Scan(&label,&title,&url,&modified);err!=nil||label!="Target,Other"||title!="Exact bookmark"||url!="https://example.invalid/exact"||modified!="old-bookmark-time"{t.Fatal("bookmark cache/metadata mismatch",err)}
 // Moved source relation preserves its original ID/time; no source bodies read.
 var relationID int64;var created string
 if err:=db.QueryRow("SELECT id,created_at FROM md_label_relation WHERE label_id=1 AND resource_id=20").Scan(&relationID,&created);err!=nil||relationID!=4||created!="t4"{t.Fatal("relation identity/time changed",err)}
}
func TestLabelMergeLateCacheFailureRollsBackEveryTable(t *testing.T){
 db:=labelMergeFixture(t)
 if _,err:=db.Exec("CREATE TRIGGER reject_merge_cache BEFORE UPDATE OF label ON md_bookmark BEGIN SELECT RAISE(ABORT,'synthetic cache failure'); END");err!=nil{t.Fatal(err)}
 before:=labelMergeSnapshot(t,db)
 if err:=MergeLabels(1,[]int64{2});err==nil{t.Fatal("cache failure reported success")}
 if after:=labelMergeSnapshot(t,db);!reflect.DeepEqual(before,after){t.Fatal("partial merge committed",before,after)}
}
func TestLabelMergeStaleIdentityAndMalformedReferencesNeverMutate(t *testing.T){
 for _,which:=range []string{"missing-target","missing-source","duplicate","self","missing-resource","unknown-kind"} {
  t.Run(which,func(t *testing.T){
   db:=labelMergeFixture(t);target:=int64(1);sources:=[]int64{2}
   switch which{
   case "missing-target":
    // Simulate target deleted after an earlier UI preflight read.
    if _,err:=db.Exec("DELETE FROM md_label WHERE label_id=1");err!=nil{t.Fatal(err)}
   case "missing-source":sources=[]int64{2,999}
   case "duplicate":sources=[]int64{2,2}
   case "self":sources=[]int64{1,2}
   case "missing-resource":
    if _,err:=db.Exec("DELETE FROM md_bookmark WHERE bookmark_id=20");err!=nil{t.Fatal(err)}
   case "unknown-kind":
    if _,err:=db.Exec("UPDATE md_label_relation SET relation_type='legacy-unknown' WHERE id=4");err!=nil{t.Fatal(err)}
   }
   before:=labelMergeSnapshot(t,db)
   if err:=MergeLabels(target,sources);err==nil{t.Fatal("invalid merge accepted")}
   if !reflect.DeepEqual(before,labelMergeSnapshot(t,db)){t.Fatal("rejected merge mutated data")}
  })
 }
}
func TestLabelMergeCompleteCacheDoesNotTruncateAtLegacyHundred(t *testing.T){
 db:=labelMergeFixture(t)
 tx,err:=db.Begin();if err!=nil{t.Fatal(err)}
 for id:=int64(4);id<110;id++{
  name:="label-"+string(rune(0x4e00+id))
  if _,err=tx.Exec("INSERT INTO md_label(label_id,label_name) VALUES(?,?)",id,name);err!=nil{tx.Rollback();t.Fatal(err)}
  if _,err=tx.Exec("INSERT INTO md_label_relation(label_id,resource_id,relation_type,created_at) VALUES(?,10,'book','untouched')",id);err!=nil{tx.Rollback();t.Fatal(err)}
 }
 if err=tx.Commit();err!=nil{t.Fatal(err)}
 if err=MergeLabels(1,[]int64{2});err!=nil{t.Fatal(err)}
 var actual string
 if err=db.QueryRow("SELECT label FROM md_books WHERE book_id=10").Scan(&actual);err!=nil{t.Fatal(err)}
 rows,err:=db.Query("SELECT l.label_name FROM md_label l JOIN md_label_relation r ON l.label_id=r.label_id WHERE r.resource_id=10 AND r.relation_type='book' ORDER BY l.label_id");if err!=nil{t.Fatal(err)}
 expected:=""
 for rows.Next(){var name string;if err=rows.Scan(&name);err!=nil{rows.Close();t.Fatal(err)};if expected!=""{expected+=","};expected+=name}
 if err=rows.Err();err!=nil{rows.Close();t.Fatal(err)};rows.Close()
 if actual!=expected{t.Fatal("complete cached labels were truncated")}
}
