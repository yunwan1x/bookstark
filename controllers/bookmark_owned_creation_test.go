package controllers_test

import (
 "bytes"
 "encoding/json"
 "net/http"
 "net/http/httptest"
 "reflect"
 "strconv"
 "testing"
 "bookstark/models"
)
func TestBookmarkOwnedCreateRoutesCompleteLabelsAndDuplicateZeroMutation(t *testing.T) {
 router,token:=initAssetControllerTest(t)
 body:=map[string]any{"title":"Exact title","url":"https://owned.example.test/new",
  "description":"\ufeffExact😀\r\n","favicon":"https://owned.example.test/favicon.png",
  "is_public":false,"labels":[]string{"comma,label"," spaced ",""}}
 response:=adminAssetRequest(router,token,"POST","/api/bookmarks/create-owned",body)
 if response.Code!=200 {t.Fatal("strict creation unavailable",response.Code,response.Body.String())}
 var receipt struct {Data models.OwnedBookmarkCreationSnapshot}
 if err:=json.Unmarshal(response.Body.Bytes(),&receipt);err!=nil{t.Fatal(err)}
 if receipt.Data.BookmarkID<=0 || len(receipt.Data.Labels)!=3 {t.Fatal("incomplete actual receipt")}
 before,err:=models.ReadOwnedBookmarkCreation(receipt.Data.BookmarkID,1);if err!=nil{t.Fatal(err)}
 body["title"]="must not overwrite";body["labels"]=[]string{"must-not-create"}
 if got:=adminAssetRequest(router,token,"POST","/api/bookmarks/create-owned",body).Code;got!=409 {
  t.Fatal("duplicate was not zero-mutation conflict",got)
 }
 after,err:=models.ReadOwnedBookmarkCreation(receipt.Data.BookmarkID,1)
 if err!=nil||!reflect.DeepEqual(before,after){t.Fatal("duplicate mutated actual resource",err)}
 review:=adminAssetRequest(router,token,"GET","/api/bookmarks/"+
  strconv.FormatInt(receipt.Data.BookmarkID,10)+"/creation-review",nil)
 if review.Code!=200{t.Fatal("complete-ID route missing",review.Code)}
 var actual struct {Data models.OwnedBookmarkCreationSnapshot}
 if err=json.Unmarshal(review.Body.Bytes(),&actual);err!=nil||!reflect.DeepEqual(before,&actual.Data){
  t.Fatal("fresh complete actual-ID metadata/source differs",err)
 }
 check:=adminAssetRequest(router,token,"POST","/api/bookmarks/creation-check",
  map[string]any{"url":body["url"]})
 if check.Code!=200{t.Fatal("read-only check unavailable",check.Code)}
 after,err=models.ReadOwnedBookmarkCreation(receipt.Data.BookmarkID,1)
 if err!=nil||!reflect.DeepEqual(before,after){t.Fatal("check/read mutated resource",err)}
}
func TestBookmarkOwnedCreationStrictJSONRejectsWithoutAnyMutation(t *testing.T) {
 router,token:=initAssetControllerTest(t)
 base:=`{"title":"x","url":"https://strict.example.test/","description":"","favicon":"","is_public":false,"labels":[]}`
 invalid:=[]string{
  `{"title":"x","title":"y","url":"https://strict.example.test/","description":"","favicon":"","is_public":false,"labels":[]}`,
  `{"title":"\ud800","url":"https://strict.example.test/","description":"","favicon":"","is_public":false,"labels":[]}`,
  base[:len(base)-1]+`,"member_id":2}`,
  base+` {}`,
  `{"title":"x","url":"https://strict.example.test/","description":"","favicon":"","is_public":false,"labels":null}`,
 }
 for _,raw:=range invalid {
  req:=httptest.NewRequest(http.MethodPost,"/api/bookmarks/create-owned",bytes.NewBufferString(raw))
  req.Header.Set("Content-Type","application/json");req.Header.Set("Authorization","Token "+token)
  response:=httptest.NewRecorder();router.ServeHTTP(response,req)
  if response.Code!=400{t.Fatal("malformed JSON accepted",response.Code)}
  var count int
  if err:=models.DB.QueryRow("SELECT COUNT(*) FROM md_bookmark").Scan(&count);err!=nil||count!=0{
   t.Fatal("rejected input mutated bookmarks",err)
  }
 }
 req:=httptest.NewRequest(http.MethodPost,"/api/bookmarks/create-owned",bytes.NewBufferString(base))
 req.Header.Set("Content-Type","application/json")
 response:=httptest.NewRecorder();router.ServeHTTP(response,req)
 if response.Code==200{t.Fatal("anonymous create authorized")}
}
