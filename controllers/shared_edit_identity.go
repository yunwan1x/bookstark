package controllers

import (
 "encoding/base64"
 "encoding/json"
 "errors"
 "io"
 "net/http"
 "time"
 "unicode/utf8"
 "context"
 "bookstark/models"
 "github.com/gin-gonic/gin"
)
func sharedCASJSON(c *gin.Context,limit int64,target any)bool {
 c.Request.Body=http.MaxBytesReader(c.Writer,c.Request.Body,limit)
 decoder:=json.NewDecoder(c.Request.Body);decoder.DisallowUnknownFields()
 if decoder.Decode(target)!=nil {apiError(c,400,"共享编辑请求格式无效");return false}
 if err:=decoder.Decode(new(any));err!=io.EOF {apiError(c,400,"共享编辑请求格式无效");return false}
 return true
}
func sharedCASError(c *gin.Context,err error){
 switch {
 case errors.Is(err,models.ErrSharedEditToken):apiError(c,403,"编辑能力不可用")
 case errors.Is(err,models.ErrSharedEditPassword):apiError(c,423,"需要有效内容密码")
 case errors.Is(err,models.ErrSharedEditTarget):apiError(c,404,"分享目标不可用")
 case errors.Is(err,models.ErrSharedEditConflict):apiError(c,409,"分享内容或身份已变化")
 case errors.Is(err,models.ErrSharedEditInput):apiError(c,422,"内容格式或大小受限")
 default:apiError(c,503,"保存结果尚未确认，请只读核对")
 }
}
func ReadSharedEditCAS(c *gin.Context){
 var req struct{Password string `json:"password"`}
 if c.Request.Method=="POST"&&!sharedCASJSON(c,16*1024,&req){return}
 if !utf8.ValidString(req.Password)||len(req.Password)>4096{apiError(c,422,"密码受限");return}
 ctx,cancel:=context.WithTimeout(c.Request.Context(),20*time.Second);defer cancel()
 result,err:=models.ReadSharedContentIdentity(ctx,c.Param("identify"),c.Query("token"),req.Password)
 if err!=nil{sharedCASError(c,err);return}
 c.Header("Cache-Control","no-store")
 apiSuccess(c,result)
}
func SaveSharedEditCAS(c *gin.Context){
 var req struct{
  SourceBase64 string `json:"source_base64"`
  Password string `json:"password"`
  ExpectedSHA string `json:"expected_source_sha256"`
  ExpectedIdentity models.SharedEditIdentity `json:"expected_identity"`
 }
 // Encoded20MiB source fits28MiB; matching bounded GET envelope. No JSON
 // content escaping expansion or implicit gzip/decompression normalization.
 if !sharedCASJSON(c,28*1024*1024+128*1024,&req){return}
 if len(req.SourceBase64)>((20*1024*1024+2)/3)*4||len(req.Password)>4096||!utf8.ValidString(req.Password){
  apiError(c,422,"共享内容超过限制");return
 }
 bytes,err:=base64.StdEncoding.Strict().DecodeString(req.SourceBase64)
 if err!=nil||base64.StdEncoding.EncodeToString(bytes)!=req.SourceBase64||!utf8.Valid(bytes){
  apiError(c,422,"共享内容编码无效");return
 }
 ctx,cancel:=context.WithTimeout(c.Request.Context(),20*time.Second);defer cancel()
 result,err:=models.SaveSharedContentWithIdentity(ctx,c.Param("identify"),c.Query("token"),string(bytes),req.Password,req.ExpectedSHA,req.ExpectedIdentity)
 if err!=nil{sharedCASError(c,err);return}
 c.Header("Cache-Control","no-store")
 apiSuccess(c,gin.H{"modify_time":result.ModifyTime.Format("2006-01-02 15:04:05"),"source_sha256":result.SourceSHA256})
}
