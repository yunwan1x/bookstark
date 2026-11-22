package controllers_test
import (
 "encoding/json"
 "net/http"
 "net/http/httptest"
 "strconv"
 "testing"
 "bookstark/models"
)
func TestOwnedComplexRoutesRegisteredAndBlogFreshFlags(t *testing.T) {
 router,token:=initAssetControllerTest(t)
 decode:=func(w *httptest.ResponseRecorder) map[string]any {
  t.Helper()
  var root map[string]any
  if w.Code!=http.StatusOK||json.Unmarshal(w.Body.Bytes(),&root)!=nil {t.Fatalf("response status %d",w.Code)}
  data,ok:=root["data"].(map[string]any);if !ok {t.Fatal("missing response data")}
  return data
 }
 made:=decode(adminAssetRequest(router,token,http.MethodPost,"/api/blogs",map[string]any{
  "blog_title":"Owned fixture","blog_type":"note","editor_type":"drawing","blog_content":"[]","visibility":0,
 }))
 rawID,ok:=made["blog_id"].(float64);if !ok||rawID<=0 {t.Fatal("create identity")};id:=int64(rawID)
 path:="/api/owned-complex/notes/"+strconv.FormatInt(id,10)+"?kind=drawing"
 anonymous:=httptest.NewRecorder()
 router.ServeHTTP(anonymous,httptest.NewRequest(http.MethodGet,path,nil))
 if anonymous.Code!=http.StatusUnauthorized {t.Fatalf("anonymous status %d",anonymous.Code)}
 actual:=decode(adminAssetRequest(router,token,http.MethodGet,path,nil))
 fp,ok:=actual["resource_fp"].(string)
 if !ok||len(fp)!=64||actual["id"]!=rawID||actual["kind"]!="drawing" {t.Fatal("wrong owned source")}
 decode(adminAssetRequest(router,token,http.MethodPut,path,map[string]any{
  "expected_fp":fp,"source_base64":actual["source_base64"],
 }))
 for _,state:=range [][2]int{{0,0},{1,1}} {
  result,err:=models.DB.Exec("UPDATE md_blogs SET is_pinned=?,visibility=? WHERE blog_id=?",state[0],state[1],id)
  if err!=nil {t.Fatal(err)}
  if n,_:=result.RowsAffected();n!=1 {t.Fatal("setup row mismatch")}
  row:=decode(adminAssetRequest(router,token,http.MethodGet,"/api/blogs/"+strconv.FormatInt(id,10),nil))
  for field,want:=range map[string]int{"is_pinned":state[0],"visibility":state[1]} {
   raw,exists:=row[field];got,typed:=raw.(float64)
   if !exists||!typed||got!=float64(want) {t.Fatalf("fresh %s mismatch",field)}
  }
 }
}
