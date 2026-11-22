package models

import (
 "database/sql"
 "errors"
 "unicode/utf8"
)

// Read-only exact ID proof. This establishes current identity/content, not
// provenance of a previous POST; adoption always requires explicit review.
func ReadOwnedTopicCreationReview(kind string, id, memberID int64) (map[string]interface{}, error) {
 db:=DB
 if db==nil || id<=0 || memberID<=0 {return nil,sql.ErrNoRows}
 tx,err:=db.Begin();if err!=nil{return nil,err};defer tx.Rollback()
 var query string
 switch kind {
 case "topic":
  query=`SELECT topic_id,member_id,title,question,is_pinned,create_time,modify_time
   FROM md_topics WHERE topic_id=? AND member_id=?
   AND length(CAST(title AS BLOB))<=800 AND length(CAST(question AS BLOB))<=8000`
 case "summary":
  query=`SELECT s.summary_id,s.topic_id,t.member_id,s.content,s.summary_type,s.order_sort,
   (SELECT COUNT(*) FROM md_topic_comments cc WHERE cc.topic_id=s.topic_id AND cc.target_type='summary' AND cc.target_id=s.summary_id) AS comment_count,
   s.create_time,s.modify_time
   FROM md_topic_summaries s JOIN md_topics t ON t.topic_id=s.topic_id
   WHERE s.summary_id=? AND t.member_id=? AND length(CAST(s.content AS BLOB))<=80000`
 case "comment":
  query=`SELECT c.comment_id,c.topic_id,c.member_id,c.target_type,c.target_id,c.parent_comment_id,c.content,COALESCE(m.account, '') AS author_name,c.create_time,c.modify_time
   FROM md_topic_comments c JOIN md_topics t ON t.topic_id=c.topic_id
   LEFT JOIN md_members m ON m.member_id=c.member_id
   WHERE c.comment_id=? AND t.member_id=? AND c.member_id=t.member_id
   AND length(CAST(c.content AS BLOB))<=80000 AND length(CAST(COALESCE(m.account, '') AS BLOB))<=800`
 default:return nil,errors.New("unsupported topic creation kind")
 }
 rows,err:=tx.Query(query,id,memberID);if err!=nil{return nil,err}
 cols,err:=rows.Columns();if err!=nil{rows.Close();return nil,err}
 if !rows.Next(){e:=rows.Err();rows.Close();if e!=nil{return nil,e};return nil,sql.ErrNoRows}
 values:=make([]interface{},len(cols));dest:=make([]interface{},len(cols))
 for i:=range values{dest[i]=&values[i]}
 if err=rows.Scan(dest...);err!=nil{rows.Close();return nil,err}
 result:=make(map[string]interface{},len(cols))
 for i,v:=range values{
  if b,ok:=v.([]byte);ok {if !utf8.Valid(b){rows.Close();return nil,errors.New("invalid topic source")};v=string(b)}
  if text,ok:=v.(string);ok && !utf8.ValidString(text){rows.Close();return nil,errors.New("invalid topic source")}
  result[cols[i]]=v
 }
 if rows.Next(){rows.Close();return nil,errors.New("ambiguous topic identity")}
 err=rows.Err();rows.Close();if err!=nil{return nil,err}
 if kind=="comment" {
  topic,okTopic:=result["topic_id"].(int64)
  target,okTarget:=result["target_id"].(int64)
  targetType,okType:=result["target_type"].(string)
  parent,okParent:=result["parent_comment_id"].(int64)
  if !okTopic||!okTarget||!okType||!okParent||parent!=0{return nil,sql.ErrNoRows}
  if err=ValidateTopicCommentTarget(tx,topic,memberID,targetType,target);err!=nil{return nil,err}
 }
 if err=tx.Commit();err!=nil{return nil,err}
 return result,nil
}
