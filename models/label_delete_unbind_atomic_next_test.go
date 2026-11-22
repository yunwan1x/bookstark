package models

import (
 "database/sql"
 "encoding/json"
 "errors"
 "reflect"
 "testing"
)

func labelMutationFixture(t *testing.T)*sql.DB{
 t.Helper();db:=labelMergeFixture(t)
 for _,q:=range []string{
  "CREATE TABLE md_members(member_id INTEGER PRIMARY KEY,role INTEGER,status INTEGER)",
  "INSERT INTO md_members VALUES(1,0,1),(2,1,1),(3,1,1)",
  "ALTER TABLE md_books ADD COLUMN member_id INTEGER NOT NULL DEFAULT 2",
  "ALTER TABLE md_bookmark ADD COLUMN member_id INTEGER NOT NULL DEFAULT 2",
 }{if _,err:=db.Exec(q);err!=nil{t.Fatal(err)}}
 return db
}
func labelMutationSnapshot(t *testing.T,db *sql.DB)map[string]string{
 t.Helper();out:=labelMergeSnapshot(t,db)
 rows,err:=db.Query("SELECT member_id,role,status FROM md_members ORDER BY member_id");if err!=nil{t.Fatal(err)}
 var all [][3]int64
 for rows.Next(){var r [3]int64;if err=rows.Scan(&r[0],&r[1],&r[2]);err!=nil{rows.Close();t.Fatal(err)};all=append(all,r)}
 if err=rows.Err();err!=nil{rows.Close();t.Fatal(err)};rows.Close()
 raw,err:=json.Marshal(all);if err!=nil{t.Fatal(err)};out["md_members"]=string(raw);return out
}
func TestLabelDeleteLateCacheFailureRollsBackEntireDatabase(t *testing.T){
 db:=labelMutationFixture(t)
 if _,err:=db.Exec("CREATE TRIGGER reject_deleted_cache BEFORE UPDATE OF label ON md_bookmark BEGIN SELECT RAISE(ABORT,'late cached field failure'); END");err!=nil{t.Fatal(err)}
 before:=labelMutationSnapshot(t,db)
 if err:=DeleteLabelOwned(2,1);err==nil{t.Fatal("late cache failure acknowledged")}
 if !reflect.DeepEqual(before,labelMutationSnapshot(t,db)){t.Fatal("label deletion partially committed")}
}
func TestLabelDeleteSuccessPreservesUnrelatedMetadataAndFreshAdminRequired(t *testing.T){
 db:=labelMutationFixture(t)
 before:=labelMutationSnapshot(t,db)
 // Role changed after the HTTP/JWT preflight; database role is authoritative.
 if err:=DeleteLabelOwned(2,2);!errors.Is(err,ErrLabelMutationForbidden){t.Fatal("ordinary member deleted global label",err)}
 if !reflect.DeepEqual(before,labelMutationSnapshot(t,db)){t.Fatal("denied delete mutated DB")}
 if err:=DeleteLabelOwned(2,1);err!=nil{t.Fatal(err)}
 var count int
 if err:=db.QueryRow("SELECT COUNT(*) FROM md_label WHERE label_id=2").Scan(&count);err!=nil||count!=0{t.Fatal("label retained",err)}
 var cache,title,modified string
 if err:=db.QueryRow("SELECT label,book_name,modify_time FROM md_books WHERE book_id=10").Scan(&cache,&title,&modified);err!=nil||cache!="Target,Other"||title!="Exact book"||modified!="old-book-time"{t.Fatal("book cache/metadata changed",err)}
 if err:=db.QueryRow("SELECT label,title,modify_time FROM md_bookmark WHERE bookmark_id=20").Scan(&cache,&title,&modified);err!=nil||cache!="Other"||title!="Exact bookmark"||modified!="old-bookmark-time"{t.Fatal("bookmark cache/metadata changed",err)}
}
func TestLabelUnbindLateSecondResourceFailureRollsBackRelationsCachesAndTimes(t *testing.T){
 db:=labelMutationFixture(t)
 for _,q:=range []string{
  "INSERT INTO md_bookmark VALUES(21,' Source ,Other','Second','https://second.invalid','old-second',2)",
  "INSERT INTO md_label_relation VALUES(6,2,21,'bookmark','t6'),(7,3,21,'bookmark','t7')",
  "CREATE TRIGGER reject_second_cache BEFORE UPDATE OF label ON md_bookmark WHEN NEW.bookmark_id=21 BEGIN SELECT RAISE(ABORT,'second cached field failure'); END",
 }{if _,err:=db.Exec(q);err!=nil{t.Fatal(err)}}
 before:=labelMutationSnapshot(t,db)
 if err:=UnbindLabelsOwned(2,[]int64{20,21},"bookmark",2);err==nil{t.Fatal("partial batch acknowledged")}
 if !reflect.DeepEqual(before,labelMutationSnapshot(t,db)){t.Fatal("partial unbind/cache/time committed")}
}
func TestLabelUnbindFreshOwnershipAndIdentityDenialsAreZeroMutation(t *testing.T){
 for _,which:=range []string{"changed-owner","disabled-actor","missing-actor","missing-label","missing-resource","duplicate-ID"}{
  t.Run(which,func(t *testing.T){
   db:=labelMutationFixture(t);actor,label:=int64(2),int64(2);ids:=[]int64{20}
   switch which{
   case "changed-owner":
    if _,err:=db.Exec("UPDATE md_bookmark SET member_id=3 WHERE bookmark_id=20");err!=nil{t.Fatal(err)}
   case "disabled-actor":
    if _,err:=db.Exec("UPDATE md_members SET status=0 WHERE member_id=2");err!=nil{t.Fatal(err)}
   case "missing-actor":actor=99
   case "missing-label":label=99
   case "missing-resource":ids=[]int64{20,999}
   case "duplicate-ID":ids=[]int64{20,20}
   }
   before:=labelMutationSnapshot(t,db)
   if err:=UnbindLabelsOwned(label,ids,"bookmark",actor);err==nil{t.Fatal("stale authority/identity accepted")}
   if !reflect.DeepEqual(before,labelMutationSnapshot(t,db)){t.Fatal("rejected unbind mutated database")}
  })
 }
}
func TestLabelUnbindSuccessTouchesOnlyActualRemovalAndFreshAdminMayAct(t *testing.T){
 db:=labelMutationFixture(t)
 if err:=UnbindLabelsOwned(2,[]int64{20},"bookmark",1);err!=nil{t.Fatal(err)}
 var cache,title,url,modified string
 if err:=db.QueryRow("SELECT label,title,url,modify_time FROM md_bookmark WHERE bookmark_id=20").Scan(&cache,&title,&url,&modified);err!=nil||cache!="Other"||title!="Exact bookmark"||url!="https://example.invalid/exact"||modified=="old-bookmark-time"{t.Fatal("actual unbind receipt wrong",err)}
 before:=labelMutationSnapshot(t,db)
 if err:=UnbindLabelsOwned(2,[]int64{20},"bookmark",1);err!=nil{t.Fatal(err)}
 if !reflect.DeepEqual(before,labelMutationSnapshot(t,db)){t.Fatal("already-unbound replay changed timestamp/data")}
}
