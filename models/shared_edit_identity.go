package models

import (
 "database/sql"
 "errors"
 "context"
 "crypto/subtle"
 "encoding/base64"
 "strings"
 "time"
 "unicode/utf8"
)
type SharedEditIdentity struct {
 ShareID int64 `json:"share_id"`
 TargetID int64 `json:"target_id"`
 OwnerID int64 `json:"owner_member_id"`
 BookID int64 `json:"book_id"`
 ShareType string `json:"share_type"`
 Format string `json:"format"`
 Protected bool `json:"protected"`
 Collection string `json:"blog_type"`
}
type SharedEditSource struct {
 Identity SharedEditIdentity `json:"identity"`
 Title string `json:"title"`
 Modified string `json:"modify_time"`
 SourceBase64 string `json:"source_base64"`
 SourceSHA256 string `json:"source_sha256"`
 Bytes int `json:"bytes"`
}
func sharedIdentityTokenEqual(actual,expected string)bool{return actual!=""&&subtle.ConstantTimeCompare([]byte(actual),[]byte(expected))==1}
func reservedSharedEnvelope(value string)bool {
 return strings.HasPrefix(strings.TrimPrefix(value,"\ufeff"),"ENC:")
}
func validateSharedIdentitySource(format,source string)error {
 limit,valid:=sharedEditLimit(format)
 if !valid||!utf8.ValidString(source)||len(source)>limit||reservedSharedEnvelope(source){return ErrSharedEditInput}
 if format=="markdown"{return nil}
 // Exact existing6-kind validator from frozen owned-complex batch, including
 // Unicode/depth/type/size. No format conversion or source normalization.
 if err:=validateOwnedComplexSource(format,source);err!=nil{return ErrSharedEditInput}
 return nil
}
func (key SharedEditIdentity) valid()bool {
 _,ok:=sharedEditLimit(key.Format)
 return ok&&key.ShareID>0&&key.TargetID>0&&key.OwnerID>0&&
 ((key.ShareType=="blog"&&key.BookID==0&&(key.Collection=="note"||key.Collection=="article"))||(key.ShareType=="document"&&key.BookID>0&&key.Collection==""))
}
func checkSharedStoredBudget(ctx context.Context,tx *sql.Tx,kind string,id int64)error{
 var size int64;var err error
 switch kind{
 case "blog":err=tx.QueryRowContext(ctx,"SELECT COALESCE(length(CAST(blog_content AS BLOB)),0) FROM md_blogs WHERE blog_id=?",id).Scan(&size)
 case "document":err=tx.QueryRowContext(ctx,"SELECT COALESCE(length(CAST(markdown AS BLOB)),0) FROM md_documents WHERE document_id=?",id).Scan(&size)
 default:return ErrSharedEditInput
 }
 if errors.Is(err,sql.ErrNoRows){return ErrSharedEditTarget};if err!=nil{return err};if size<0||size>32*1024*1024{return ErrSharedEditInput};return nil
}
func sharedIdentityModified(ctx context.Context,tx *sql.Tx,kind string,id int64)(time.Time,error){
 var value string;var err error
 switch kind {
 case "blog":err=tx.QueryRowContext(ctx,"SELECT COALESCE(strftime('%Y-%m-%d %H:%M:%S',modify_time),'0001-01-01 00:00:00') FROM md_blogs WHERE blog_id=?",id).Scan(&value)
 case "document":err=tx.QueryRowContext(ctx,"SELECT COALESCE(strftime('%Y-%m-%d %H:%M:%S',modify_time),'0001-01-01 00:00:00') FROM md_documents WHERE document_id=?",id).Scan(&value)
 default:return time.Time{},ErrSharedEditInput
 }
 if err!=nil{return time.Time{},err};return time.Parse("2006-01-02 15:04:05",value)
}
func SaveSharedContentWithIdentity(ctx context.Context,identify,token,source,password,expectedSHA string,key SharedEditIdentity)(*SharedContentReceipt,error){
 if !key.valid()||!sharedSourceHashPattern.MatchString(expectedSHA){return nil,ErrSharedEditInput}
 return saveSharedContentIdentity(ctx,identify,token,source,password,&expectedSHA,&key)
}
// Source and identity share one read transaction; password/token never enter
// the result. NULL and empty plaintext have same digest, but typed no-op keeps
// original stored bytes/NULL representation unchanged.
func ReadSharedContentIdentity(ctx context.Context,identify,token,password string)(*SharedEditSource,error){
 if token==""{return nil,ErrSharedEditToken}
 tx,err:=DB.BeginTx(ctx,nil);if err!=nil{return nil,err};defer tx.Rollback()
 var key SharedEditIdentity;var currentToken string
 err=tx.QueryRowContext(ctx,"SELECT share_id,share_type,target_id,member_id,edit_token FROM md_shares WHERE share_identify=?",identify).Scan(
  &key.ShareID,&key.ShareType,&key.TargetID,&key.OwnerID,&currentToken)
 if err!=nil{return nil,ErrSharedEditTarget}
 if !sharedIdentityTokenEqual(currentToken,token){return nil,ErrSharedEditToken}
 if err=checkSharedStoredBudget(ctx,tx,key.ShareType,key.TargetID);err!=nil{return nil,err}
 var title,stored,passwordHash string;var owner int64
 switch key.ShareType{
 case "blog":
  err=tx.QueryRowContext(ctx,"SELECT member_id,COALESCE(editor_type,'markdown'),COALESCE(blog_content,''),password,blog_title,blog_type FROM md_blogs WHERE blog_id=?",key.TargetID).Scan(&owner,&key.Format,&stored,&passwordHash,&title,&key.Collection)
 case "document":
  err=tx.QueryRowContext(ctx,"SELECT d.member_id,COALESCE(d.doc_type,'markdown'),COALESCE(d.markdown,''),d.document_name,d.book_id FROM md_documents d JOIN md_books b ON b.book_id=d.book_id WHERE d.document_id=? AND b.member_id=?",key.TargetID,key.OwnerID).Scan(&owner,&key.Format,&stored,&title,&key.BookID)
 default:return nil,ErrSharedEditInput
 }
 if err!=nil{return nil,ErrSharedEditTarget}
 key.Protected=passwordHash!=""
 if !key.valid()||owner!=key.OwnerID{return nil,ErrSharedEditTarget}
 if key.Protected&&!(&Blog{Password:passwordHash}).VerifyPassword(password){return nil,ErrSharedEditPassword}
 if reservedSharedEnvelope(stored)&&(!key.Protected||!IsEncrypted(stored)){return nil,ErrSharedEditPassword}
 limit,_:=sharedEditLimit(key.Format)
 source,err:=sharedEditFullSource(key.Format,stored,key.Protected,password,limit)
 if err!=nil{return nil,ErrSharedEditInput}
 if err=validateSharedIdentitySource(key.Format,source);err!=nil{return nil,err}
 modified,err:=sharedIdentityModified(ctx,tx,key.ShareType,key.TargetID);if err!=nil{return nil,err}
 if err=tx.Commit();err!=nil{return nil,err}
 return &SharedEditSource{Identity:key,Title:title,Modified:modified.Format("2006-01-02 15:04:05"),
 SourceBase64:base64.StdEncoding.EncodeToString([]byte(source)),SourceSHA256:sharedEditSourceHash(source),Bytes:len(source)},nil
}
