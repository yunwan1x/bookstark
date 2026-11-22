package models
import (
 "database/sql"
 "encoding/json"
 "errors"
 "reflect"
 "strings"
 "sync"
 "testing"
)
func ownedBookmarkInput()OwnedBookmarkCreationInput{
 return OwnedBookmarkCreationInput{Title:" 真实标题 \ufeff",URL:"https://example.test/owned?x=1#fragment",
  Description:"\ufeffExact\r\n😀",Favicon:"https://example.test/actual-icon.png",
  Labels:[]string{"exact,tag"," spaced ","","\ufeff路径/😀"}}
}
func TestOwnedBookmarkAtomicFullReceiptAndDuplicateZeroMutation(t *testing.T){
 initAssetTestDB(t)
 input:=ownedBookmarkInput()
 saved,err:=CreateOwnedBookmarkAtomic(input,1);if err!=nil{t.Fatal(err)}
 if saved.BookmarkID<=0||saved.MemberID!=1||saved.Title!=input.Title||saved.Description!=input.Description||
  saved.URL!=input.URL||saved.Favicon!=input.Favicon||saved.NavVisible||saved.IsPinned||saved.IsPublic{t.Fatal("actual complete receipt differs")}
 got:=map[string]bool{};for _,name:=range saved.Labels{got[name]=true}
 for _,name:=range input.Labels{if !got[name]{t.Fatal("exact label missing",name)}}
 before,_:=json.Marshal(saved)
 changed:=input;changed.Title="must not overwrite";changed.Labels=[]string{"must-not-create-label"}
 if _,err=CreateOwnedBookmarkAtomic(changed,1);!errors.Is(err,ErrOwnedBookmarkDuplicate){t.Fatal("duplicate not rejected",err)}
 after,err:=ReadOwnedBookmarkCreation(saved.BookmarkID,1);if err!=nil{t.Fatal(err)}
 raw,_:=json.Marshal(after);if string(raw)!=string(before){t.Fatal("duplicate changed existing metadata/source")}
 var count int
 if err=DB.QueryRow("SELECT COUNT(*) FROM md_label WHERE label_name='must-not-create-label'").Scan(&count);err!=nil||count!=0{t.Fatal("duplicate mutated labels",err)}
 if _,err=ReadOwnedBookmarkCreation(saved.BookmarkID,2);!errors.Is(err,sql.ErrNoRows){t.Fatal("other owner readable",err)}
 checked,err:=CheckOwnedBookmarkCreationURL(input.URL,1)
 if err!=nil||checked==nil||checked.BookmarkID!=saved.BookmarkID{t.Fatal("read-only URL check failed",err)}
}
func TestOwnedBookmarkConcurrentUniqueCreatesExactlyOneWithoutUpsert(t *testing.T){
 initAssetTestDB(t)
 start:=make(chan struct{});type result struct{row *OwnedBookmarkCreationSnapshot;err error}
 results:=make(chan result,2);var wg sync.WaitGroup
 for i:=0;i<2;i++{wg.Add(1);go func(){defer wg.Done();<-start;r,e:=CreateOwnedBookmarkAtomic(ownedBookmarkInput(),1);results<-result{r,e}}()}
 close(start);wg.Wait();close(results)
 successes,duplicates:=0,0
 for r:=range results{
  if r.err==nil{successes++;if r.row.BookmarkID<=0{t.Fatal("fake ID")}}
  if errors.Is(r.err,ErrOwnedBookmarkDuplicate){duplicates++}else if r.err!=nil{t.Fatal(r.err)}
 }
 if successes!=1||duplicates!=1{t.Fatal("concurrent result",successes,duplicates)}
 var count int
 if err:=DB.QueryRow("SELECT COUNT(*) FROM md_bookmark WHERE member_id=1 AND url=?",ownedBookmarkInput().URL).Scan(&count);err!=nil||count!=1{t.Fatal("duplicate resource",count,err)}
}
func bookmarkCreationCounts(t *testing.T)[]int64{
 t.Helper();out:=[]int64{}
 for _,table:=range []string{"md_bookmark","md_label","md_label_relation"}{
  var n int64;if err:=DB.QueryRow("SELECT COUNT(*) FROM "+table).Scan(&n);err!=nil{t.Fatal(err)};out=append(out,n)
 }
 return out
}
func TestOwnedBookmarkLabelFailureRollsBackEntireInsertAndLabelTree(t *testing.T){
 initAssetTestDB(t);before:=bookmarkCreationCounts(t)
 if _,err:=DB.Exec(`CREATE TRIGGER fail_owned_label BEFORE INSERT ON md_label
  WHEN NEW.label_name='reject-this-name' BEGIN SELECT RAISE(ABORT,'owned fixture label failure');END`);err!=nil{t.Fatal(err)}
 in:=ownedBookmarkInput();in.Labels=[]string{"must-rollback-first","reject-this-name"}
 if _,err:=CreateOwnedBookmarkAtomic(in,1);err==nil{t.Fatal("trigger failure accepted")}
 if !reflect.DeepEqual(before,bookmarkCreationCounts(t)){t.Fatal("partial resource or label mutation")}
 var count int
 if err:=DB.QueryRow("SELECT COUNT(*) FROM md_label WHERE label_name='must-rollback-first'").Scan(&count);err!=nil||count!=0{t.Fatal("partial label retained",err)}
}
func TestOwnedBookmarkBudgetAndReadOnlyNeverTurnsInvalidIntoEmpty(t *testing.T){
 initAssetTestDB(t)
 in:=ownedBookmarkInput();saved,err:=CreateOwnedBookmarkAtomic(in,1);if err!=nil{t.Fatal(err)}
 oversized:=strings.Repeat("x",501)
 if _,err=DB.Exec("UPDATE md_bookmark SET title=? WHERE bookmark_id=?",oversized,saved.BookmarkID);err!=nil{t.Fatal(err)}
 if _,err=ReadOwnedBookmarkCreation(saved.BookmarkID,1);!errors.Is(err,ErrOwnedBookmarkReadBound){t.Fatal("oversize was not typed refusal",err)}
 if _,err=CheckOwnedBookmarkCreationURL(in.URL,1);!errors.Is(err,ErrOwnedBookmarkReadBound){t.Fatal("oversize URL check became absent",err)}
 var actual string;if err=DB.QueryRow("SELECT title FROM md_bookmark WHERE bookmark_id=?",saved.BookmarkID).Scan(&actual);err!=nil||actual!=oversized{t.Fatal("read mutated original bytes",err)}
 in=ownedBookmarkInput();in.URL="https://other.test/";in.Title=string([]byte{0xff})
 before:=bookmarkCreationCounts(t)
 if _,err=CreateOwnedBookmarkAtomic(in,1);!errors.Is(err,ErrOwnedBookmarkInput){t.Fatal("invalid UTF8 accepted",err)}
 if !reflect.DeepEqual(before,bookmarkCreationCounts(t)){t.Fatal("invalid input mutated")}
}
func TestOwnedBookmarkPhysicalDeleteTrashIsNotNewCreationReceipt(t *testing.T){
 initAssetTestDB(t);in:=ownedBookmarkInput()
 old,err:=CreateOwnedBookmarkAtomic(in,1);if err!=nil{t.Fatal(err)}
 if err=DeleteBookmark(old.BookmarkID);err!=nil{t.Fatal(err)}
 if _,err=ReadOwnedBookmarkCreation(old.BookmarkID,1);!errors.Is(err,sql.ErrNoRows){t.Fatal("deleted ID became active proof",err)}
 // Go has no deleted column: trash keeps a snapshot, source row is removed.
 rows,err:=DB.Query("SELECT trash_id,snapshot FROM md_trash WHERE member_id=1 AND resource_type='bookmark'")
 if err!=nil{t.Fatal(err)}
 before:=map[int64]string{}
 for rows.Next(){var id int64;var raw string;if err=rows.Scan(&id,&raw);err!=nil{rows.Close();t.Fatal(err)};before[id]=raw}
 err=rows.Err();rows.Close();if err!=nil||len(before)==0{t.Fatal("trash snapshot missing",err)}
 checked,err:=CheckOwnedBookmarkCreationURL(in.URL,1);if err!=nil||checked!=nil{t.Fatal("trash treated as active create receipt",err)}
 fresh,err:=CreateOwnedBookmarkAtomic(in,1);if err!=nil{t.Fatal(err)}
 if fresh.BookmarkID==old.BookmarkID{t.Fatal("silently revived prior deleted ID")}
 for id,want:=range before{
  var got string;if err=DB.QueryRow("SELECT snapshot FROM md_trash WHERE trash_id=?",id).Scan(&got);err!=nil||got!=want{t.Fatal("explicit new create changed old trash bytes",err)}
 }
}
