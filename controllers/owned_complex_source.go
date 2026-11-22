package controllers

import (
 "encoding/base64"
 "encoding/json"
 "errors"
 "io"
 "net/http"
 "strconv"
 "time"
 "context"
 "database/sql"

 "github.com/gin-gonic/gin"
 "bookstark/middleware"
 "bookstark/models"
)
func ownedComplexKey(c *gin.Context)(models.OwnedComplexIdentity,bool){
 id,ok:=middleware.ParseID(c,"id");if !ok{apiError(c,400,"Invalid resource ID");return models.OwnedComplexIdentity{},false}
 key:=models.OwnedComplexIdentity{ID:id,MemberID:middleware.GetMemberID(c),Kind:c.Query("kind"),Resource:"remote-note"}
 if c.Param("book")!=""{
  book,err:=strconv.ParseInt(c.Param("book"),10,64);if err!=nil || book<=0{apiError(c,400,"Invalid book ID");return key,false}
  key.BookID=book;key.Resource="remote-book-document"
 }
 if len(c.Request.URL.Query())!=1 || len(c.Request.URL.Query()["kind"])!=1{apiError(c,400,"Explicit kind required");return key,false}
 return key,true
}
func ownedComplexError(c *gin.Context,err error){
 switch{
 case errors.Is(err,models.ErrOwnedComplexLocked):apiError(c,423,"Protected source requires its protected editor")
 case errors.Is(err,models.ErrOwnedComplexConflict):apiError(c,409,"Source or metadata changed; read-only review required")
 case errors.Is(err,models.ErrOwnedComplexLimit):apiError(c,413,"Source exceeds editor bound")
 case errors.Is(err,models.ErrOwnedComplexFormat):apiError(c,422,"Source format is invalid; original retained")
 case errors.Is(err,models.ErrOwnedComplexDenied),errors.Is(err,sql.ErrNoRows):apiError(c,404,"Owned complex resource unavailable")
 default:apiError(c,503,"Complex source operation unconfirmed")
 }
}
func GetOwnedComplexSource(c *gin.Context){
 key,ok:=ownedComplexKey(c);if !ok{return}
 ctx,cancel:=context.WithTimeout(c.Request.Context(),30*time.Second);defer cancel()
 source,err:=models.ReadOwnedComplexSource(ctx,key);if err!=nil{ownedComplexError(c,err);return}
 c.Header("Cache-Control","no-store");apiSuccess(c,source)
}
func PutOwnedComplexSource(c *gin.Context){
 key,ok:=ownedComplexKey(c);if !ok{return}
 c.Request.Body=http.MaxBytesReader(c.Writer,c.Request.Body,28*1024*1024+128*1024)
 var request struct {Expected string `json:"expected_fp"`;Source string `json:"source_base64"`;Title *string `json:"title"`;Labels *[]string `json:"labels"`}
 decoder:=json.NewDecoder(c.Request.Body);decoder.DisallowUnknownFields()
 if err:=decoder.Decode(&request);err!=nil{apiError(c,400,"Invalid bounded source request");return}
 var extra any;if err:=decoder.Decode(&extra);err!=io.EOF{apiError(c,400,"Unexpected trailing request");return}
 limit:=5*1024*1024;if key.Kind=="presentation"{limit=20*1024*1024}
 if base64.StdEncoding.DecodedLen(len(request.Source))>limit+2{apiError(c,413,"Source exceeds bound");return}
 bytes,err:=base64.StdEncoding.Strict().DecodeString(request.Source);if err!=nil || len(bytes)>limit{apiError(c,400,"Invalid source bytes");return}
 ctx,cancel:=context.WithTimeout(c.Request.Context(),30*time.Second);defer cancel()
 var metadata *models.OwnedComplexMetadata
 if request.Title!=nil || request.Labels!=nil{
  if request.Title==nil || request.Labels==nil || key.Resource!="remote-note"{apiError(c,422,"Only notes accept explicit title and labels together");return}
  metadata=&models.OwnedComplexMetadata{Title:*request.Title,Labels:*request.Labels}
 }
 actual,err:=models.SaveOwnedComplexEdit(ctx,key,request.Expected,string(bytes),metadata);if err!=nil{ownedComplexError(c,err);return}
 c.Header("Cache-Control","no-store");apiSuccess(c,actual)
}
