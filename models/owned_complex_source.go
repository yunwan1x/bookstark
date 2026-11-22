package models

import (
 "bytes"
 "compress/gzip"
 "context"
 "crypto/sha256"
 "database/sql"
 "encoding/base64"
 "encoding/hex"
 "encoding/json"
 "errors"
 "fmt"
 "io"
 "regexp"
 "strings"
 "time"
 "unicode/utf16"
 "unicode/utf8"
)

var ErrOwnedComplexDenied = errors.New("owned complex resource unavailable")
var ErrOwnedComplexLocked = errors.New("protected complex resource")
var ErrOwnedComplexLimit = errors.New("owned complex resource exceeds bound")
var ErrOwnedComplexFormat = errors.New("invalid owned complex format")
var ErrOwnedComplexConflict = errors.New("owned complex source changed")
type OwnedComplexIdentity struct { Resource string; ID,BookID,MemberID int64; Kind string }
type OwnedComplexSnapshot struct {
 Resource string `json:"resource"`
 ID int64 `json:"id"`; BookID int64 `json:"book_id"`; MemberID int64 `json:"member_id"`
 Kind string `json:"kind"`; Title string `json:"title"`; Labels []string `json:"labels"`
 Fingerprint string `json:"resource_fp"`; Source string `json:"source_base64"`
 Bytes int `json:"bytes"`; SHA256 string `json:"sha256"`
 metadata map[string]any
 stored,plain string
}
func ownedComplexLimit(kind string) int {
 switch kind {case "presentation":return 20*1024*1024
 case "html","spreadsheet","drawing","mindmap","richdoc":return 5*1024*1024}
 return 0
}
func ownedComplexDigest(data []byte)string{ sum:=sha256.Sum256(data);return hex.EncodeToString(sum[:]) }
func ownedProtected(source string)bool{return strings.HasPrefix(strings.TrimPrefix(source,"\uFEFF"),"ENC:")}
func ownedDecode(kind,stored string)(string,error){
 if len(stored)>32*1024*1024{return "",ErrOwnedComplexLimit}
 if ownedProtected(stored){return "",ErrOwnedComplexLocked}
 source:=stored
 if kind=="html" || kind=="richdoc" {
  if strings.HasPrefix(stored,"CMP:") && !strings.HasPrefix(stored,compressedContentPrefix){return "",ErrOwnedComplexDenied}
  if strings.HasPrefix(stored,compressedContentPrefix){
   encoded:=strings.TrimPrefix(stored,compressedContentPrefix)
   if base64.StdEncoding.DecodedLen(len(encoded))>32*1024*1024{return "",ErrOwnedComplexLimit}
   data,err:=base64.StdEncoding.Strict().DecodeString(encoded);if err!=nil{return "",err}
   reader,err:=gzip.NewReader(bytes.NewReader(data));if err!=nil{return "",err}
   defer reader.Close()
   plain,err:=io.ReadAll(io.LimitReader(reader,int64(ownedComplexLimit(kind))+1));if err!=nil{return "",err}
   if len(plain)>ownedComplexLimit(kind){return "",ErrOwnedComplexLimit}
   source=string(plain)
  }
 }
 if len(source)>ownedComplexLimit(kind){return "",ErrOwnedComplexLimit}
 if ownedProtected(source){return "",ErrOwnedComplexLocked}
 if err:=validateOwnedComplexSource(kind,source);err!=nil{return "",err}
 return source,nil
}
func ownedEncode(kind,source string)(string,error){
 if kind!="html" && kind!="richdoc"{return source,nil}
 // Always compress plaintext, including literal CMP-looking source; never
 // pass it through the legacy already-compressed shortcut.
 var output bytes.Buffer
 writer:=gzip.NewWriter(&output)
 if _,err:=writer.Write([]byte(source));err!=nil{return "",err}
 if err:=writer.Close();err!=nil{return "",err}
 return compressedContentPrefix+base64.StdEncoding.EncodeToString(output.Bytes()),nil
}
func validateOwnedComplexSource(kind,source string)error{
 limit:=ownedComplexLimit(kind)
 if limit==0 || len(source)>limit || !utf8.ValidString(source){return ErrOwnedComplexLimit}
 if ownedProtected(source){return ErrOwnedComplexLocked}
 if kind=="html"{return nil}
 // Check depth and escaped UTF16 before Go's JSON decoder can replace malformed
 // surrogate escapes. Source itself is retained verbatim, never reserialized.
 quoted,escaped,depth:=false,false,0
 for i:=0;i<len(source);i++{
  c:=source[i]
  if quoted {
   if escaped {escaped=false;continue}
   if c=='\\' {
    if i+1<len(source) && source[i+1]=='u'{
     if i+6>len(source){return ErrOwnedComplexDenied}
     var hi uint16
     if _,err:=fmt.Sscanf(source[i+2:i+6],"%04x",&hi);err!=nil{return err}
     if utf16.IsSurrogate(rune(hi)){
      if hi<0xD800 || hi>0xDBFF || i+12>len(source) || source[i+6:i+8]!="\\u"{return ErrOwnedComplexDenied}
      var lo uint16
      if _,err:=fmt.Sscanf(source[i+8:i+12],"%04x",&lo);err!=nil || lo<0xDC00 || lo>0xDFFF{return ErrOwnedComplexDenied}
      i+=11
     }else{i+=5}
    }else{escaped=true}
   }else if c=='"'{quoted=false}
  }else if c=='"'{quoted=true}else if c=='{' || c=='['{depth++;if depth>64{return ErrOwnedComplexLimit}}else if c=='}' || c==']'{depth--}
 }
 var value any
 if err:=json.Unmarshal([]byte(source),&value);err!=nil{return err}
 object,_:=value.(map[string]any)
 switch kind{
 case "spreadsheet":
  order,ok:=object["sheetOrder"].([]any);sheets,_:=object["sheets"].(map[string]any)
  if !ok || len(order)==0 || sheets==nil{return ErrOwnedComplexDenied}
  for _,id:=range order{key,ok:=id.(string);if !ok || key=="" || sheets[key]==nil{return ErrOwnedComplexDenied}}
 case "drawing":
  elements,ok:=value.([]any);if !ok{elements,ok=object["elements"].([]any)}
  if !ok{return ErrOwnedComplexDenied};for _,element:=range elements{if _,ok:=element.(map[string]any);!ok{return ErrOwnedComplexDenied}}
 case "mindmap":
  node,_:=object["nodeData"].(map[string]any);id,ok:=node["id"].(string);if !ok || id==""{return ErrOwnedComplexDenied}
  if _,ok:=node["topic"].(string);!ok{return ErrOwnedComplexDenied}
 case "richdoc":return ValidateRichDocument(source)
 case "presentation":return ValidatePresentation(source)
 default:return ErrOwnedComplexDenied
 }
 return nil
}
var ownedSQLName=regexp.MustCompile("^[a-z_][a-z0-9_]*$")
func ownedColumns(ctx context.Context,tx *sql.Tx,table,body string)([]string,error){
 if table!="md_blogs" && table!="md_documents"{return nil,ErrOwnedComplexDenied}
 rows,err:=tx.QueryContext(ctx,"PRAGMA table_info("+table+")");if err!=nil{return nil,err};defer rows.Close()
 var columns []string
 for rows.Next(){
  var cid,notnull,pk int;var name,kind string;var def any
  if err:=rows.Scan(&cid,&name,&kind,&notnull,&def,&pk);err!=nil{return nil,err}
  if !ownedSQLName.MatchString(name){return nil,ErrOwnedComplexDenied}
  if name!=body && name!="password"{columns=append(columns,name)}
  if len(columns)>128{return nil,ErrOwnedComplexLimit}
 }
 if err:=rows.Err();err!=nil{return nil,err}
 if len(columns)==0{return nil,ErrOwnedComplexDenied};return columns,nil
}
func ownedMetadata(ctx context.Context,tx *sql.Tx,table,body,where string,args []any)(map[string]any,string,error){
 columns,err:=ownedColumns(ctx,tx,table,body);if err!=nil{return nil,"",err}
 lengths:=[]string{}
 for _,column:=range columns{lengths=append(lengths,"COALESCE(length(CAST("+column+" AS BLOB)),0)")}
 var bodyBytes,metadataBytes int64
 if err:=tx.QueryRowContext(ctx,"SELECT COALESCE(length(CAST("+body+" AS BLOB)),0),"+strings.Join(lengths,"+")+" FROM "+table+" WHERE "+where,args...).Scan(&bodyBytes,&metadataBytes);err!=nil{return nil,"",err}
 if bodyBytes>32*1024*1024 || metadataBytes>128*1024{return nil,"",ErrOwnedComplexLimit}
 names:=append(append([]string{},columns...),body)
 values:=make([]any,len(names));refs:=make([]any,len(names));for i:=range values{refs[i]=&values[i]}
 if err:=tx.QueryRowContext(ctx,"SELECT "+strings.Join(names,",")+" FROM "+table+" WHERE "+where,args...).Scan(refs...);err!=nil{return nil,"",err}
 result:=map[string]any{}
 for i,column:=range names{
  value:=values[i]
  if data,ok:=value.([]byte);ok{if !utf8.Valid(data){return nil,"",ErrOwnedComplexDenied};value=string(data)}
  if text,ok:=value.(string);ok && !utf8.ValidString(text){return nil,"",ErrOwnedComplexDenied}
  result[column]=value
 }
 stored,_:=result[body].(string);if result[body]!=nil && result[body]!=stored{return nil,"",ErrOwnedComplexDenied}
 result["_source_storage_null"]=result[body]==nil
 delete(result,body)
 if deleted,ok:=result["deleted"].(int64);ok && deleted!=0{return nil,"",ErrOwnedComplexDenied}
 return result,stored,nil
}
func ownedLabels(ctx context.Context,tx *sql.Tx,id int64,relation string)([]string,[]any,error){
 rows,err:=tx.QueryContext(ctx,"SELECT r.id,r.label_id,CASE WHEN length(CAST(l.label_name AS BLOB))<=65536 THEN l.label_name ELSE NULL END FROM md_label_relation r LEFT JOIN md_label l ON l.label_id=r.label_id WHERE r.resource_id=? AND r.relation_type=? ORDER BY r.id LIMIT 101",id,relation)
 if err!=nil{return nil,nil,err};defer rows.Close()
 labels:=[]string{};relations:=[]any{};bytes:=0
 for rows.Next(){var rid,lid int64;var name string;if err:=rows.Scan(&rid,&lid,&name);err!=nil{return nil,nil,err}
  bytes+=len(name);if len(labels)>=100 || bytes>60*1024 || !utf8.ValidString(name){return nil,nil,ErrOwnedComplexLimit}
  labels=append(labels,name);relations=append(relations,[]any{rid,lid,name})
 }
 return labels,relations,rows.Err()
}
func readOwnedComplexTx(ctx context.Context,tx *sql.Tx,key OwnedComplexIdentity)(*OwnedComplexSnapshot,error){
 if key.ID<=0 || key.MemberID<=0 || ownedComplexLimit(key.Kind)==0{return nil,ErrOwnedComplexDenied}
 table,body,where,relation:="","","",""
 args:=[]any{}
 bookProof:=[]any{}
 switch key.Resource{
 case "remote-note":
  if key.BookID!=0{return nil,ErrOwnedComplexDenied}
  table,body,where,relation="md_blogs","blog_content","blog_id=? AND member_id=? AND blog_type='note' AND editor_type=? AND COALESCE(password,'')=''","blog"
  args=[]any{key.ID,key.MemberID,key.Kind}
  // Return locked, without body, for an owned protected note.
  var protected int
  if err:=tx.QueryRowContext(ctx,"SELECT CASE WHEN COALESCE(password,'')<>'' THEN 1 ELSE 0 END FROM md_blogs WHERE blog_id=? AND member_id=?",key.ID,key.MemberID).Scan(&protected);err!=nil{return nil,err}
  if protected!=0{return nil,ErrOwnedComplexLocked}
 case "remote-book-document":
  if key.BookID<=0{return nil,ErrOwnedComplexDenied}
  var identify string
  if err:=tx.QueryRowContext(ctx,"SELECT identify FROM md_books WHERE book_id=? AND member_id=?",key.BookID,key.MemberID).Scan(&identify);err!=nil{return nil,err}
  if len(identify)>65536 || !utf8.ValidString(identify){return nil,ErrOwnedComplexLimit}
  bookProof=[]any{key.BookID,key.MemberID,identify}
  table,body,where,relation="md_documents","markdown","document_id=? AND book_id=? AND member_id=? AND doc_type=?","document"
  args=[]any{key.ID,key.BookID,key.MemberID,key.Kind}
 default:return nil,ErrOwnedComplexDenied
 }
 metadata,stored,err:=ownedMetadata(ctx,tx,table,body,where,args);if err!=nil{return nil,err}
 plain,err:=ownedDecode(key.Kind,stored);if err!=nil{if errors.Is(err,ErrOwnedComplexLocked) || errors.Is(err,ErrOwnedComplexLimit){return nil,err};return nil,ErrOwnedComplexFormat}
 labels,relations,err:=ownedLabels(ctx,tx,key.ID,relation);if err!=nil{return nil,err}
 fingerprintInput:=[]any{"owned-complex-v1",key.Resource,key.ID,key.BookID,key.MemberID,key.Kind,bookProof,metadata,relations,ownedComplexDigest([]byte(stored)),ownedComplexDigest([]byte(plain))}
 encoded,err:=json.Marshal(fingerprintInput);if err!=nil{return nil,err}
 titleKey:="blog_title";if key.Resource=="remote-book-document"{titleKey="document_name"}
 title,ok:=metadata[titleKey].(string);if !ok || len(title)>65536{return nil,ErrOwnedComplexDenied}
 return &OwnedComplexSnapshot{Resource:key.Resource,ID:key.ID,BookID:key.BookID,MemberID:key.MemberID,Kind:key.Kind,Title:title,Labels:labels,
  Fingerprint:ownedComplexDigest(encoded),Source:base64.StdEncoding.EncodeToString([]byte(plain)),Bytes:len(plain),SHA256:ownedComplexDigest([]byte(plain)),metadata:metadata,stored:stored,plain:plain},nil
}
func ReadOwnedComplexSource(ctx context.Context,key OwnedComplexIdentity)(*OwnedComplexSnapshot,error){
 tx,err:=DB.BeginTx(ctx,nil);if err!=nil{return nil,err};defer tx.Rollback()
 result,err:=readOwnedComplexTx(ctx,tx,key);if err!=nil{return nil,err}
 if err:=tx.Commit();err!=nil{return nil,err};return result,nil
}
type OwnedComplexMetadata struct {Title string; Labels []string}
func sameOwnedLabels(a,b []string)bool{if len(a)!=len(b){return false};for i:=range a{if a[i]!=b[i]{return false}};return true}
func validateOwnedMetadata(metadata *OwnedComplexMetadata)error{
 if metadata==nil{return nil}
 if !utf8.ValidString(metadata.Title) || strings.TrimSpace(metadata.Title)=="" || len(metadata.Title)>200 || len(metadata.Labels)>100{return ErrOwnedComplexFormat}
 seen:=map[string]bool{}
 for _,label:=range metadata.Labels{if label=="" || !utf8.ValidString(label) || seen[label]{return ErrOwnedComplexFormat};seen[label]=true}
 encoded,err:=json.Marshal(metadata.Labels);if err!=nil || len(encoded)>60*1024{return ErrOwnedComplexLimit}
 return nil
}
func replaceOwnedNoteLabels(ctx context.Context,tx *sql.Tx,id int64,labels []string)error{
 if _,err:=tx.ExecContext(ctx,"DELETE FROM md_label_relation WHERE resource_id=? AND relation_type='blog'",id);err!=nil{return err}
 for _,name:=range labels{
  if _,err:=tx.ExecContext(ctx,"INSERT OR IGNORE INTO md_label(label_name) VALUES(?)",name);err!=nil{return err}
  var labelID int64
  if err:=tx.QueryRowContext(ctx,"SELECT label_id FROM md_label WHERE label_name=?",name).Scan(&labelID);err!=nil{return err}
  if _,err:=tx.ExecContext(ctx,"INSERT INTO md_label_relation(label_id,resource_id,relation_type) VALUES(?,?,'blog')",labelID,id);err!=nil{return err}
 }
 return nil
}
func SaveOwnedComplexSource(ctx context.Context,key OwnedComplexIdentity,expected,source string)(*OwnedComplexSnapshot,error){
 return SaveOwnedComplexEdit(ctx,key,expected,source,nil)
}
func SaveOwnedComplexEdit(ctx context.Context,key OwnedComplexIdentity,expected,source string,metadata *OwnedComplexMetadata)(*OwnedComplexSnapshot,error){
 if metadata!=nil && key.Resource!="remote-note"{return nil,ErrOwnedComplexFormat}
 if err:=validateOwnedMetadata(metadata);err!=nil{return nil,err}
 if !regexp.MustCompile("^[a-f0-9]{64}$").MatchString(expected){return nil,ErrOwnedComplexDenied}
 if err:=validateOwnedComplexSource(key.Kind,source);err!=nil{if errors.Is(err,ErrOwnedComplexLocked) || errors.Is(err,ErrOwnedComplexLimit){return nil,err};return nil,ErrOwnedComplexFormat}
 tx,err:=DB.BeginTx(ctx,nil);if err!=nil{return nil,err};defer tx.Rollback()
 actual,err:=readOwnedComplexTx(ctx,tx,key);if err!=nil{return nil,err}
 if actual.Fingerprint!=expected{return nil,ErrOwnedComplexConflict}
 metadataChanged:=metadata!=nil && (actual.Title!=metadata.Title || !sameOwnedLabels(actual.Labels,metadata.Labels))
 if actual.plain!=source || metadataChanged{
  encoded:=actual.stored
  if actual.plain!=source{encoded,err=ownedEncode(key.Kind,source);if err!=nil{return nil,err}}
  now:=time.Now().UTC()
  var result sql.Result
  if key.Resource=="remote-note"{
   if metadataChanged && actual.plain==source{
    result,err=tx.ExecContext(ctx,"UPDATE md_blogs SET blog_title=?,modify_time=?,modify_at=?,version=version+1 WHERE blog_id=? AND member_id=? AND blog_type='note' AND editor_type=? AND COALESCE(password,'')='' AND COALESCE(CAST(blog_content AS BLOB),X'')=?",metadata.Title,now,key.MemberID,key.ID,key.MemberID,key.Kind,[]byte(actual.stored))
   }else if metadataChanged{
    result,err=tx.ExecContext(ctx,"UPDATE md_blogs SET blog_content=?,blog_title=?,modify_time=?,modify_at=?,version=version+1 WHERE blog_id=? AND member_id=? AND blog_type='note' AND editor_type=? AND COALESCE(password,'')='' AND COALESCE(CAST(blog_content AS BLOB),X'')=?",encoded,metadata.Title,now,key.MemberID,key.ID,key.MemberID,key.Kind,[]byte(actual.stored))
   }else{
   result,err=tx.ExecContext(ctx,"UPDATE md_blogs SET blog_content=?,modify_time=?,modify_at=?,version=version+1 WHERE blog_id=? AND member_id=? AND blog_type='note' AND editor_type=? AND COALESCE(password,'')='' AND COALESCE(CAST(blog_content AS BLOB),X'')=?",encoded,now,key.MemberID,key.ID,key.MemberID,key.Kind,[]byte(actual.stored))
   }
  }else{
   result,err=tx.ExecContext(ctx,"UPDATE md_documents SET markdown=?,modify_time=?,modify_at=? WHERE document_id=? AND book_id=? AND member_id=? AND doc_type=? AND COALESCE(CAST(markdown AS BLOB),X'')=?",encoded,now,key.MemberID,key.ID,key.BookID,key.MemberID,key.Kind,[]byte(actual.stored))
  }
  if err!=nil{return nil,err};count,err:=result.RowsAffected();if err!=nil || count!=1{return nil,ErrOwnedComplexConflict}
  if metadataChanged && !sameOwnedLabels(actual.Labels,metadata.Labels){
   if err:=replaceOwnedNoteLabels(ctx,tx,key.ID,metadata.Labels);err!=nil{return nil,err}
  }
 }
 saved,err:=readOwnedComplexTx(ctx,tx,key);if err!=nil{return nil,err}
 if saved.plain!=source || metadata!=nil && (saved.Title!=metadata.Title || !sameOwnedLabels(saved.Labels,metadata.Labels)){return nil,ErrOwnedComplexConflict}
 if err:=tx.Commit();err!=nil{return nil,err};return saved,nil
}
