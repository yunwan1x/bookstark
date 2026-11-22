package models

import (
 "database/sql"
 "errors"
 "time"
 "unicode/utf8"
)

var ErrLabelCreationReviewBound=errors.New("global label metadata exceeds review bounds")
type LabelCreationRelation struct {
 ID int64 `json:"id"`
 ResourceID int64 `json:"resource_id"`
 RelationType string `json:"relation_type"`
 CreatedAt time.Time `json:"created_at"`
}
type LabelCreationReview struct {
 LabelID int64 `json:"label_id"`
 LabelName string `json:"label_name"`
 BookCount int `json:"book_count"`
 BlogCount int `json:"blog_count"`
 BookmarkCount int `json:"bookmark_count"`
 DocumentCount int `json:"document_count"`
 RelationCount int `json:"relation_count"`
 Relations []LabelCreationRelation `json:"relations"`
}
// A label is global, not owned by actorID. Authentication identifies the caller
// who may review it, never an invented member_id on md_label.
func ReadLabelCreationReview(id,actorID int64)(*LabelCreationReview,error) {
 db:=DB;if db==nil||id<=0||actorID<=0{return nil,sql.ErrNoRows}
 tx,err:=db.Begin();if err!=nil{return nil,err};defer tx.Rollback()
 var actor int64
 if err=tx.QueryRow("SELECT member_id FROM md_members WHERE member_id=?",actorID).Scan(&actor);err!=nil{return nil,err}
 var size sql.NullInt64
 if err=tx.QueryRow("SELECT length(CAST(label_name AS BLOB)) FROM md_label WHERE label_id=?",id).Scan(&size);err!=nil{return nil,err}
 if !size.Valid||size.Int64<0||size.Int64>100{return nil,ErrLabelCreationReviewBound}
 out:=&LabelCreationReview{LabelID:id,Relations:make([]LabelCreationRelation,0)}
 var raw []byte
 if err=tx.QueryRow("SELECT CAST(label_name AS BLOB) FROM md_label WHERE label_id=?",id).Scan(&raw);err!=nil{return nil,err}
 if int64(len(raw))!=size.Int64||!utf8.Valid(raw){return nil,ErrLabelCreationReviewBound}
 out.LabelName=string(raw)
 var count,maxType,nonNull int64
 err=tx.QueryRow(`SELECT COUNT(*),COALESCE(MAX(length(CAST(relation_type AS BLOB))),0),
  COUNT(relation_type) FROM md_label_relation WHERE label_id=?`,id).Scan(&count,&maxType,&nonNull)
 if err!=nil{return nil,err}
 if count>500||count!=nonNull||maxType>24{return nil,ErrLabelCreationReviewBound}
 rows,err:=tx.Query(`SELECT id,resource_id,relation_type,created_at
  FROM md_label_relation WHERE label_id=? ORDER BY id`,id)
 if err!=nil{return nil,err}
 for rows.Next() {
  var item LabelCreationRelation
  if err=rows.Scan(&item.ID,&item.ResourceID,&item.RelationType,&item.CreatedAt);err!=nil{rows.Close();return nil,err}
  if item.ID<=0||item.ResourceID<=0||!utf8.ValidString(item.RelationType)||len(item.RelationType)>24{
   rows.Close();return nil,ErrLabelCreationReviewBound
  }
  switch item.RelationType {
  case "book":out.BookCount++
  case "blog":out.BlogCount++
  case "bookmark":out.BookmarkCount++
  case "document":out.DocumentCount++
  default:rows.Close();return nil,ErrLabelCreationReviewBound
  }
  out.Relations=append(out.Relations,item)
 }
 err=rows.Err();rows.Close();if err!=nil{return nil,err}
 if int64(len(out.Relations))!=count{return nil,ErrLabelCreationReviewBound}
 out.RelationCount=len(out.Relations)
 if err=tx.Commit();err!=nil{return nil,err}
 return out,nil
}
