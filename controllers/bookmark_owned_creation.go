package controllers

import (
 "bytes"
 "database/sql"
 "encoding/json"
 "errors"
 "io"
 "net/http"
 "strconv"
 "unicode/utf8"
 "github.com/gin-gonic/gin"
 "bookstark/middleware"
 "bookstark/models"
)

// encoding/json replaces unpaired escaped surrogates. Reject them before decode
// instead of silently changing a persisted title, URL, description or label.
func validBookmarkCreationJSONUnicode(raw []byte)bool{
 if !utf8.Valid(raw){return false}
 inside:=false
 for i:=0;i<len(raw);i++{
  if raw[i]=='"'{inside=!inside;continue}
  if !inside||raw[i]!='\\'{continue}
  i++;if i>=len(raw){return false}
  if raw[i]!='u'{continue}
  if i+4>=len(raw){return false}
  unit,err:=strconv.ParseUint(string(raw[i+1:i+5]),16,16);if err!=nil{return false}
  i+=4
  if unit>=0xd800&&unit<=0xdbff{
   if i+6>=len(raw)||raw[i+1]!='\\'||raw[i+2]!='u'{return false}
   low,e:=strconv.ParseUint(string(raw[i+3:i+7]),16,16)
   if e!=nil||low<0xdc00||low>0xdfff{return false};i+=6
  }else if unit>=0xdc00&&unit<=0xdfff{return false}
 }
 return !inside
}
func decodeBookmarkCreationFields(c *gin.Context,limit int64,names []string)(map[string]json.RawMessage,error){
 raw,err:=io.ReadAll(http.MaxBytesReader(c.Writer,c.Request.Body,limit))
 if err!=nil||!validBookmarkCreationJSONUnicode(raw){return nil,models.ErrOwnedBookmarkInput}
 allowed:=map[string]bool{};for _,name:=range names{allowed[name]=true}
 d:=json.NewDecoder(bytes.NewReader(raw))
 token,err:=d.Token();if err!=nil||token!=json.Delim('{'){return nil,models.ErrOwnedBookmarkInput}
 fields:=map[string]json.RawMessage{}
 for d.More(){
  token,err=d.Token();if err!=nil{return nil,models.ErrOwnedBookmarkInput}
  key,ok:=token.(string);if !ok||!allowed[key]||fields[key]!=nil{return nil,models.ErrOwnedBookmarkInput}
  var value json.RawMessage
  if err=d.Decode(&value);err!=nil||bytes.Equal(bytes.TrimSpace(value),[]byte("null")){return nil,models.ErrOwnedBookmarkInput}
  fields[key]=value
 }
 token,err=d.Token();if err!=nil||token!=json.Delim('}')||len(fields)!=len(names){return nil,models.ErrOwnedBookmarkInput}
 var extra interface{}
 if err=d.Decode(&extra);err!=io.EOF{return nil,models.ErrOwnedBookmarkInput}
 return fields,nil
}
func ownedBookmarkCreationError(c *gin.Context,err error){
 if errors.Is(err,models.ErrOwnedBookmarkDuplicate){apiError(c,http.StatusConflict,"Bookmark URL already exists; explicitly review the existing resource");return}
 if errors.Is(err,models.ErrOwnedBookmarkInput){apiError(c,http.StatusBadRequest,"Invalid bounded bookmark input");return}
 if errors.Is(err,sql.ErrNoRows){apiError(c,http.StatusNotFound,"Owned bookmark unavailable");return}
 if errors.Is(err,models.ErrOwnedBookmarkReadBound){apiError(c,http.StatusRequestEntityTooLarge,"Owned bookmark exceeds recovery bounds");return}
 apiError(c,http.StatusInternalServerError,"Owned bookmark operation unavailable")
}
func CreateOwnedBookmarkAPI(c *gin.Context){
 fields,err:=decodeBookmarkCreationFields(c,512*1024,[]string{"title","url","description","favicon","is_public","labels"})
 if err!=nil{ownedBookmarkCreationError(c,err);return}
 var in models.OwnedBookmarkCreationInput
 for _,field:=range []struct{key string;value interface{}}{
  {"title",&in.Title},{"url",&in.URL},{"description",&in.Description},
  {"favicon",&in.Favicon},{"is_public",&in.IsPublic},{"labels",&in.Labels},
 }{
  if err=json.Unmarshal(fields[field.key],field.value);err!=nil{ownedBookmarkCreationError(c,models.ErrOwnedBookmarkInput);return}
 }
 if in.Labels==nil{ownedBookmarkCreationError(c,models.ErrOwnedBookmarkInput);return}
 row,err:=models.CreateOwnedBookmarkAtomic(in,middleware.GetMemberID(c))
 if err!=nil{ownedBookmarkCreationError(c,err);return}
 apiSuccess(c,row)
}
func CheckOwnedBookmarkCreationAPI(c *gin.Context){
 fields,err:=decodeBookmarkCreationFields(c,16*1024,[]string{"url"})
 if err!=nil{ownedBookmarkCreationError(c,err);return}
 var value string
 if err=json.Unmarshal(fields["url"],&value);err!=nil{ownedBookmarkCreationError(c,models.ErrOwnedBookmarkInput);return}
 row,err:=models.CheckOwnedBookmarkCreationURL(value,middleware.GetMemberID(c))
 if err!=nil{ownedBookmarkCreationError(c,err);return}
 apiSuccess(c,gin.H{"found":row!=nil,"bookmark":row})
}
func ReadOwnedBookmarkCreationAPI(c *gin.Context){
 id,err:=strconv.ParseInt(c.Param("id"),10,64)
 if err!=nil||id<=0{ownedBookmarkCreationError(c,models.ErrOwnedBookmarkInput);return}
 row,err:=models.ReadOwnedBookmarkCreation(id,middleware.GetMemberID(c))
 if err!=nil{ownedBookmarkCreationError(c,err);return}
 apiSuccess(c,row)
}
