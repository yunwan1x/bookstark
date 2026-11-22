package controllers_test
import(
 "bytes"
 "encoding/base64"
 "encoding/json"
 "net/http"
 "net/http/httptest"
 "net/url"
 "reflect"
 "strings"
 "testing"
 "bookstark/models"
)
func typedSharedRequest(router http.Handler,method,path string,body any,csrf bool)*httptest.ResponseRecorder{
 var payload []byte;if body!=nil{payload,_=json.Marshal(body)}
 request:=httptest.NewRequest(method,path,bytes.NewReader(payload))
 request.Header.Set("Content-Type","application/json")
 if csrf{nonce:=strings.Repeat("a",64);request.AddCookie(&http.Cookie{Name:"csrf_token",Value:nonce});request.Header.Set("X-CSRF-Token",nonce)}
 response:=httptest.NewRecorder();router.ServeHTTP(response,request);return response
}
func typedSharedFixture(t *testing.T)(http.Handler,*models.Blog,string){
 t.Helper();router,_:=initAssetControllerTest(t)
 blog:=&models.Blog{BlogTitle:"Typed source",BlogIdentify:"typed-cas-controller",MemberID:1,
 BlogType:"article",EditorType:"markdown",Visibility:1,BlogContent:"\ufeffbefore\r\n"}
 if err:=blog.Insert();err!=nil{t.Fatal(err)}
 token:=strings.Repeat("a",64)
 share,err:=models.CreateShare("blog",blog.BlogID,1,token);if err!=nil{t.Fatal(err)}
 share,err=models.GetShareByTypeAndTarget("blog",blog.BlogID);if err!=nil{t.Fatal(err)}
 path:="/api/shares/"+url.PathEscape(share.ShareIdentify)+"/edit/cas?token="+token
 return router,blog,path
}
func TestTypedShareCASRequiresAnonymousCSRFAndMandatoryTuple(t *testing.T){
 router,blog,path:=typedSharedFixture(t)
 response:=typedSharedRequest(router,"GET",path,nil,false)
 if response.Code!=200{t.Fatal("source refused",response.Code)}
 var source struct{Data models.SharedEditSource}
 if err:=json.Unmarshal(response.Body.Bytes(),&source);err!=nil{t.Fatal(err)}
 body:=map[string]any{"source_base64":base64.StdEncoding.EncodeToString([]byte("\ufeffafter🙂\r\n")),
 "expected_source_sha256":source.Data.SourceSHA256,"expected_identity":source.Data.Identity}
 // Possessing capability is not permission to skip this endpoint CSRF boundary.
 if got:=typedSharedRequest(router,"PUT",path,body,false).Code;got!=403{t.Fatal("missing CSRF accepted",got)}
 malformed:=map[string]any{"source_base64":body["source_base64"],"expected_source_sha256":source.Data.SourceSHA256}
 if got:=typedSharedRequest(router,"PUT",path,malformed,true).Code;got!=422{t.Fatal("missing tuple accepted",got)}
 response=typedSharedRequest(router,"PUT",path,body,true)
 if response.Code!=200{t.Fatal("valid anonymous capability+CSRF refused",response.Code)}
 actual,_:=models.GetBlogByID(blog.BlogID)
 if actual.BlogContent!="\ufeffafter🙂\r\n"||actual.BlogTitle!=blog.BlogTitle{t.Fatal("body bytes or metadata changed")}
 if got:=typedSharedRequest(router,"PUT",path,body,true).Code;got!=409{t.Fatal("stale source repeated",got)}
}
func TestTypedShareReadWrongKindAndUnknownFieldNeverMutate(t *testing.T){
 router,blog,path:=typedSharedFixture(t)
 // Insert sets SQL defaults but only returns BlogID to its input object.
 // Snapshot the complete persisted row before even the source GET.
 before,err:=models.GetBlogByID(blog.BlogID);if err!=nil{t.Fatal(err)}
 response:=typedSharedRequest(router,"GET",path,nil,false)
 if response.Code!=200{t.Fatal("source refused",response.Code)}
 var source struct{Data models.SharedEditSource}
 if err:=json.Unmarshal(response.Body.Bytes(),&source);err!=nil{t.Fatal(err)}
 key:=source.Data.Identity;key.Format="html"
 body:=map[string]any{"source_base64":base64.StdEncoding.EncodeToString([]byte("<p>wrong kind</p>")),
 "expected_source_sha256":source.Data.SourceSHA256,"expected_identity":key}
 if got:=typedSharedRequest(router,"PUT",path,body,true).Code;got!=409{t.Fatal("wrong kind accepted",got)}
 body["unknown"]="must reject"
 if got:=typedSharedRequest(router,"PUT",path,body,true).Code;got!=400{t.Fatal("unknown key accepted",got)}
 actual,err:=models.GetBlogByID(blog.BlogID);if err!=nil{t.Fatal(err)}
 if !reflect.DeepEqual(actual,before){t.Fatal("rejection mutated persisted source or metadata")}
}
