//go:build ignore

// Standalone Go JSON/ZIP contract fixtures; no BookStark production imports.
package main
import (
 "archive/zip"; "crypto/sha256"; "encoding/hex"; "encoding/json";
 "os"; "strings"; "time"; "encoding/base64"
)
type obj = map[string]interface{}
func main() {
 attachment:=[]byte{0,255,13,10,1,2,3}
 digest:=sha256.Sum256(attachment)
 times:=func(row obj) obj {row["create_time"]="2026-11-08T00:00:00Z";row["modify_time"]="";return row}
 data:=map[string]interface{}{
  "manifest.json":obj{"version":1,"source":"bookstark","export_time":"2026-11-08T00:00:00Z","stats":obj{
   "books":1,"documents":2,"blogs":1,"bookmarks":0,"tasks":1,"topics":1,"labels":1,"friend_links":1,"uploads":1,
  }},
  "books.json":[]interface{}{times(obj{
   "book_name":"book","identify":"book-id","description":"","label":"资料","order_index":7,"is_use_first_document":1,
   "documents":[]interface{}{
    times(obj{"document_name":"parent","identify":"parent-id","parent_identify":"","order_sort":7,"doc_type":"markdown","markdown":"\ufeff# parent\r\n","is_open":0}),
    times(obj{"document_name":"child","identify":"child-id","parent_identify":"parent-id","order_sort":9,"doc_type":"excalidraw","markdown":"{\"type\":\"excalidraw\",\"future\":{\"opaque\":true}}","is_open":0}),
   },
  })},
  "blogs.json":[]interface{}{times(obj{"blog_title":"note","blog_identify":"note-id","blog_content":"\ufeff# body\r\n","password":"","blog_type":"note","visibility":2,"is_pinned":1,"pin_order":5,"version":3})},
  "bookmarks.json":nil,
  "tasks.json":[]interface{}{times(obj{"task_id":9223372036854775807,"content":"task","due_date":"","done":false,"parent_id":0,"topic_id":4,"complete_time":""})},
  "topics.json":[]interface{}{times(obj{"topic_id":4,"title":"topic","question":"question","is_pinned":true,"summaries":nil,"resources":nil})},
  "labels.json":obj{"labels":[]interface{}{obj{"label_name":"资料"}},"relations":[]interface{}{obj{"label_name":"资料","resource_type":"blog","resource_identify":"note-id"}}},
  "friend_links.json":[]interface{}{times(obj{"group_name":"group","group_order":7,"qr_code":"","description":"keep","link_name":"friend","link_url":"https://example.invalid","sort_weight":8,"is_enabled":0})},
  "uploads.json":[]interface{}{obj{"file_name":"binary","storage_path":"bytes.bin","file_hash":hex.EncodeToString(digest[:]),"file_size":len(attachment),"mime_type":"application/octet-stream","width":0,"height":0,"thumb_path":"","thumb_size":0,"category":"files","create_time":"2026-11-08T00:00:00Z"}},
 }
 for _,variant:=range []string{"good","count-mismatch","missing-upload","hash-mismatch","size-mismatch","unknown-field","protected","unsupported-protection","missing-type","uploads-omitted","unknown-entry"} {
  encoded,e:=json.Marshal(data);if e!=nil {panic(e)}
  var current map[string]interface{}
  if e=json.Unmarshal(encoded,&current);e!=nil {panic(e)}
  // Unmarshal uses float64; retain the intentionally large task ID exactly.
  current["tasks.json"].([]interface{})[0].(map[string]interface{})["task_id"]=int64(9223372036854775807)
  blog:=current["blogs.json"].([]interface{})[0].(map[string]interface{})
  upload:=current["uploads.json"].([]interface{})[0].(map[string]interface{})
  stats:=current["manifest.json"].(map[string]interface{})["stats"].(map[string]interface{})
  switch variant {
   case "count-mismatch": stats["documents"]=3
   case "hash-mismatch": upload["file_hash"]=strings.Repeat("0",64)
   case "size-mismatch": upload["file_size"]=8
   case "unknown-field": blog["future_secret_field"]=obj{"nested":"preserve"}
   case "protected":
    // Structural envelope only: NOT a cryptographic interoperability vector.
    blog["password"]="$2a$10$"+strings.Repeat("A",53)
    blog["blog_content"]="ENC:v1:"+base64.StdEncoding.EncodeToString(make([]byte,16))+":"+base64.StdEncoding.EncodeToString(make([]byte,12))+":"+base64.StdEncoding.EncodeToString(make([]byte,16))
   case "unsupported-protection": blog["password"]="synthetic-unrecognized-format";blog["blog_content"]="ENC:v9:unsupported"
   case "missing-type": delete(blog,"blog_type")
   case "uploads-omitted": delete(current,"uploads.json");stats["uploads"]=0
   case "unknown-entry": current["future.json"]=obj{"secret":"preserve"}
  }
  out,e:=os.Create("contract-"+variant+".zip");if e!=nil {panic(e)}
  zipWriter:=zip.NewWriter(out)
  for _,name:=range []string{"manifest.json","books.json","blogs.json","bookmarks.json","tasks.json","topics.json","labels.json","friend_links.json","uploads.json","future.json"} {
   value,ok:=current[name];if !ok {continue}
   header:=&zip.FileHeader{Name:name,Method:zip.Deflate}
   header.SetModTime(time.Date(2026,11,8,0,0,0,0,time.UTC))
   writer,e:=zipWriter.CreateHeader(header);if e!=nil {panic(e)}
   encoder:=json.NewEncoder(writer);encoder.SetIndent("","  ")
   if e=encoder.Encode(value);e!=nil {panic(e)}
  }
  if variant!="missing-upload" && variant!="uploads-omitted" {
   header:=&zip.FileHeader{Name:"uploads/bytes.bin",Method:zip.Store}
   header.SetModTime(time.Date(2026,11,8,0,0,0,0,time.UTC))
   writer,e:=zipWriter.CreateHeader(header);if e!=nil {panic(e)}
   if _,e=writer.Write(attachment);e!=nil {panic(e)}
  }
  if e=zipWriter.Close();e!=nil {panic(e)};if e=out.Close();e!=nil {panic(e)}
 }
}
