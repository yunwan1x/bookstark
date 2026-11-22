package controllers
import (
 "context"
 "encoding/json"
 "io"
 "net/http"
 "time"
 "bookstark/middleware"
 "bookstark/models"
 "github.com/gin-gonic/gin"
)
// Read-only POST because credentials must never be placed in URL/query/logs.
func ReadOwnedProtectedRecoverySource(c *gin.Context){
 c.Header("Cache-Control","no-store")
 id,ok:=middleware.ParseID(c,"id");if !ok{apiError(c,400,"Invalid resource ID");return}
 if len(c.Request.URL.Query())!=0{apiError(c,400,"No recovery query accepted");return}
 c.Request.Body=http.MaxBytesReader(c.Writer,c.Request.Body,8192)
 var request struct{Password string `json:"password"`}
 decoder:=json.NewDecoder(c.Request.Body);decoder.DisallowUnknownFields()
 if err:=decoder.Decode(&request);err!=nil{apiError(c,400,"Invalid recovery credential request");return}
 var extra any;if err:=decoder.Decode(&extra);err!=io.EOF{apiError(c,400,"Trailing request");return}
 ctx,cancel:=context.WithTimeout(c.Request.Context(),30*time.Second);defer cancel()
 source,err:=models.ReadOwnedProtectedRecoverySource(ctx,middleware.GetMemberID(c),id,request.Password)
 if err!=nil{protectedOwnedError(c,err);return}
 apiSuccess(c,source)
}
