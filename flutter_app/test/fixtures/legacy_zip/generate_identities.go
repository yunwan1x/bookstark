//go:build ignore

// Synthetic Go ZIP identity cases. Standard library only, no production imports.
package main
import ("archive/zip";"encoding/json";"io";"os";"bytes";"time";"strings";"sort";"crypto/sha256";"fmt")
type obj = map[string]interface{}
func clone(v interface{}) interface{} {
 b,e:=json.Marshal(v);if e!=nil{panic(e)}
 d:=json.NewDecoder(bytes.NewReader(b));d.UseNumber()
 var result interface{};if e=d.Decode(&result);e!=nil{panic(e)};return result
}
func main(){
 source,e:=zip.OpenReader(os.Args[1]);if e!=nil{panic(e)};defer source.Close()
 base:=map[string]interface{}{};blobs:=map[string][]byte{}
 for _,f:=range source.File{
  r,e:=f.Open();if e!=nil{panic(e)};b,e:=io.ReadAll(r);r.Close();if e!=nil{panic(e)}
  if len(f.Name)>5 && f.Name[len(f.Name)-5:]==".json" {
   d:=json.NewDecoder(bytes.NewReader(b));d.UseNumber();var v interface{}
   if e=d.Decode(&v);e!=nil{panic(e)};base[f.Name]=v
  }else{blobs[f.Name]=b}
 }
 vectors:=[]obj{}
 if len(os.Args)>2 {
  f,e:=os.Open(os.Args[2]);if e!=nil{panic(e)}
  d:=json.NewDecoder(f);d.UseNumber();if e=d.Decode(&vectors);e!=nil{panic(e)};f.Close()
 }
 for _,variant:=range []string{"good","tuple-alias","duplicate-bookmark","bad-reference","duplicate-child","cross-topic","comment-targets","forward-parents","known-formats","review-required","missing-hash","high-cost","protected-formats","duplicate-label-relations","record-chunks","forward-native","tuple-native","duplicate-books-native","duplicate-articles","invalid-flag","duplicate-target","large-inline","pre-epoch","upload-thumbnails","upload-shared-thumb","upload-empty","upload-ambiguous-path","upload-original-thumb","upload-large","protected-native","protected-native-unicode","protected-plain-native"}{
  data:=clone(base).(obj)
  files:=map[string][]byte{};for name,value:=range blobs{files[name]=value}
  blogs:=data["blogs.json"].([]interface{});article:=clone(blogs[0]).(obj)
  article["blog_identify"]="article-id";article["blog_type"]="article";blogs=append(blogs,article);data["blogs.json"]=blogs
  data["bookmarks.json"]=[]interface{}{obj{"title":"bookmark","url":"https://example.invalid/shared","description":"","favicon":"","order_sort":0,"label":"","is_public":0,"is_pinned":0,"nav_visible":0,"create_time":"","modify_time":""}}
  tasks:=data["tasks.json"].([]interface{});task:=clone(tasks[0]).(obj)
  task["task_id"]=int64(7);task["parent_id"]=json.Number("9223372036854775807");data["tasks.json"]=append(tasks,task)
  topics:=data["topics.json"].([]interface{});topic:=topics[0].(obj)
  summary:=obj{"summary_id":5,"content":"summary","summary_type":"manual","order_sort":0,"create_time":"","modify_time":""}
  noIDSummary:=clone(summary).(obj);delete(noIDSummary,"summary_id")
  topic["summaries"]=[]interface{}{summary,noIDSummary}
  resource:=obj{"topic_resource_id":6,"resource_type":"document","target_identify":"book-id/child-id","title_snapshot":"child","desc_snapshot":"","order_sort":0,"create_time":""}
  noIDResource:=clone(resource).(obj);delete(noIDResource,"topic_resource_id");noIDResource["resource_type"]="article";noIDResource["target_identify"]="article-id"
  topic["resources"]=[]interface{}{resource,noIDResource}
  first:=obj{"comment_id":8,"parent_comment_id":0,"target_type":"summary","target_id":5,"content":"parent","create_time":"","modify_time":""}
  child:=clone(first).(obj);child["comment_id"]=9;child["parent_comment_id"]=8;child["content"]="child"
  noIDComment:=clone(first).(obj);delete(noIDComment,"comment_id");noIDComment["content"]="no old ID"
  topic["comments"]=[]interface{}{first,child,noIDComment}
  friends:=data["friend_links.json"].([]interface{});data["friend_links.json"]=append(friends,clone(friends[0]))
  switch variant{
   case "tuple-alias","tuple-native","duplicate-books-native":
    books:=data["books.json"].([]interface{})
    for _,pair:=range [][2]string{{"a/b","c"},{"a","b/c"}}{
     book:=clone(books[0]).(obj);book["identify"]=pair[0]
     if variant=="tuple-native"{book["book_name"]=pair[0]}
     doc:=clone(book["documents"].([]interface{})[0]).(obj);doc["identify"]=pair[1];doc["parent_identify"]=""
     book["documents"]=[]interface{}{doc};books=append(books,book)
    };data["books.json"]=books
    if variant!="tuple-alias"{books[0].(obj)["documents"].([]interface{})[1].(obj)["doc_type"]="drawing"}
   case "duplicate-bookmark":
    values:=data["bookmarks.json"].([]interface{});data["bookmarks.json"]=append(values,clone(values[0]))
   case "bad-reference":resource["target_identify"]="missing/secret-source-value"
   case "duplicate-child":topic["summaries"]=append(topic["summaries"].([]interface{}),clone(summary))
   case "missing-hash","high-cost","protected-formats":
    data["books.json"].([]interface{})[0].(obj)["documents"].([]interface{})[1].(obj)["doc_type"]="drawing"
    note:=data["blogs.json"].([]interface{})[0].(obj)
    note["password"]=""
    if variant=="high-cost"{note["password"]="$2a$15$"+strings.Repeat("A",53)}
    if variant=="protected-formats"{note["password"]="$2a$10$"+strings.Repeat("A",53)}
    note["blog_content"]="ENC:v1:AAAAAAAAAAAAAAAAAAAAAA==:AAAAAAAAAAAAAAAA:AAAAAAAAAAAAAAAAAAAAAA=="
   case "duplicate-label-relations":
    data["books.json"].([]interface{})[0].(obj)["documents"].([]interface{})[1].(obj)["doc_type"]="drawing"
    labels:=data["labels.json"].(obj);values:=labels["relations"].([]interface{})
    labels["relations"]=append(values,clone(values[0]))
   case "review-required":
    data["books.json"].([]interface{})[0].(obj)["documents"].([]interface{})[1].(obj)["doc_type"]="drawing"
    note:=data["blogs.json"].([]interface{})[0].(obj)
    note["password"]="$2a$10$"+strings.Repeat("A",53)
    note["blog_content"]="ENC:v1:AAAAAAAAAAAAAAAAAAAAAA==:AAAAAAAAAAAAAAAA:AAAAAAAAAAAAAAAAAAAAAA=="
    note["future_metadata"]=obj{"keep":true}
   case "record-chunks":
    data["books.json"].([]interface{})[0].(obj)["documents"].([]interface{})[1].(obj)["doc_type"]="drawing"
    data["blogs.json"].([]interface{})[0].(obj)["blog_content"]="\ufeff"+strings.Repeat("汉🙂\r\n",300000)
   case "duplicate-articles","invalid-flag","duplicate-target","large-inline","pre-epoch":
    data["books.json"].([]interface{})[0].(obj)["documents"].([]interface{})[1].(obj)["doc_type"]="drawing"
    note:=data["blogs.json"].([]interface{})[0].(obj)
    switch variant{
     case "duplicate-articles":
      values:=data["blogs.json"].([]interface{});item:=clone(values[1]).(obj)
      item["blog_identify"]="article-two";data["blogs.json"]=append(values,item)
     case "invalid-flag":note["is_pinned"]=2
     case "duplicate-target":
      values:=topic["resources"].([]interface{});item:=clone(values[0]).(obj)
      item["topic_resource_id"]=7;topic["resources"]=append(values,item)
     case "large-inline":note["blog_title"]=strings.Repeat("A",256*1024+1)
     case "pre-epoch":
      note["create_time"]="1969-12-31T23:59:59.999999999Z"
      note["version"]=json.Number("9223372036854775807")
    }
   case "upload-thumbnails","upload-shared-thumb","upload-empty","upload-ambiguous-path","upload-original-thumb","upload-large":
    data["books.json"].([]interface{})[0].(obj)["documents"].([]interface{})[1].(obj)["doc_type"]="drawing"
    uploads:=data["uploads.json"].([]interface{});original:=uploads[0].(obj)
    switch variant {
     case "upload-thumbnails","upload-shared-thumb":
      thumb:=[]byte{0,255,13,10};files["uploads/thumbs/预览🙂.bin"]=thumb
      original["thumb_path"]="thumbs/预览🙂.bin";original["thumb_size"]=len(thumb)
      if variant=="upload-shared-thumb" {
       second:=clone(original).(obj);second["storage_path"]="editor/second.bin"
       files["uploads/editor/second.bin"]=files["uploads/"+original["storage_path"].(string)]
       uploads=append(uploads,second)
      }
     case "upload-large":
      large:=bytes.Repeat([]byte{0,255,13,10,1,2,3},1300000)
      files["uploads/"+original["storage_path"].(string)]=large
      original["file_size"]=len(large);original["file_hash"]=fmt.Sprintf("%x",sha256.Sum256(large))
     case "upload-original-thumb":
      original["thumb_path"]=original["storage_path"];original["thumb_size"]=original["file_size"]
     case "upload-empty":
      uploads=[]interface{}{};files=map[string][]byte{}
     case "upload-ambiguous-path":
      files["uploads/editor/a%2Fb.bin"]=files["uploads/"+original["storage_path"].(string)]
      delete(files,"uploads/"+original["storage_path"].(string));original["storage_path"]="editor/a%2Fb.bin"
    };data["uploads.json"]=uploads
   case "protected-native","protected-native-unicode","protected-plain-native":
    if len(vectors)<2{panic("synthetic Go crypto catalog argument required")}
    data["books.json"].([]interface{})[0].(obj)["documents"].([]interface{})[1].(obj)["doc_type"]="drawing"
    vector:=vectors[0];if variant=="protected-native-unicode"{vector=vectors[1]}
    note:=data["blogs.json"].([]interface{})[0].(obj)
    note["password"]=vector["hash"];note["blog_content"]=vector["body"]
    if variant=="protected-plain-native"{note["blog_content"]=vector["plain"]}
   case "known-formats":
    data["books.json"].([]interface{})[0].(obj)["documents"].([]interface{})[1].(obj)["doc_type"]="drawing"
   case "comment-targets":
    first["target_type"]="resource";first["target_id"]=6
    child["target_type"]="resource";child["target_id"]=6
    noIDComment["target_type"]="task";noIDComment["target_id"]=json.Number("9223372036854775807")
   case "forward-parents","forward-native":
    docs:=data["books.json"].([]interface{})[0].(obj)["documents"].([]interface{})
    data["books.json"].([]interface{})[0].(obj)["documents"]=[]interface{}{docs[1],docs[0]}
    values:=data["tasks.json"].([]interface{});data["tasks.json"]=[]interface{}{values[1],values[0]}
    topic["comments"]=[]interface{}{child,first,noIDComment}
    if variant=="forward-native"{data["books.json"].([]interface{})[0].(obj)["documents"].([]interface{})[0].(obj)["doc_type"]="drawing"}
   case "cross-topic":
    other:=clone(topic).(obj);other["topic_id"]=9;topics=append(topics,other);data["topics.json"]=topics
  }
  stats:=data["manifest.json"].(obj)["stats"].(obj)
  for _,kind:=range []string{"books","blogs","bookmarks","tasks","topics","friend_links"}{stats[kind]=len(data[kind+".json"].([]interface{}))}
  stats["uploads"]=len(data["uploads.json"].([]interface{}))
  documents:=0;for _,value:=range data["books.json"].([]interface{}){documents+=len(value.(obj)["documents"].([]interface{}))};stats["documents"]=documents
  out,e:=os.OpenFile("identity-"+variant+".zip",os.O_CREATE|os.O_EXCL|os.O_WRONLY,0600);if e!=nil{panic(e)}
  writer:=zip.NewWriter(out)
  names:=[]string{"manifest.json","books.json","blogs.json","bookmarks.json","tasks.json","topics.json","labels.json","friend_links.json","uploads.json"}
  if _,ok:=files["uploads/bytes.bin"];ok{names=append(names,"uploads/bytes.bin")}
  extra:=[]string{};for name:=range files{if name!="uploads/bytes.bin"{extra=append(extra,name)}};sort.Strings(extra);names=append(names,extra...)
  for _,name:=range names{
   h:=&zip.FileHeader{Name:name,Method:zip.Deflate};h.SetModTime(time.Date(2026,11,8,0,0,0,0,time.UTC))
   entry,e:=writer.CreateHeader(h);if e!=nil{panic(e)}
   if value,ok:=data[name];ok{if e=json.NewEncoder(entry).Encode(value);e!=nil{panic(e)}}else{if _,e=entry.Write(files[name]);e!=nil{panic(e)}}
  };if e=writer.Close();e!=nil{panic(e)};if e=out.Close();e!=nil{panic(e)}
 }
}
