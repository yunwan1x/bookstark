//go:build ignore

// Standalone fixture generator: standard library only; never builds BookStark.
package main
import ("archive/zip"; "os"; "time")
func main() {
 f,e:=os.Create(os.Args[1]); if e!=nil {panic(e)}
 z:=zip.NewWriter(f)
 for _,entry:=range []struct{name,body string;method uint16}{
  {"manifest.json","{\"version\":1,\"source\":\"bookstark\"}",zip.Deflate},
  {"blogs.json","[{\"blog_content\":\"\\ufeff# text\\r\\n\"}]",zip.Deflate},
  {"uploads/","",zip.Store},
  {"uploads/资料.txt","exact attachment\r\n",zip.Store},
 } {
  h:=&zip.FileHeader{Name:entry.name, Method:entry.method}
  h.SetModTime(time.Date(2026,11,8,0,0,0,0,time.UTC))
  w,e:=z.CreateHeader(h);if e!=nil {panic(e)}
  if _,e=w.Write([]byte(entry.body));e!=nil {panic(e)}
 }
 if e=z.Close();e!=nil {panic(e)};if e=f.Close();e!=nil {panic(e)}
 for _, fixture := range []struct{name string; paths []string}{
  {"case-alias.zip", []string{"first.json","FIRST.JSON"}},
  {"parent-file.zip", []string{"root","root/file.json"}},
 } {
  out,e:=os.Create(fixture.name);if e!=nil {panic(e)}
  archive:=zip.NewWriter(out)
  for _,path:=range fixture.paths {
   header:=&zip.FileHeader{Name:path,Method:zip.Deflate}
   header.SetModTime(time.Date(2026,11,8,0,0,0,0,time.UTC))
   entry,e:=archive.CreateHeader(header);if e!=nil {panic(e)}
   if _,e=entry.Write([]byte("{}"));e!=nil {panic(e)}
  }
  if e=archive.Close();e!=nil {panic(e)}
  if e=out.Close();e!=nil {panic(e)}
 }
}
