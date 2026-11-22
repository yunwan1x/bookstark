package models

import (
 "database/sql"
 "errors"
 "net/url"
 "strconv"
 "strings"
 "time"
 "unicode/utf8"
)

var ErrOwnedBookmarkDuplicate=errors.New("owned bookmark URL already exists")
var ErrOwnedBookmarkInput=errors.New("invalid owned bookmark creation input")
var ErrOwnedBookmarkReadBound=errors.New("owned bookmark exceeds recovery bounds")

type OwnedBookmarkCreationInput struct {
 Title string `json:"title"`
 URL string `json:"url"`
 Description string `json:"description"`
 Favicon string `json:"favicon"`
 IsPublic bool `json:"is_public"`
 Labels []string `json:"labels"`
}
type OwnedBookmarkCreationSnapshot struct {
 Bookmark
 Labels []string `json:"labels"`
}
func validOwnedBookmarkURL(raw string)bool{
 if len(raw)==0||len(raw)>2048||!utf8.ValidString(raw){return false}
 for _,r:=range raw{if r<=0x20||r==0x7f{return false}}
 u,err:=url.Parse(raw)
 if err!=nil||u.User!=nil||u.Hostname()==""||(u.Scheme!="http"&&u.Scheme!="https")||strings.HasSuffix(u.Host,":"){return false}
 if port:=u.Port();port!=""{n,e:=strconv.Atoi(port);if e!=nil||n<1||n>65535{return false}}
 return true
}
func (in OwnedBookmarkCreationInput) validated()(OwnedBookmarkCreationInput,error){
 if !utf8.ValidString(in.Title)||strings.TrimSpace(in.Title)==""||len(in.Title)>500||
  !validOwnedBookmarkURL(in.URL)||!utf8.ValidString(in.Description)||len(in.Description)>2000||
  !utf8.ValidString(in.Favicon)||len(in.Favicon)>4096||len(in.Labels)>100{return in,ErrOwnedBookmarkInput}
 seen:=map[string]bool{};names:=make([]string,0,len(in.Labels));total:=0
 for _,name:=range in.Labels{
  if !utf8.ValidString(name)||len(name)>4096{return in,ErrOwnedBookmarkInput}
  if seen[name]{continue};seen[name]=true;total+=len(name)
  if total>65536{return in,ErrOwnedBookmarkInput};names=append(names,name)
 }
 in.Labels=names
 return in,nil
}
func readOwnedBookmarkCreationTx(tx *sql.Tx,id,memberID int64)(*OwnedBookmarkCreationSnapshot,error){
 var out OwnedBookmarkCreationSnapshot;var public,pin,nav int
 var lengths [5]sql.NullInt64
 err:=tx.QueryRow(`SELECT length(CAST(title AS BLOB)),length(CAST(url AS BLOB)),
  length(CAST(description AS BLOB)),length(CAST(favicon AS BLOB)),length(CAST(label AS BLOB))
  FROM md_bookmark WHERE bookmark_id=? AND member_id=?`,id,memberID).
  Scan(&lengths[0],&lengths[1],&lengths[2],&lengths[3],&lengths[4])
 if err!=nil{return nil,err}
 for i,cap:=range []int64{500,2048,2000,4096,65635}{
  if !lengths[i].Valid||lengths[i].Int64<0||lengths[i].Int64>cap{return nil,ErrOwnedBookmarkReadBound}
 }
 err=tx.QueryRow(`SELECT bookmark_id,title,url,description,favicon,order_sort,label,member_id,
  is_public,is_pinned,nav_visible,create_time,modify_time FROM md_bookmark
  WHERE bookmark_id=? AND member_id=? AND length(CAST(title AS BLOB))<=500
  AND length(CAST(url AS BLOB))<=2048 AND length(CAST(description AS BLOB))<=2000
  AND length(CAST(favicon AS BLOB))<=4096 AND length(CAST(label AS BLOB))<=65635`,id,memberID).
  Scan(&out.BookmarkID,&out.Title,&out.URL,&out.Description,&out.Favicon,&out.OrderSort,&out.Label,&out.MemberID,
   &public,&pin,&nav,&out.CreateTime,&out.ModifyTime)
 if err!=nil{return nil,err}
 if (public!=0&&public!=1)||(pin!=0&&pin!=1)||(nav!=0&&nav!=1){return nil,ErrOwnedBookmarkReadBound}
 for _,s:=range []string{out.Title,out.URL,out.Description,out.Favicon,out.Label}{
  if !utf8.ValidString(s){return nil,ErrOwnedBookmarkReadBound}
 }
 out.IsPublic=public==1;out.IsPinned=pin==1;out.NavVisible=nav==1
 var count,total,max,nonNull int64
 err=tx.QueryRow(`SELECT COUNT(*),COALESCE(SUM(length(CAST(l.label_name AS BLOB))),0),
  COALESCE(MAX(length(CAST(l.label_name AS BLOB))),0),COUNT(l.label_name)
  FROM md_label_relation r JOIN md_label l ON l.label_id=r.label_id
  WHERE r.resource_id=? AND r.relation_type='bookmark'`,id).Scan(&count,&total,&max,&nonNull)
 if err!=nil{return nil,err}
 if count!=nonNull||count>100||total>65536||max>4096{return nil,ErrOwnedBookmarkReadBound}
 rows,err:=tx.Query(`SELECT CAST(l.label_name AS BLOB) FROM md_label_relation r
  JOIN md_label l ON l.label_id=r.label_id
  WHERE r.resource_id=? AND r.relation_type='bookmark' ORDER BY l.label_id`,id)
 if err!=nil{return nil,err}
 names:=make([]string,0,count);seen:=map[string]bool{}
 for rows.Next(){
  var raw []byte
  if err=rows.Scan(&raw);err!=nil{rows.Close();return nil,err}
  if !utf8.Valid(raw)||len(raw)>4096{rows.Close();return nil,ErrOwnedBookmarkReadBound}
  name:=string(raw);if seen[name]{rows.Close();return nil,ErrOwnedBookmarkReadBound}
  seen[name]=true;names=append(names,name)
 }
 err=rows.Err();rows.Close();if err!=nil{return nil,err}
 if int64(len(names))!=count{return nil,ErrOwnedBookmarkReadBound}
 out.Labels=names
 return &out,nil
}
func ReadOwnedBookmarkCreation(id,memberID int64)(*OwnedBookmarkCreationSnapshot,error){
 db:=DB;if db==nil||id<=0||memberID<=0{return nil,sql.ErrNoRows}
 tx,err:=db.Begin();if err!=nil{return nil,err};defer tx.Rollback()
 out,err:=readOwnedBookmarkCreationTx(tx,id,memberID);if err!=nil{return nil,err}
 if err=tx.Commit();err!=nil{return nil,err};return out,nil
}
// Body-only URL lookup. No page walk, metadata fetch, upsert or mutation.
func CheckOwnedBookmarkCreationURL(raw string,memberID int64)(*OwnedBookmarkCreationSnapshot,error){
 db:=DB;if db==nil||memberID<=0{return nil,sql.ErrNoRows}
 if !validOwnedBookmarkURL(raw){return nil,ErrOwnedBookmarkInput}
 tx,err:=db.Begin();if err!=nil{return nil,err};defer tx.Rollback()
 var id int64
 err=tx.QueryRow("SELECT bookmark_id FROM md_bookmark WHERE member_id=? AND url=?",memberID,raw).Scan(&id)
 if errors.Is(err,sql.ErrNoRows){if err=tx.Commit();err!=nil{return nil,err};return nil,nil}
 if err!=nil{return nil,err}
 out,err:=readOwnedBookmarkCreationTx(tx,id,memberID);if err!=nil{return nil,err}
 if err=tx.Commit();err!=nil{return nil,err};return out,nil
}
func CreateOwnedBookmarkAtomic(input OwnedBookmarkCreationInput,memberID int64)(*OwnedBookmarkCreationSnapshot,error){
 in,err:=input.validated();if err!=nil{return nil,err}
 db:=DB;if db==nil||memberID<=0{return nil,sql.ErrNoRows}
 tx,err:=db.Begin();if err!=nil{return nil,err};defer tx.Rollback()
 favicon:=in.Favicon;if favicon==""{favicon=generateFaviconURL(in.URL)}
 now:=time.Now().UTC();var id,order int64
 // First statement is the write: no read-transaction upgrade race. URL/member
 // uniqueness rejects an existing resource; unlike legacy POST it never updates.
 err=tx.QueryRow(`INSERT INTO md_bookmark(title,url,description,favicon,order_sort,label,
  member_id,is_public,is_pinned,nav_visible,create_time,modify_time)
  SELECT ?,?,?,?,(SELECT COALESCE(MAX(order_sort),0)+1 FROM md_bookmark WHERE member_id=?),
  ?,?,?,0,0,?,? FROM md_members WHERE member_id=?
  RETURNING bookmark_id,order_sort`,in.Title,in.URL,in.Description,favicon,memberID,
  strings.Join(in.Labels,","),memberID,in.IsPublic,now,now,memberID).Scan(&id,&order)
 if err!=nil{
  if strings.Contains(err.Error(),"md_bookmark.url")&&strings.Contains(err.Error(),"md_bookmark.member_id"){
   return nil,ErrOwnedBookmarkDuplicate
  }
  return nil,err
 }
 for _,name:=range in.Labels{
  if _,err=tx.Exec("INSERT OR IGNORE INTO md_label(label_name)VALUES(?)",name);err!=nil{return nil,err}
  var labelID int64
  if err=tx.QueryRow("SELECT label_id FROM md_label WHERE label_name=?",name).Scan(&labelID);err!=nil{return nil,err}
  if _,err=tx.Exec(`INSERT INTO md_label_relation(label_id,resource_id,relation_type,created_at)
   VALUES(?,?,'bookmark',datetime('now'))`,labelID,id);err!=nil{return nil,err}
 }
 out,err:=readOwnedBookmarkCreationTx(tx,id,memberID);if err!=nil{return nil,err}
 if out.OrderSort!=int(order)||out.BookmarkID!=id||len(out.Labels)!=len(in.Labels){return nil,ErrOwnedBookmarkReadBound}
 if err=tx.Commit();err!=nil{return nil,err};return out,nil
}
