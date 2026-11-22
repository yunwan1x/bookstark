package controllers_test
import (
 "encoding/json"
 "net/http"
 "net/http/httptest"
 "strconv"
 "testing"
 "bookstark/conf"
 "bookstark/middleware"
 "bookstark/models"
 "golang.org/x/crypto/bcrypt"
)
func TestProtectedOwnedRoutesActualAuthCSRFAndReadonlyRetarget(t *testing.T){
 router,token:=initAssetControllerTest(t)
 decode:=func(w *httptest.ResponseRecorder)map[string]any{
  t.Helper();var envelope map[string]any
  if w.Code!=200||json.Unmarshal(w.Body.Bytes(),&envelope)!=nil{t.Fatalf("status %d",w.Code)}
  data,ok:=envelope["data"].(map[string]any);if !ok{t.Fatal("actual data missing")};return data
 }
 made:=decode(adminAssetRequest(router,token,http.MethodPost,"/api/blogs",map[string]any{
  "blog_title":"Protected fixture","blog_type":"note","editor_type":"drawing","blog_content":"[]","visibility":0,
 }))
 id:=int64(made["blog_id"].(float64));if id<=0{t.Fatal("real identity")}
 prefix:="/api/owned-complex/notes/"+strconv.FormatInt(id,10)
 password:="fixture-only"
 hash,err:=bcrypt.GenerateFromPassword([]byte(password),bcrypt.MinCost);if err!=nil{t.Fatal(err)}
 cipher,err:=models.EncryptContent(password,"[]");if err!=nil{t.Fatal(err)}
 result,err:=models.DB.Exec("UPDATE md_blogs SET password=?,blog_content=? WHERE blog_id=?",string(hash),cipher,id)
 if err!=nil{t.Fatal(err)};if n,_:=result.RowsAffected();n!=1{t.Fatal("fixture update")}
 member,err:=models.GetMemberByAccount(conf.App.AdminAccount);if err!=nil{t.Fatal(err)}
 jwt,err:=middleware.GenerateToken(member.MemberID,member.Account,member.Role);if err!=nil{t.Fatal(err)}
 for _,route:=range []struct{method,path string}{
  {http.MethodPost,prefix+"/unlock?kind=drawing"},
  {http.MethodPost,prefix+"/protected-review"},
  {http.MethodPut,prefix+"/protected?kind=drawing"},
 }{
  anonymous:=httptest.NewRecorder()
  router.ServeHTTP(anonymous,httptest.NewRequest(route.method,route.path,nil))
  if anonymous.Code!=http.StatusUnauthorized{t.Fatalf("anonymous %d",anonymous.Code)}
  req:=httptest.NewRequest(route.method,route.path,nil)
  req.AddCookie(&http.Cookie{Name:"token",Value:jwt})
  denied:=httptest.NewRecorder();router.ServeHTTP(denied,req)
  if denied.Code!=http.StatusForbidden{t.Fatalf("cookie request without CSRF %d",denied.Code)}
 }
 unlocked:=decode(adminAssetRequest(router,token,http.MethodPost,prefix+"/unlock?kind=drawing",map[string]any{"password":password}))
 reviewed:=decode(adminAssetRequest(router,token,http.MethodPost,prefix+"/protected-review",map[string]any{"password":password}))
 if reviewed["resource_fp"]!=unlocked["resource_fp"]{t.Fatal("same current tuple differs")}
 decode(adminAssetRequest(router,token,http.MethodPut,prefix+"/protected?kind=drawing",map[string]any{
  "password":password,"expected_fp":unlocked["resource_fp"],"source_base64":unlocked["source_base64"],
 }))
 var after string
 if err=models.DB.QueryRow("SELECT blog_content FROM md_blogs WHERE blog_id=?",id).Scan(&after);err!=nil{t.Fatal(err)}
 if after!=cipher{t.Fatal("readonly/noop request modified original cipher")}
}
