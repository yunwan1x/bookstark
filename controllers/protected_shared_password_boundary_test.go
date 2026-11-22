package controllers_test

import (
 "encoding/base64"
 "encoding/json"
 "net/url"
 "reflect"
 "strings"
 "testing"
 "bookstark/models"
)

// Synthetic secrets only. GET query-password must never authorize source access;
// the production typed client sends passwords solely in CSRF-bound POST bodies.
func TestTypedProtectedSharePasswordOnlyPOSTBodyWithoutReadMutation(t *testing.T) {
 router,_:=initAssetControllerTest(t)
 blog:=&models.Blog{BlogTitle:"Protected typed source",BlogIdentify:"protected-typed-password",
  MemberID:1,BlogType:"note",EditorType:"markdown",Visibility:1,
  BlogContent:"\ufeffprotected body🙂\r\n",Password:" correct "}
 if err:=blog.Insert();err!=nil{t.Fatal(err)}
 token:=strings.Repeat("b",64)
 if _,err:=models.CreateShare("blog",blog.BlogID,1,token);err!=nil{t.Fatal(err)}
 share,err:=models.GetShareByTypeAndTarget("blog",blog.BlogID);if err!=nil{t.Fatal(err)}
 path:="/api/shares/"+url.PathEscape(share.ShareIdentify)+"/edit/cas?token="+token
 before,err:=models.GetBlogByID(blog.BlogID);if err!=nil{t.Fatal(err)}
 if !strings.HasPrefix(before.BlogContent,"ENC:"){t.Fatal("fixture is not encrypted")}
 if got:=typedSharedRequest(router,"GET",path+"&password="+url.QueryEscape(" correct "),nil,false).Code;got!=423{
  t.Fatal("GET query password authorized protected source",got)
 }
 readPath:=strings.Replace(path,"/edit/cas?","/edit/cas/read?",1)
 if got:=typedSharedRequest(router,"POST",readPath,map[string]any{"password":" correct "},false).Code;got!=403{
  t.Fatal("unlock bypassed anonymous CSRF",got)
 }
 response:=typedSharedRequest(router,"POST",readPath,map[string]any{"password":" correct "},true)
 if response.Code!=200{t.Fatal("CSRF POST-body unlock refused",response.Code)}
 var source struct{Data models.SharedEditSource}
 if err:=json.Unmarshal(response.Body.Bytes(),&source);err!=nil{t.Fatal(err)}
 bytes,err:=base64.StdEncoding.DecodeString(source.Data.SourceBase64);if err!=nil{t.Fatal(err)}
 if string(bytes)!="\ufeffprotected body🙂\r\n"{t.Fatal("unlocked source changed exact bytes")}
 after,err:=models.GetBlogByID(blog.BlogID);if err!=nil{t.Fatal(err)}
 if !reflect.DeepEqual(after,before){t.Fatal("read/unlock mutated encrypted bytes or metadata")}
}
