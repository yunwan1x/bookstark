// Interoperability vectors only. Never imports or builds production BookStark.
package main
import (
 "crypto/aes"; "crypto/cipher"; "crypto/sha256"; "encoding/base64";
 "encoding/json"; "fmt"; "os"; "strings"; "bufio";
 "golang.org/x/crypto/bcrypt"; "golang.org/x/crypto/pbkdf2"
)
type vector struct {Name string `json:"name"`;Password string `json:"password"`;Hash string `json:"hash"`;Body string `json:"body"`;Plain string `json:"plain"`}
func encrypt(password,plain string) string {
 salt:=make([]byte,16); nonce:=make([]byte,12)
 for i:=range salt {salt[i]=byte(i+1)};for i:=range nonce {nonce[i]=byte(i+31)}
 key:=pbkdf2.Key([]byte(password),salt,100000,32,sha256.New)
 block,e:=aes.NewCipher(key);if e!=nil {panic(e)};gcm,e:=cipher.NewGCM(block);if e!=nil {panic(e)}
 return "ENC:v1:"+base64.StdEncoding.EncodeToString(salt)+":"+base64.StdEncoding.EncodeToString(nonce)+":"+base64.StdEncoding.EncodeToString(gcm.Seal(nil,nonce,[]byte(plain),nil))
}
func decrypt(password,body string) string {
 parts:=strings.Split(body,":");if len(parts)!=5 {panic("bad envelope")}
 decode:=func(s string) []byte {b,e:=base64.StdEncoding.DecodeString(s);if e!=nil {panic(e)};return b}
 salt,nonce,ct:=decode(parts[2]),decode(parts[3]),decode(parts[4])
 key:=pbkdf2.Key([]byte(password),salt,100000,32,sha256.New)
 block,e:=aes.NewCipher(key);if e!=nil {panic(e)};gcm,e:=cipher.NewGCM(block);if e!=nil {panic(e)}
 plain,e:=gcm.Open(nil,nonce,ct,nil);if e!=nil {panic(e)};return string(plain)
}
func boundedFile(path string, max int64) []byte {
 info,e:=os.Lstat(path);if e!=nil||!info.Mode().IsRegular()||info.Size()>max {panic("bounded synthetic input required")}
 data,e:=os.ReadFile(path);if e!=nil||int64(len(data))>max {panic("bounded synthetic read failed")};return data
}
func main() {
 if len(os.Args)==6 && os.Args[1]=="verify-files" {
  pw:=boundedFile(os.Args[2],4096);hash:=boundedFile(os.Args[3],60)
  body:=boundedFile(os.Args[4],28*1024*1024);expected:=boundedFile(os.Args[5],20*1024*1024)
  if e:=bcrypt.CompareHashAndPassword(hash,pw);e!=nil {panic("synthetic bcrypt mismatch")}
  actual:=decrypt(string(pw),string(body))
  if actual!=string(expected) {panic("synthetic maximum-size plaintext mismatch")}
  sum:=sha256.Sum256([]byte(actual))
  value,e:=json.Marshal(map[string]interface{}{"passed":true,"javaToGoFiles":1,"plaintextBytes":len(actual),"plaintextSHA256":fmt.Sprintf("%x",sum),"syntheticDataOnly":true})
  if e!=nil {panic(e)};fmt.Println(string(value));return
 }

 if len(os.Args)>1 && os.Args[1]=="verify-java" {
  file,e:=os.Open(os.Args[2]);if e!=nil {panic(e)};defer file.Close()
  scanner:=bufio.NewScanner(file);scanner.Buffer(make([]byte,4096),16*1024*1024)
  count:=0
  for scanner.Scan() {
   fields:=strings.Split(scanner.Text(),"\t");if len(fields)!=5 {panic("bad Java vector")}
   decode:=func(s string) string {b,e:=base64.StdEncoding.DecodeString(s);if e!=nil {panic(e)};return string(b)}
   pw,hash,body,plain:=decode(fields[1]),decode(fields[2]),decode(fields[3]),decode(fields[4])
   if e=bcrypt.CompareHashAndPassword([]byte(hash),[]byte(pw));e!=nil {panic("Java bcrypt mismatch")}
   if decrypt(pw,body)!=plain {panic("Java AES/PBKDF2 mismatch")}
   count++
  }
  if e=scanner.Err();e!=nil {panic(e)}
  encoded,e:=json.Marshal(map[string]interface{}{"passed":true,"javaToGoVectors":count,"syntheticDataOnly":true});if e!=nil {panic(e)}
  fmt.Println(string(encoded));return
 }
 vectors:=[]vector{
  {Name:"ascii",Password:"synthetic-password",Plain:"\ufeff# exact\r\nline\r\n"},
  {Name:"unicode",Password:"中文😀 e\u0301",Plain:"\ufeff原文😀\r\n<未知>\n"},
  {Name:"nul-password",Password:"a\x00b密码",Plain:"embedded\x00body\r\n"},
  {Name:"empty-body",Password:"synthetic-empty-body",Plain:""},
  {Name:"72-byte-password",Password:strings.Repeat("x",72),Plain:"limit"},
  {Name:"legacy-long-password",Password:strings.Repeat("x",73),Plain:"full password used for PBKDF2"},
 }
 for i:=range vectors {
  pw:=vectors[i].Password
  hashPW:=pw;if len(hashPW)>72 {hashPW=hashPW[:72]}
  hash,e:=bcrypt.GenerateFromPassword([]byte(hashPW),bcrypt.DefaultCost);if e!=nil {panic(e)}
  vectors[i].Hash=string(hash);vectors[i].Body=encrypt(pw,vectors[i].Plain)
  if e=bcrypt.CompareHashAndPassword(hash,[]byte(pw));e!=nil {panic(e)}
  if decrypt(pw,vectors[i].Body)!=vectors[i].Plain {panic("self-check failed")}
 }
 for _,minor:=range []string{"2b","2y"} {
  copy:=vectors[1];copy.Name=minor+"-unicode";copy.Hash="$"+minor+"$"+copy.Hash[4:]
  if e:=bcrypt.CompareHashAndPassword([]byte(copy.Hash),[]byte(copy.Password));e!=nil {panic(e)}
  vectors=append(vectors,copy)
 }
 out,e:=os.Create("go-vectors.tsv");if e!=nil {panic(e)}
 enc:=base64.StdEncoding.EncodeToString
 for _,v:=range vectors {fmt.Fprintln(out,strings.Join([]string{v.Name,enc([]byte(v.Password)),enc([]byte(v.Hash)),enc([]byte(v.Body)),enc([]byte(v.Plain))},"\t"))}
 if e=out.Close();e!=nil {panic(e)}
 bytes,e:=json.MarshalIndent(vectors,"","  ");if e!=nil {panic(e)}
 if e=os.WriteFile("go-vectors.json",append(bytes,'\n'),0600);e!=nil {panic(e)}
 fmt.Printf("Generated and Go-self-verified %d synthetic vectors\n",len(vectors))
}
