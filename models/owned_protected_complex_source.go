package models

import (
 "context"
 "database/sql"
 "encoding/base64"
 "encoding/json"
 "errors"
 "regexp"
 "time"
 "unicode/utf8"
 "golang.org/x/crypto/bcrypt"
)
var ErrOwnedProtectedCredential=errors.New("protected credential rejected")
type ProtectedOwnedComplexSnapshot struct {
 *OwnedComplexSnapshot
 Protected bool `json:"protected"`
 passwordHash string
}
func protectedOwnedKey(key OwnedComplexIdentity) bool {
 return key.Resource=="remote-note" && key.ID>0 && key.MemberID>0 && key.BookID==0 &&
  (key.Kind=="spreadsheet"||key.Kind=="drawing"||key.Kind=="mindmap"||key.Kind=="richdoc"||key.Kind=="presentation")
}
func readProtectedOwnedComplexTx(ctx context.Context,tx *sql.Tx,key OwnedComplexIdentity,password string)(*ProtectedOwnedComplexSnapshot,error){
 if !protectedOwnedKey(key)||password==""||len(password)>4096||!utf8.ValidString(password){return nil,ErrOwnedComplexDenied}
 var hash sql.NullString
 err:=tx.QueryRowContext(ctx,"SELECT CASE WHEN length(CAST(password AS BLOB))<=128 THEN password ELSE NULL END FROM md_blogs WHERE blog_id=? AND member_id=? AND blog_type='note' AND editor_type=?",key.ID,key.MemberID,key.Kind).Scan(&hash)
 if err!=nil{return nil,err}
 if !hash.Valid||hash.String==""{return nil,ErrOwnedComplexLocked}
 if bcrypt.CompareHashAndPassword([]byte(hash.String),[]byte(password))!=nil{return nil,ErrOwnedProtectedCredential}
 where:="blog_id=? AND member_id=? AND blog_type='note' AND editor_type=? AND password=?"
 metadata,stored,err:=ownedMetadata(ctx,tx,"md_blogs","blog_content",where,[]any{key.ID,key.MemberID,key.Kind,hash.String})
 if err!=nil{return nil,err}
 encoded:=stored
 if IsEncrypted(stored){
  encoded,err=DecryptContent(password,stored)
  if err!=nil{return nil,ErrOwnedComplexFormat}
 }
 plain,err:=ownedDecode(key.Kind,encoded);if err!=nil{return nil,err}
 labels,relations,err:=ownedLabels(ctx,tx,key.ID,"blog");if err!=nil{return nil,err}
 title,ok:=metadata["blog_title"].(string)
 if !ok||len(title)>65536{return nil,ErrOwnedComplexDenied}
 // bcrypt hash is used only inside this opaque fingerprint; never a DTO field.
 fp,err:=json.Marshal([]any{"owned-protected-complex-v1",key.Resource,key.ID,key.BookID,key.MemberID,key.Kind,
  true,hash.String,metadata,relations,ownedComplexDigest([]byte(stored)),ownedComplexDigest([]byte(plain))})
 if err!=nil{return nil,err}
 return &ProtectedOwnedComplexSnapshot{OwnedComplexSnapshot:&OwnedComplexSnapshot{
  Resource:key.Resource,ID:key.ID,BookID:0,MemberID:key.MemberID,Kind:key.Kind,Title:title,Labels:labels,
  Fingerprint:ownedComplexDigest(fp),Source:base64.StdEncoding.EncodeToString([]byte(plain)),
  Bytes:len(plain),SHA256:ownedComplexDigest([]byte(plain)),metadata:metadata,stored:stored,plain:plain},
  Protected:true,passwordHash:hash.String},nil
}
func ReadProtectedOwnedComplexSource(ctx context.Context,key OwnedComplexIdentity,password string)(*ProtectedOwnedComplexSnapshot,error){
 tx,err:=DB.BeginTx(ctx,nil);if err!=nil{return nil,err};defer tx.Rollback()
 actual,err:=readProtectedOwnedComplexTx(ctx,tx,key,password);if err!=nil{return nil,err}
 if err=tx.Commit();err!=nil{return nil,err};return actual,nil
}
func SaveProtectedOwnedComplexSource(ctx context.Context,key OwnedComplexIdentity,password,expected,source string)(*ProtectedOwnedComplexSnapshot,error){
 if !protectedOwnedKey(key)||!regexp.MustCompile("^[a-f0-9]{64}$").MatchString(expected){return nil,ErrOwnedComplexDenied}
 if err:=validateOwnedComplexSource(key.Kind,source);err!=nil{return nil,err}
 tx,err:=DB.BeginTx(ctx,nil);if err!=nil{return nil,err};defer tx.Rollback()
 actual,err:=readProtectedOwnedComplexTx(ctx,tx,key,password);if err!=nil{return nil,err}
 if actual.Fingerprint!=expected{return nil,ErrOwnedComplexConflict}
 if actual.plain!=source {
  encoded,err:=ownedEncode(key.Kind,source);if err!=nil{return nil,err}
  encrypted,err:=EncryptContent(password,encoded);if err!=nil{return nil,err}
  now:=time.Now().UTC()
  result,err:=tx.ExecContext(ctx,"UPDATE md_blogs SET blog_content=?,modify_time=?,modify_at=?,version=version+1 WHERE blog_id=? AND member_id=? AND blog_type='note' AND editor_type=? AND password=? AND COALESCE(CAST(blog_content AS BLOB),X'')=?",encrypted,now,key.MemberID,key.ID,key.MemberID,key.Kind,actual.passwordHash,[]byte(actual.stored))
  if err!=nil{return nil,err}
  count,err:=result.RowsAffected();if err!=nil||count!=1{return nil,ErrOwnedComplexConflict}
 }
 saved,err:=readProtectedOwnedComplexTx(ctx,tx,key,password);if err!=nil{return nil,err}
 if saved.plain!=source||saved.passwordHash!=actual.passwordHash{return nil,ErrOwnedComplexConflict}
 if err=tx.Commit();err!=nil{return nil,err};return saved,nil
}
