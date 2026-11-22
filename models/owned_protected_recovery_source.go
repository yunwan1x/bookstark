package models

import (
 "context"
 "database/sql"
 "encoding/base64"
 "encoding/json"
 "unicode/utf8"
 "golang.org/x/crypto/bcrypt"
)

// Recovery reads are seven-kind and owner-only. This type grants no write
// operation: SaveProtectedOwnedComplexSource remains strictly five-kind notes.
type OwnedProtectedRecoverySource struct {
 *OwnedComplexSnapshot
 BlogType string `json:"blog_type"`
 Protected bool `json:"protected"`
}
func ReadOwnedProtectedRecoverySource(ctx context.Context,memberID,id int64,password string)(*OwnedProtectedRecoverySource,error){
 if memberID<=0||id<=0||len(password)>4096||!utf8.ValidString(password){return nil,ErrOwnedComplexDenied}
 tx,err:=DB.BeginTx(ctx,nil);if err!=nil{return nil,err};defer tx.Rollback()
 var blogType,editor string
 var hash sql.NullString
 err=tx.QueryRowContext(ctx,"SELECT blog_type,editor_type,CASE WHEN length(CAST(password AS BLOB))<=128 THEN password ELSE NULL END FROM md_blogs WHERE blog_id=? AND member_id=?",id,memberID).Scan(&blogType,&editor,&hash)
 if err!=nil{return nil,err}
 if blogType!="note"&&blogType!="article"{return nil,ErrOwnedComplexDenied}
 kind:=editor;if kind==""{kind="markdown"}
 switch kind{case "markdown","html","spreadsheet","drawing","mindmap","richdoc","presentation":default:return nil,ErrOwnedComplexDenied}
 protected:=hash.Valid&&hash.String!=""
 if !hash.Valid {
  // Distinguish a legitimate NULL password from an oversized/corrupt hash.
  var absent bool
  if err=tx.QueryRowContext(ctx,"SELECT password IS NULL FROM md_blogs WHERE blog_id=? AND member_id=?",id,memberID).Scan(&absent);err!=nil{return nil,err}
  if !absent{return nil,ErrOwnedComplexDenied}
 }
 if protected&&bcrypt.CompareHashAndPassword([]byte(hash.String),[]byte(password))!=nil{return nil,ErrOwnedProtectedCredential}
 metadata,stored,err:=ownedMetadata(ctx,tx,"md_blogs","blog_content",
  "blog_id=? AND member_id=? AND blog_type=? AND editor_type=? AND COALESCE(password,'')=?",
  []any{id,memberID,blogType,editor,hash.String})
 if err!=nil{return nil,err}
 encoded:=stored
 if IsEncrypted(stored){
  if !protected{return nil,ErrOwnedComplexFormat}
  encoded,err=DecryptContent(password,stored);if err!=nil{return nil,ErrOwnedComplexFormat}
 }
 var plain string
 if kind=="markdown"{
  // Markdown has no JSON/gzip normalization. Preserve BOM, CRLF and source.
  if len(encoded)>5*1024*1024||!utf8.ValidString(encoded){return nil,ErrOwnedComplexLimit}
  if ownedProtected(encoded){return nil,ErrOwnedComplexFormat}
  plain=encoded
 }else{plain,err=ownedDecode(kind,encoded);if err!=nil{return nil,err}}
 labels,relations,err:=ownedLabels(ctx,tx,id,"blog");if err!=nil{return nil,err}
 title,ok:=metadata["blog_title"].(string);if !ok||len(title)>65536{return nil,ErrOwnedComplexDenied}
 // Same full-tuple fingerprint domain as a five-kind protected Save receipt.
 // A retarget/format/password/protection change necessarily changes this hash.
 fp,err:=json.Marshal([]any{"owned-protected-complex-v1","remote-note",id,int64(0),memberID,kind,
  protected,hash.String,metadata,relations,ownedComplexDigest([]byte(stored)),ownedComplexDigest([]byte(plain))})
 if err!=nil{return nil,err}
 result:=&OwnedProtectedRecoverySource{OwnedComplexSnapshot:&OwnedComplexSnapshot{
  Resource:"owned-blog-recovery",ID:id,BookID:0,MemberID:memberID,Kind:kind,Title:title,Labels:labels,
  Fingerprint:ownedComplexDigest(fp),Source:base64.StdEncoding.EncodeToString([]byte(plain)),
  Bytes:len(plain),SHA256:ownedComplexDigest([]byte(plain)),metadata:metadata,stored:stored,plain:plain},
  BlogType:blogType,Protected:protected}
 if err=tx.Commit();err!=nil{return nil,err};return result,nil
}
