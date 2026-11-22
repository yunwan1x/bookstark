package controllers
import (
 "context"
 "encoding/base64"
 "encoding/json"
 "errors"
 "io"
 "net/http"
 "time"
 "bookstark/models"
 "github.com/gin-gonic/gin"
)
func protectedOwnedError(c *gin.Context,err error){
 if errors.Is(err,models.ErrOwnedProtectedCredential){apiError(c,403,"Protected credential rejected");return}
 ownedComplexError(c,err)
}
func UnlockProtectedOwnedComplexSource(c *gin.Context){
 c.Header("Cache-Control","no-store")
 key,ok:=ownedComplexKey(c);if !ok{return}
 if key.Resource!="remote-note"{apiError(c,400,"Protected note required");return}
 c.Request.Body=http.MaxBytesReader(c.Writer,c.Request.Body,8192)
 var request struct{Password string `json:"password"`}
 decoder:=json.NewDecoder(c.Request.Body);decoder.DisallowUnknownFields()
 if err:=decoder.Decode(&request);err!=nil{apiError(c,400,"Invalid credential request");return}
 var extra any;if err:=decoder.Decode(&extra);err!=io.EOF{apiError(c,400,"Trailing request");return}
 ctx,cancel:=context.WithTimeout(c.Request.Context(),30*time.Second);defer cancel()
 actual,err:=models.ReadProtectedOwnedComplexSource(ctx,key,request.Password)
 if err!=nil{protectedOwnedError(c,err);return}
 apiSuccess(c,actual)
}
func PutProtectedOwnedComplexSource(c *gin.Context){
 c.Header("Cache-Control","no-store")
 key,ok:=ownedComplexKey(c);if !ok{return}
 if key.Resource!="remote-note"{apiError(c,400,"Protected note required");return}
 c.Request.Body=http.MaxBytesReader(c.Writer,c.Request.Body,28*1024*1024+128*1024)
 var request struct{
  Password string `json:"password"`
  Expected string `json:"expected_fp"`
  Source string `json:"source_base64"`
 }
 decoder:=json.NewDecoder(c.Request.Body);decoder.DisallowUnknownFields()
 if err:=decoder.Decode(&request);err!=nil{apiError(c,400,"Invalid protected source request");return}
 var extra any;if err:=decoder.Decode(&extra);err!=io.EOF{apiError(c,400,"Trailing request");return}
 limit:=5*1024*1024;if key.Kind=="presentation"{limit=20*1024*1024}
 if base64.StdEncoding.DecodedLen(len(request.Source))>limit+2{apiError(c,413,"Source bound");return}
 source,err:=base64.StdEncoding.Strict().DecodeString(request.Source)
 if err!=nil||len(source)>limit{apiError(c,400,"Invalid bounded source");return}
 ctx,cancel:=context.WithTimeout(c.Request.Context(),30*time.Second);defer cancel()
 actual,err:=models.SaveProtectedOwnedComplexSource(ctx,key,request.Password,request.Expected,string(source))
 if err!=nil{protectedOwnedError(c,err);return}
 apiSuccess(c,actual)
}
