package models

// PREPARED ONLY. Not gofmt, compiled or executed.
import (
 "context"
 "database/sql"
 "encoding/base64"
 "errors"
 "path/filepath"
 "sync"
 "testing"
)
func ownedComplexFixture(t *testing.T){
 t.Helper()
 previous:=DB
 db,err:=sql.Open("sqlite",filepath.Join(t.TempDir(),"owned-complex.db"));if err!=nil{t.Fatal(err)}
 DB=db;DB.SetMaxOpenConns(2)
 t.Cleanup(func(){_ = db.Close();DB=previous})
 schema:=[]string{
  "PRAGMA journal_mode=WAL",
  "CREATE TABLE md_books(book_id INTEGER PRIMARY KEY,member_id INTEGER,identify TEXT)",
  "CREATE TABLE md_documents(document_id INTEGER PRIMARY KEY,book_id INTEGER,member_id INTEGER,doc_type TEXT,document_name TEXT,identify TEXT,parent_id INTEGER,order_sort INTEGER,markdown TEXT,create_time DATETIME,modify_time DATETIME,modify_at INTEGER,extra TEXT)",
  "CREATE TABLE md_blogs(blog_id INTEGER PRIMARY KEY,member_id INTEGER,blog_type TEXT,editor_type TEXT,blog_title TEXT,blog_identify TEXT,blog_content TEXT,blog_desc TEXT,password TEXT,version INTEGER,create_time DATETIME,modify_time DATETIME,modify_at INTEGER,visibility INTEGER,is_pinned INTEGER,extra TEXT)",
  "CREATE TABLE md_label(label_id INTEGER PRIMARY KEY,label_name TEXT UNIQUE)",
  "CREATE TABLE md_label_relation(id INTEGER PRIMARY KEY,label_id INTEGER,resource_id INTEGER,relation_type TEXT)",
  "INSERT INTO md_books VALUES(10,7,'real-book'),(11,8,'other-book')",
  "INSERT INTO md_documents VALUES(1,10,7,'html','chapter','chapter-1',0,3,'<p>original</p>','2020-01-01','2020-01-01',7,' retain doc ')",
  "INSERT INTO md_blogs VALUES(1,7,'note','html','note','note-1','<p>original</p>','exact old description','',2,'2020-01-01','2020-01-01',7,0,1,' retain note ')",
  "INSERT INTO md_label VALUES(1,'first'),(2,'legacy,value')",
  "INSERT INTO md_label_relation VALUES(1,1,1,'blog'),(2,2,1,'blog'),(3,2,1,'document')",
 }
 for _,query:=range schema{if _,err:=DB.Exec(query);err!=nil{t.Fatal(err)}}
}
func ownedKey(note bool)OwnedComplexIdentity{
 if note{return OwnedComplexIdentity{Resource:"remote-note",ID:1,MemberID:7,Kind:"html"}}
 return OwnedComplexIdentity{Resource:"remote-book-document",ID:1,BookID:10,MemberID:7,Kind:"html"}
}
func TestOwnedComplexBodyOnlyExactAndNoop(t *testing.T){
 ownedComplexFixture(t);ctx:=context.Background()
 for _,note:=range []bool{true,false}{
  key:=ownedKey(note);before,err:=ReadOwnedComplexSource(ctx,key);if err!=nil{t.Fatal(err)}
  same,err:=SaveOwnedComplexSource(ctx,key,before.Fingerprint,before.plain);if err!=nil{t.Fatal(err)}
  if same.Fingerprint!=before.Fingerprint || same.stored!=before.stored{t.Fatal("noop mutated wire or metadata")}
  source:="\uFEFF\uFEFF<p>changed 😀</p>\r\n"
  saved,err:=SaveOwnedComplexSource(ctx,key,before.Fingerprint,source);if err!=nil{t.Fatal(err)}
  bytes,err:=base64.StdEncoding.DecodeString(saved.Source);if err!=nil || string(bytes)!=source || saved.SHA256!=ownedComplexDigest(bytes){t.Fatal("source changed")}
  if saved.Title!=before.Title || saved.metadata["extra"]!=before.metadata["extra"] || saved.metadata["identify"]!=before.metadata["identify"]{t.Fatal("metadata overwritten")}
  if len(saved.Labels)!=len(before.Labels){t.Fatal("labels changed")}
  if saved.Fingerprint==before.Fingerprint{t.Fatal("fingerprint did not advance")}
  if note{
   var description,extra string;var version int
   if err:=DB.QueryRow("SELECT blog_desc,extra,version FROM md_blogs WHERE blog_id=1").Scan(&description,&extra,&version);err!=nil{t.Fatal(err)}
   if description!="exact old description" || extra!=" retain note " || version!=3{t.Fatal("note metadata/version")}
  }else if saved.metadata["parent_id"]!=before.metadata["parent_id"] || saved.metadata["order_sort"]!=before.metadata["order_sort"]{t.Fatal("document layout overwritten")}
 }
}
func TestOwnedComplexStaleMetadataAndLabelsAreCASConflicts(t *testing.T){
 for _,mutation:=range []string{
  "UPDATE md_blogs SET blog_title='external rename' WHERE blog_id=1",
  "UPDATE md_blogs SET extra='future metadata change' WHERE blog_id=1",
  "UPDATE md_label SET label_name='external label' WHERE label_id=1",
 }{
  t.Run(mutation,func(t *testing.T){
   ownedComplexFixture(t);key:=ownedKey(true);before,err:=ReadOwnedComplexSource(context.Background(),key);if err!=nil{t.Fatal(err)}
   if _,err:=DB.Exec(mutation);err!=nil{t.Fatal(err)}
   _,err=SaveOwnedComplexSource(context.Background(),key,before.Fingerprint,"<p>must not write</p>")
   if !errors.Is(err,ErrOwnedComplexConflict){t.Fatalf("expected conflict, got %v",err)}
   var body string;var version int
   if err:=DB.QueryRow("SELECT blog_content,version FROM md_blogs WHERE blog_id=1").Scan(&body,&version);err!=nil{t.Fatal(err)}
   if body!="<p>original</p>" || version!=2{t.Fatal("conflict mutated body")}
  })
 }
}
func TestOwnedComplexChapterOwnershipTypeDeletionAndParentGuard(t *testing.T){
 ownedComplexFixture(t);ctx:=context.Background();key:=ownedKey(false)
 baseline,err:=ReadOwnedComplexSource(ctx,key);if err!=nil{t.Fatal(err)}
 for _,bad:=range []OwnedComplexIdentity{
  {Resource:key.Resource,ID:1,BookID:11,MemberID:7,Kind:"html"},
  {Resource:key.Resource,ID:1,BookID:10,MemberID:8,Kind:"html"},
  {Resource:key.Resource,ID:1,BookID:10,MemberID:7,Kind:"drawing"},
  {Resource:key.Resource,ID:999,BookID:10,MemberID:7,Kind:"html"},
 }{if _,err:=SaveOwnedComplexSource(ctx,bad,baseline.Fingerprint,"<p>bad</p>");err==nil{t.Fatal("bad identity accepted")}}
 if _,err:=DB.Exec("UPDATE md_documents SET document_name='renamed',parent_id=42,order_sort=99 WHERE document_id=1");err!=nil{t.Fatal(err)}
 if _,err:=SaveOwnedComplexSource(ctx,key,baseline.Fingerprint,"<p>stale</p>");!errors.Is(err,ErrOwnedComplexConflict){t.Fatal("metadata drift not rejected")}
 current,err:=ReadOwnedComplexSource(ctx,key);if err!=nil{t.Fatal(err)}
 saved,err:=SaveOwnedComplexSource(ctx,key,current.Fingerprint,"<p>fresh body</p>");if err!=nil{t.Fatal(err)}
 if saved.Title!="renamed" || saved.metadata["parent_id"]!=int64(42) || saved.metadata["order_sort"]!=int64(99){t.Fatal("fresh metadata reverted")}
 if _,err:=DB.Exec("DELETE FROM md_documents WHERE document_id=1");err!=nil{t.Fatal(err)}
 if _,err:=SaveOwnedComplexSource(ctx,key,saved.Fingerprint,"<p>resurrection</p>");err==nil{t.Fatal("deleted document recreated")}
}
func TestOwnedComplexProtectedMalformedAndBudgetFailClosed(t *testing.T){
 for _,stored:=range []string{"ENC:v1:opaque","\uFEFFENC:v9:opaque","CMP:v9:unknown"}{
  t.Run(stored,func(t *testing.T){ownedComplexFixture(t)
   if _,err:=DB.Exec("UPDATE md_blogs SET blog_content=? WHERE blog_id=1",stored);err!=nil{t.Fatal(err)}
   if _,err:=ReadOwnedComplexSource(context.Background(),ownedKey(true));err==nil{t.Fatal("protected/unknown format exposed")}
   var actual string;if err:=DB.QueryRow("SELECT blog_content FROM md_blogs WHERE blog_id=1").Scan(&actual);err!=nil{t.Fatal(err)}
   if actual!=stored{t.Fatal("stored bytes changed")}
  })
 }
 ownedComplexFixture(t)
 before,err:=ReadOwnedComplexSource(context.Background(),ownedKey(true));if err!=nil{t.Fatal(err)}
 if _,err:=DB.Exec("UPDATE md_blogs SET password='protected-marker' WHERE blog_id=1");err!=nil{t.Fatal(err)}
 if _,err:=SaveOwnedComplexSource(context.Background(),ownedKey(true),before.Fingerprint,"<p>overwrite</p>");!errors.Is(err,ErrOwnedComplexLocked){t.Fatal("new protection overwritten")}
 if err:=validateOwnedComplexSource("drawing",`{"elements":[],"x":"\ud800"}`);err==nil{t.Fatal("malformed surrogate accepted")}
 if err:=validateOwnedComplexSource("markdown","# not this route");err==nil{t.Fatal("Markdown accepted")}
}
func TestOwnedComplexConcurrentSameBaselineCommitsAtMostOnce(t *testing.T){
 ownedComplexFixture(t);key:=ownedKey(true);before,err:=ReadOwnedComplexSource(context.Background(),key);if err!=nil{t.Fatal(err)}
 start:=make(chan struct{});results:=make(chan error,2);var group sync.WaitGroup
 for _,body:=range []string{"<p>one</p>","<p>two</p>"}{group.Add(1);go func(source string){defer group.Done();<-start;_,err:=SaveOwnedComplexSource(context.Background(),key,before.Fingerprint,source);results<-err}(body)}
 close(start);group.Wait();close(results);success:=0;for err:=range results{if err==nil{success++}}
 if success!=1{t.Fatalf("expected one commit, got %d",success)}
 var version int;if err:=DB.QueryRow("SELECT version FROM md_blogs WHERE blog_id=1").Scan(&version);err!=nil{t.Fatal(err)}
 if version!=3{t.Fatal("replayed source update")}
}

func TestOwnedComplexNoteMetadataAndBodyCommitTogether(t *testing.T){
 ownedComplexFixture(t);ctx:=context.Background();key:=ownedKey(true)
 before,err:=ReadOwnedComplexSource(ctx,key);if err!=nil{t.Fatal(err)}
 labels:=[]string{"exact new","legacy,value"," 指南 "}
 saved,err:=SaveOwnedComplexEdit(ctx,key,before.Fingerprint,"<p>new body</p>",&OwnedComplexMetadata{Title:"new title",Labels:labels});if err!=nil{t.Fatal(err)}
 if saved.Title!="new title" || !sameOwnedLabels(saved.Labels,labels) || saved.plain!="<p>new body</p>"{t.Fatal("combined edit did not match")}
 var description,extra string;var pinned,visibility int
 if err:=DB.QueryRow("SELECT blog_desc,extra,is_pinned,visibility FROM md_blogs WHERE blog_id=1").Scan(&description,&extra,&pinned,&visibility);err!=nil{t.Fatal(err)}
 if description!="exact old description" || extra!=" retain note " || pinned!=1 || visibility!=0{t.Fatal("unrequested metadata changed")}
 var documentRelation int
 if err:=DB.QueryRow("SELECT COUNT(*) FROM md_label_relation WHERE id=3 AND relation_type='document' AND label_id=2").Scan(&documentRelation);err!=nil || documentRelation!=1{t.Fatal("other resource labels changed")}
 // Metadata-only edit must preserve the exact compressed stored source bytes.
 changed,err:=SaveOwnedComplexEdit(ctx,key,saved.Fingerprint,saved.plain,&OwnedComplexMetadata{Title:"metadata only",Labels:labels});if err!=nil{t.Fatal(err)}
 if changed.stored!=saved.stored{t.Fatal("metadata edit rewrote body wire")}
}
func TestOwnedComplexMetadataFailureRollsBackWholeEditAndBookRejectsIt(t *testing.T){
 ownedComplexFixture(t);ctx:=context.Background();key:=ownedKey(true)
 before,err:=ReadOwnedComplexSource(ctx,key);if err!=nil{t.Fatal(err)}
 if _,err:=DB.Exec("CREATE TRIGGER reject_owned_label BEFORE INSERT ON md_label WHEN NEW.label_name='reject' BEGIN SELECT RAISE(ABORT,'reject'); END");err!=nil{t.Fatal(err)}
 _,err=SaveOwnedComplexEdit(ctx,key,before.Fingerprint,"<p>must rollback</p>",&OwnedComplexMetadata{Title:"must rollback",Labels:[]string{"new first","reject"}})
 if err==nil{t.Fatal("expected label failure")}
 after,err:=ReadOwnedComplexSource(ctx,key);if err!=nil{t.Fatal(err)}
 if after.Fingerprint!=before.Fingerprint || after.stored!=before.stored{t.Fatal("partial body/title/label change survived")}
 var count int
 if err:=DB.QueryRow("SELECT COUNT(*) FROM md_label WHERE label_name='new first'").Scan(&count);err!=nil || count!=0{t.Fatal("partial label survived")}
 book:=ownedKey(false);chapter,err:=ReadOwnedComplexSource(ctx,book);if err!=nil{t.Fatal(err)}
 if _,err:=SaveOwnedComplexEdit(ctx,book,chapter.Fingerprint,"<p>bad</p>",&OwnedComplexMetadata{Title:"rename chapter",Labels:[]string{}});!errors.Is(err,ErrOwnedComplexFormat){t.Fatal("book metadata accepted")}
 same,err:=ReadOwnedComplexSource(ctx,book);if err!=nil || same.Fingerprint!=chapter.Fingerprint{t.Fatal("book changed on rejected metadata")}
}
