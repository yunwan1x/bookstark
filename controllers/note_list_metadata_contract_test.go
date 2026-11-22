package controllers_test
import (
 "encoding/json"
 "net/http"
 "strings"
 "testing"
 "unicode/utf8"
 "bookstark/conf"
 "bookstark/models"
)
// Uses real router/auth/SQLite producer; no fixture JSON replaces the producer.
func TestOwnedNoteMetadataOptInContract(t *testing.T) {
 router, token := initAssetControllerTest(t)
 owner, err := models.GetMemberByAccount(conf.App.AdminAccount)
 if err != nil { t.Fatal(err) }
 insert := func(title, collection, kind, source string, member int64, pin int) int64 {
  t.Helper()
  b := &models.Blog{BlogTitle:title, BlogIdentify:"metadata-"+title, MemberID:member,
   BlogType:collection, EditorType:kind, BlogContent:source, Visibility:1, IsPinned:pin}
  if err:=b.Insert();err!=nil {t.Fatal(err)};return b.BlogID
 }
 big:=strings.Repeat("雪🙂",32768)
 source:="\x60\x60\x60go\nx\n\x60\x60\x60\n"+big
 first:=insert("contract-first","note","markdown",source,owner.MemberID,1)
 second:=insert("contract-second","note","markdown","second "+big,owner.MemberID,0)
 insert("contract-article","article","markdown","not a note",owner.MemberID,0)
 other:=&models.Member{Account:"metadata-other",Password:"fixture-only",Email:"other@example.invalid",Status:0}
 if err:=other.Insert();err!=nil {t.Fatal(err)}
 insert("contract-foreign","note","markdown","foreign",other.MemberID,1)
 if err:=models.BindLabelsFromNames(first,"blog","contract-label");err!=nil {t.Fatal(err)}
 if _,err:=models.DB.Exec("UPDATE md_blogs SET create_time='2026-10-01 12:00:00',modify_time='2026-10-01 12:00:00' WHERE blog_id IN (?,?)",first,second);err!=nil {t.Fatal(err)}
 type envelope struct {
  Code int;Data []models.BlogWithLabels;Total int;Page int
  PageSize int `json:"page_size"`;TotalPages int `json:"total_pages"`
 }
 get:=func(query string)(envelope,int){
  t.Helper();r:=adminAssetRequest(router,token,http.MethodGet,"/api/blogs?"+query,nil)
  if r.Code!=http.StatusOK {t.Fatalf("status=%d",r.Code)}
  var e envelope
  if err:=json.Unmarshal(r.Body.Bytes(),&e);err!=nil {t.Fatal(err)}
  if e.Code!=0 {t.Fatalf("code=%d",e.Code)}
  return e,r.Body.Len()
 }
 e,size:=get("type=note&keyword=contract-&page=1&page_size=1&metadata_only=1")
 if size>16384||e.Total!=2||e.Page!=1||e.PageSize!=1||e.TotalPages!=2||len(e.Data)!=1||e.Data[0].BlogID!=first {t.Fatalf("bounded owned page: size=%d %+v",size,e)}
 row:=e.Data[0]
 if row.MemberID!=owner.MemberID||row.BlogType!="note"||row.EditorType!="markdown"||row.Visibility!=1||row.IsPinned!=1||len(row.Labels)!=1||row.Labels[0]!="contract-label"||utf8.RuneCountInString(row.ContentPreview)>512 {t.Fatalf("metadata: %+v",row)}
 page2,_:=get("type=note&keyword=contract-&page=2&page_size=1&metadata_only=1")
 if len(page2.Data)!=1||page2.Data[0].BlogID!=second {t.Fatalf("page2=%+v",page2)}
 for _,q:=range []string{"label=contract-label","pinned=1","visibility=1&has_code=1","date=2026-10-01&editor_type=markdown&label=contract-label","keyword=contract-label"} {
  filtered,_:=get("type=note&metadata_only=1&page=1&page_size=20&"+q)
  if len(filtered.Data)!=1||filtered.Data[0].BlogID!=first {t.Fatalf("filter %q: %+v",q,filtered)}
 }
 legacy,legacySize:=get("type=note&keyword=contract-first&page=1&page_size=20")
 if legacySize<=size||len(legacy.Data)!=1||legacy.Data[0].ContentPreview!=source {t.Fatal("legacy default body preview changed")}
 insert("encoded-html","note","html",strings.Repeat("<p>source</p>",8192),owner.MemberID,0)
 protected:=&models.Blog{BlogTitle:"protected",BlogIdentify:"metadata-protected",MemberID:owner.MemberID,BlogType:"note",EditorType:"markdown",BlogContent:big,Password:"fixture-pass"}
 if err:=protected.Insert();err!=nil {t.Fatal(err)}
 for _,keyword:=range []string{"encoded-html","protected"} {
  got,n:=get("type=note&metadata_only=1&page=1&page_size=20&keyword="+keyword)
  if n>16384||len(got.Data)!=1||got.Data[0].ContentPreview!="" {t.Fatalf("non-preview source leaked: %q",keyword)}
 }
}
