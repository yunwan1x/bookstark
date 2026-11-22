package models
import (
 "context"
 "encoding/json"
 "errors"
 "strings"
 "testing"
 "golang.org/x/crypto/bcrypt"
)
func protectedOwnedFixture(t *testing.T)(OwnedComplexIdentity,string,string){
 ownedComplexFixture(t)
 password:="owned-fixture-only"
 hash,err:=bcrypt.GenerateFromPassword([]byte(password),bcrypt.MinCost);if err!=nil{t.Fatal(err)}
 encrypted,err:=EncryptContent(password,"[]");if err!=nil{t.Fatal(err)}
 result,err:=DB.Exec("UPDATE md_blogs SET editor_type='drawing',password=?,blog_content=? WHERE blog_id=1",string(hash),encrypted)
 if err!=nil{t.Fatal(err)};if n,_:=result.RowsAffected();n!=1{t.Fatal("fixture row")}
 return OwnedComplexIdentity{Resource:"remote-note",ID:1,MemberID:7,Kind:"drawing"},password,string(hash)
}
func TestProtectedOwnedBodyCASPreservesPasswordAndMetadata(t *testing.T){
 key,password,hash:=protectedOwnedFixture(t);ctx:=context.Background()
 if _,err:=ReadOwnedComplexSource(ctx,key);!errors.Is(err,ErrOwnedComplexLocked){t.Fatal("ordinary path unlocked")}
 if _,err:=ReadProtectedOwnedComplexSource(ctx,key,"wrong");!errors.Is(err,ErrOwnedProtectedCredential){t.Fatal("wrong password accepted")}
 before,err:=ReadProtectedOwnedComplexSource(ctx,key,password);if err!=nil{t.Fatal(err)}
 noOp,err:=SaveProtectedOwnedComplexSource(ctx,key,password,before.Fingerprint,before.plain)
 if err!=nil||noOp.stored!=before.stored||noOp.Fingerprint!=before.Fingerprint{t.Fatal("noop changed cipher")}
 source:="{\"elements\":[]}\r\n"
 saved,err:=SaveProtectedOwnedComplexSource(ctx,key,password,before.Fingerprint,source);if err!=nil{t.Fatal(err)}
 if saved.plain!=source||!IsEncrypted(saved.stored)||saved.passwordHash!=hash{t.Fatal("protected source/hash changed")}
 for _,field:=range []string{"blog_title","blog_desc","visibility","is_pinned","extra","create_time"}{
  if saved.metadata[field]!=before.metadata[field]{t.Fatalf("metadata overwritten %s",field)}
 }
 raw,err:=json.Marshal(saved);if err!=nil{t.Fatal(err)}
 if strings.Contains(string(raw),password)||strings.Contains(string(raw),hash){t.Fatal("credential/hash leaked in DTO")}
}
func TestProtectedOwnedFingerprintBindsHashCipherAndRollback(t *testing.T){
 key,password,_:=protectedOwnedFixture(t);ctx:=context.Background()
 before,err:=ReadProtectedOwnedComplexSource(ctx,key,password);if err!=nil{t.Fatal(err)}
 replacement,err:=bcrypt.GenerateFromPassword([]byte(password),bcrypt.MinCost);if err!=nil{t.Fatal(err)}
 if _,err=DB.Exec("UPDATE md_blogs SET password=? WHERE blog_id=1",string(replacement));err!=nil{t.Fatal(err)}
 if _,err=SaveProtectedOwnedComplexSource(ctx,key,password,before.Fingerprint,"{\"elements\":[]}");!errors.Is(err,ErrOwnedComplexConflict){t.Fatal("password hash rotation not conflict")}
 fresh,err:=ReadProtectedOwnedComplexSource(ctx,key,password);if err!=nil{t.Fatal(err)}
 if _,err=DB.Exec("CREATE TRIGGER protected_abort BEFORE UPDATE ON md_blogs BEGIN SELECT RAISE(ABORT,'fixture'); END");err!=nil{t.Fatal(err)}
 if _,err=SaveProtectedOwnedComplexSource(ctx,key,password,fresh.Fingerprint,"{\"elements\":[]}");err==nil{t.Fatal("trigger should fail")}
 after,err:=ReadProtectedOwnedComplexSource(ctx,key,password);if err!=nil{t.Fatal(err)}
 if after.Fingerprint!=fresh.Fingerprint||after.stored!=fresh.stored{t.Fatal("failed transaction partially saved")}
}

func TestProtectedOwnedInvalidJSONBOMRetainsOriginal(t *testing.T){
 key,password,_:=protectedOwnedFixture(t);ctx:=context.Background()
 before,err:=ReadProtectedOwnedComplexSource(ctx,key,password);if err!=nil{t.Fatal(err)}
 // Drawing uses strict JSON in both Go and Dart String decoders. A leading
 // Unicode BOM is not a valid drawing envelope; do not silently strip bytes.
 invalid:="\uFEFF{\"elements\":[]}\r\n"
 if _,err=SaveProtectedOwnedComplexSource(ctx,key,password,before.Fingerprint,invalid);err==nil{
  t.Fatal("invalid BOM JSON accepted")
 }
 after,err:=ReadProtectedOwnedComplexSource(ctx,key,password);if err!=nil{t.Fatal(err)}
 if after.Fingerprint!=before.Fingerprint||after.stored!=before.stored||
   after.passwordHash!=before.passwordHash||after.plain!=before.plain{
  t.Fatal("rejected JSON changed the original tuple")
 }
}
