package models
import (
 "context"
 "encoding/json"
 "errors"
 "strings"
 "testing"
)
func TestProtectedRecoveryReadsSameFiveKindTupleWithoutWrite(t *testing.T){
 key,password,_:=protectedOwnedFixture(t);ctx:=context.Background()
 saved,err:=ReadProtectedOwnedComplexSource(ctx,key,password);if err!=nil{t.Fatal(err)}
 actual,err:=ReadOwnedProtectedRecoverySource(ctx,key.MemberID,key.ID,password);if err!=nil{t.Fatal(err)}
 if actual.Fingerprint!=saved.Fingerprint||actual.plain!=saved.plain||!actual.Protected{t.Fatal("different actual tuple")}
 if _,err=ReadOwnedProtectedRecoverySource(ctx,8,key.ID,password);err==nil{t.Fatal("different owner read")}
}
func TestProtectedRecoveryMarkdownHTMLRetargetIsReadonly(t *testing.T){
 for _,kind:=range []string{"markdown","html"}{
  t.Run(kind,func(t *testing.T){
   key,password,hash:=protectedOwnedFixture(t);ctx:=context.Background()
   before,err:=ReadProtectedOwnedComplexSource(ctx,key,password);if err!=nil{t.Fatal(err)}
   source:="\ufeff# current server only\r\n"
   if kind=="html"{source="\ufeff<p>current server only</p>\r\n"}
   encoded:=source
   if kind=="html"{encoded,err=ownedEncode(kind,source);if err!=nil{t.Fatal(err)}}
   encrypted,err:=EncryptContent(password,encoded);if err!=nil{t.Fatal(err)}
   result,err:=DB.Exec("UPDATE md_blogs SET editor_type=?,blog_type='article',blog_content=? WHERE blog_id=?",kind,encrypted,key.ID)
   if err!=nil{t.Fatal(err)};if n,_:=result.RowsAffected();n!=1{t.Fatal("fixture update")}
   actual,err:=ReadOwnedProtectedRecoverySource(ctx,key.MemberID,key.ID,password);if err!=nil{t.Fatal(err)}
   if actual.Kind!=kind||actual.BlogType!="article"||actual.plain!=source||
     actual.Fingerprint==before.Fingerprint{t.Fatal("retarget not actual source")}
   bytes,err:=json.Marshal(actual);if err!=nil{t.Fatal(err)}
   if strings.Contains(string(bytes),hash)||strings.Contains(string(bytes),password){t.Fatal("secret DTO")}
   // This endpoint's expanded read scope never grants Markdown/HTML writes.
   changed:=key;changed.Kind=kind
   if _,err=SaveProtectedOwnedComplexSource(ctx,changed,password,actual.Fingerprint,source+"x");
     !errors.Is(err,ErrOwnedComplexDenied){t.Fatal("expanded write scope")}
   var after,afterHash string
   if err=DB.QueryRow("SELECT blog_content,password FROM md_blogs WHERE blog_id=?",key.ID).Scan(&after,&afterHash);err!=nil{t.Fatal(err)}
   if after!=encrypted||afterHash!=hash{t.Fatal("read or rejected write changed row")}
   if _,err=ReadOwnedProtectedRecoverySource(ctx,key.MemberID,key.ID,"wrong");!errors.Is(err,ErrOwnedProtectedCredential){t.Fatal("wrong password")}
  })
 }
}
func TestProtectedRecoveryRemovedProtectionHasFreshTuple(t *testing.T){
 key,password,_:=protectedOwnedFixture(t);ctx:=context.Background()
 before,err:=ReadOwnedProtectedRecoverySource(ctx,key.MemberID,key.ID,password);if err!=nil{t.Fatal(err)}
 result,err:=DB.Exec("UPDATE md_blogs SET editor_type='markdown',password='',blog_content=? WHERE blog_id=?","\ufeff# now plain\r\n",key.ID)
 if err!=nil{t.Fatal(err)};if n,_:=result.RowsAffected();n!=1{t.Fatal("fixture update")}
 after,err:=ReadOwnedProtectedRecoverySource(ctx,key.MemberID,key.ID,"");if err!=nil{t.Fatal(err)}
 if after.Protected||after.Fingerprint==before.Fingerprint||after.plain!="\ufeff# now plain\r\n"{t.Fatal("old protected state inferred")}
}
