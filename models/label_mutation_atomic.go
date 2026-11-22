package models

import (
 "database/sql"
 "errors"
 "fmt"
 "time"
)

// Exported typed denial, so stale JWT permissions never become a false success.
var ErrLabelMutationForbidden=errors.New("label mutation authority changed")

func labelMutationActorTx(tx *sql.Tx,actorID int64)(bool,error){
 if actorID<=0{return false,ErrLabelMutationForbidden}
 var role,status int
 if err:=tx.QueryRow("SELECT role,status FROM md_members WHERE member_id=?",actorID).Scan(&role,&status);err!=nil{
  if errors.Is(err,sql.ErrNoRows){return false,ErrLabelMutationForbidden};return false,err
 }
 if status!=1{return false,ErrLabelMutationForbidden}
 return role==0,nil // Actual middleware.RoleAdmin value; no models->middleware cycle.
}
func DeleteLabelOwned(id,actorID int64)error{
 return deleteLabelAtomic(id,actorID,true)
}
func deleteLabelAtomic(id,actorID int64,checkActor bool)error{
 db:=DB;if db==nil||id<=0{return fmt.Errorf("invalid label deletion")}
 tx,err:=db.Begin();if err!=nil{return err};defer tx.Rollback()
 if checkActor{
  admin,err:=labelMutationActorTx(tx,actorID);if err!=nil{return err}
  if !admin{return ErrLabelMutationForbidden}
 }
 var actual int64
 if err=tx.QueryRow("SELECT label_id FROM md_label WHERE label_id=?",id).Scan(&actual);err!=nil{
  if errors.Is(err,sql.ErrNoRows){return fmt.Errorf("标签不存在")};return err
 }
 var count,biggest int
 if err=tx.QueryRow("SELECT COUNT(*),COALESCE(MAX(length(CAST(relation_type AS BLOB))),0) FROM md_label_relation WHERE label_id=?",id).Scan(&count,&biggest);err!=nil{return err}
 if biggest>24{return fmt.Errorf("invalid label relation metadata")}
 if count>10000{return fmt.Errorf("label relation metadata exceeds deletion budget")}
 type ref struct{id int64;kind string}
 refs:=[]ref{};seen:=map[ref]bool{}
 rows,err:=tx.Query("SELECT resource_id,relation_type FROM md_label_relation WHERE label_id=?",id)
 if err!=nil{return err}
 for rows.Next(){
  var r ref
  if err=rows.Scan(&r.id,&r.kind);err!=nil{rows.Close();return err}
  if r.id<=0||(r.kind!="book"&&r.kind!="blog"&&r.kind!="bookmark"&&r.kind!="document"){
   rows.Close();return fmt.Errorf("invalid label reference")
  }
  if !seen[r]{seen[r]=true;refs=append(refs,r)}
 }
 if err=rows.Err();err!=nil{rows.Close();return err};if err=rows.Close();err!=nil{return err}
 if _,err=tx.Exec("DELETE FROM md_label_relation WHERE label_id=?",id);err!=nil{return err}
 if _,err=tx.Exec("DELETE FROM md_label WHERE label_id=?",id);err!=nil{return err}
 for _,r:=range refs{
  if err=syncMergedResourceLabelsTx(tx,r.id,r.kind);err!=nil{return err}
 }
 return tx.Commit()
}
func UnbindLabelsOwned(labelID int64,resourceIDs []int64,kind string,actorID int64)error{
 return unbindLabelsAtomic(labelID,resourceIDs,kind,actorID,true)
}
func unbindLabelsAtomic(labelID int64,resourceIDs []int64,kind string,actorID int64,checkActor bool)error{
 if labelID<=0||len(resourceIDs)==0||len(resourceIDs)>200{return fmt.Errorf("invalid label unbind identities")}
 table,key:="",""
 switch kind{
 case "book":table,key="md_books","book_id"
 case "blog":table,key="md_blogs","blog_id"
 case "bookmark":table,key="md_bookmark","bookmark_id"
 case "document":table,key="md_documents","document_id"
 default:return fmt.Errorf("invalid label relation type")
 }
 seen:=map[int64]bool{}
 for _,id:=range resourceIDs{
  if id<=0||seen[id]{return fmt.Errorf("distinct positive resource IDs required")};seen[id]=true
 }
 db:=DB;if db==nil{return fmt.Errorf("label database unavailable")}
 tx,err:=db.Begin();if err!=nil{return err};defer tx.Rollback()
 admin:=false
 if checkActor{admin,err=labelMutationActorTx(tx,actorID);if err!=nil{return err}}
 var actual int64
 if err=tx.QueryRow("SELECT label_id FROM md_label WHERE label_id=?",labelID).Scan(&actual);err!=nil{return err}
 // Resolve every actual identity and authority before the first DELETE. The old
 // controller preflight cannot authorize a changed owner at mutation time.
 for _,id:=range resourceIDs{
  var owner int64
  if err=tx.QueryRow("SELECT member_id FROM "+table+" WHERE "+key+"=?",id).Scan(&owner);err!=nil{return err}
  if checkActor&&!admin&&owner!=actorID{return ErrLabelMutationForbidden}
 }
 now:=time.Now()
 for _,id:=range resourceIDs{
  result,err:=tx.Exec("DELETE FROM md_label_relation WHERE label_id=? AND resource_id=? AND relation_type=?",labelID,id,kind)
  if err!=nil{return err}
  removed,err:=result.RowsAffected();if err!=nil{return err}
  if removed==0{continue} // An explicit duplicate unbind has no timestamp side effect.
  if err=syncMergedResourceLabelsTx(tx,id,kind);err!=nil{return err}
  if kind=="bookmark"{
   if _,err=tx.Exec("UPDATE md_bookmark SET modify_time=? WHERE bookmark_id=?",now,id);err!=nil{return err}
  }
 }
 return tx.Commit()
}
