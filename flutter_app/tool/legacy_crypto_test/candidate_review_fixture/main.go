
// Deterministic synthetic fixture only. Never a production encryption utility.
package main
import("archive/zip";"os";"io";"bytes";"encoding/json";"time";"fmt";"image";"image/color";"image/png";
 "crypto/sha256";"crypto/aes";"crypto/cipher";"encoding/base64";"golang.org/x/crypto/pbkdf2")
func main(){
 input,e:=zip.OpenReader(os.Args[1]);if e!=nil{panic(e)};defer input.Close()
 original:=map[string]any{}
 for _,file:=range input.File{
  if file.Name=="manifest.json"||file.Name=="blogs.json"||file.Name=="uploads.json"{
   stream,e:=file.Open();if e!=nil{panic(e)};raw,e:=io.ReadAll(stream);stream.Close();if e!=nil{panic(e)}
   decoder:=json.NewDecoder(bytes.NewReader(raw));decoder.UseNumber();var value any
   if e=decoder.Decode(&value);e!=nil{panic(e)};original[file.Name]=value
  }
 }
 vectorsRaw,e:=os.ReadFile(os.Args[2]);if e!=nil{panic(e)}
 var vectors []map[string]string;if e=json.Unmarshal(vectorsRaw,&vectors);e!=nil{panic(e)}
 pw,hash:=vectors[0]["password"],vectors[0]["hash"]
 img:=image.NewRGBA(image.Rect(0,0,32,32))
 for y:=0;y<32;y++{for x:=0;x<32;x++{img.SetRGBA(x,y,color.RGBA{0,180,70,255})}}
 var picture bytes.Buffer;if e=png.Encode(&picture,img);e!=nil{panic(e)}
 plain:="<h1>周末计划</h1><h2>周六</h2><p>早上去湖边散步</p><p>下午整理旅行照片</p><h2>周日</h2><p>留出时间阅读和休息</p><img alt=\"副本图片\" src=\"/upload-files/images/green.png\" width=\"96\">"
 salt,nonce:=make([]byte,16),make([]byte,12)
 for i:=range salt{salt[i]=byte(i+1)};for i:=range nonce{nonce[i]=byte(i+31)}
 key:=pbkdf2.Key([]byte(pw),salt,100000,32,sha256.New);block,e:=aes.NewCipher(key);if e!=nil{panic(e)}
 gcm,e:=cipher.NewGCM(block);if e!=nil{panic(e)}
 ct:=gcm.Seal(nil,nonce,[]byte(plain),nil);check,e:=gcm.Open(nil,nonce,ct,nil)
 if e!=nil||string(check)!=plain{panic("synthetic self-check failed")}
 enc:=base64.StdEncoding.EncodeToString
 protected:="ENC:v1:"+enc(salt)+":"+enc(nonce)+":"+enc(ct)
 base:=original["blogs.json"].([]any)[0].(map[string]any)
 blogs:=[]map[string]any{}
 for i:=0;i<3;i++{
  row:=map[string]any{};for k,v:=range base{row[k]=v}
  row["blog_title"]=[]string{"旅行计划","项目草稿","周末随笔"}[i]
  row["blog_identify"]=[]string{"candidate-travel","candidate-draft","candidate-weekend"}[i]
  row["blog_type"]="note";row["password"]="";row["modify_time"]=[]string{"2026-11-09T12:00:00Z","2026-11-09T11:00:00Z","2026-11-09T10:00:00Z"}[i]
  if i==0{row["password"]=hash;row["blog_content"]=protected}
  if i==1{row["blog_content"]="# 项目草稿\n\n只读审阅，不会修改原文。\n\n![副本图片](/upload-files/images/green.png)\n"}
  if i==2{row["blog_type"]="article";row["blog_content"]="<h1>周末随笔</h1><p>只读文章正文</p>"}
  blogs=append(blogs,row)
 }
 upload:=original["uploads.json"].([]any)[0].(map[string]any)
 upload["storage_path"]="images/green.png";upload["file_name"]="green.png";upload["file_size"]=picture.Len()
 upload["thumb_path"]="";upload["thumb_size"]=0;upload["width"]=32;upload["height"]=32;upload["mime_type"]="image/png"
 sum:=sha256.Sum256(picture.Bytes());upload["file_hash"]=fmt.Sprintf("%x",sum)
 manifest:=original["manifest.json"].(map[string]any)
 stats:=map[string]int{"blogs":3,"books":0,"documents":0,"bookmarks":0,"tasks":0,"topics":0,"labels":0,"friend_links":0,"uploads":1}
 manifest["stats"]=stats
 sections:=map[string]any{"manifest.json":manifest,"blogs.json":blogs,"books.json":[]any{},"bookmarks.json":[]any{},
 "tasks.json":[]any{},"topics.json":[]any{},"friend_links.json":[]any{},"labels.json":map[string]any{"labels":[]any{},"relations":[]any{}},
 "uploads.json":[]any{upload}}
 out,e:=os.Create(os.Args[3]);if e!=nil{panic(e)};writer:=zip.NewWriter(out)
 names:=[]string{"manifest.json","blogs.json","books.json","bookmarks.json","tasks.json","topics.json","friend_links.json","labels.json","uploads.json"}
 for _,name:=range append(names,"uploads/images/green.png"){
  var raw []byte
  if name=="uploads/images/green.png"{raw=picture.Bytes()}else{raw,e=json.MarshalIndent(sections[name],"","  ");if e!=nil{panic(e)}}
  header:=zip.FileHeader{Name:name,Method:zip.Deflate};header.SetModTime(time.Date(2026,11,9,0,0,0,0,time.UTC))
  entry,e:=writer.CreateHeader(&header);if e!=nil{panic(e)};if _,e=entry.Write(raw);e!=nil{panic(e)}
 }
 if e=writer.Close();e!=nil{panic(e)};if e=out.Close();e!=nil{panic(e)}
 fmt.Println("PASS actual Go review fixture:2notes/1article/1protected/1PNG; no password output")
}
