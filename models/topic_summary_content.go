package models

import (
 "crypto/sha256"
 "database/sql"
 "encoding/hex"
 "errors"
 "strings"
 "time"
 "unicode/utf8"
)
var ErrTopicSummaryContentConflict=errors.New("topic summary content changed")
var ErrTopicSummaryContentInput=errors.New("invalid or oversized topic summary source")
// All source/metadata reads use one owned transaction, bounded before materialization.
func readOwnedTopicSummaryTx(tx *sql.Tx,memberID,topicID,summaryID int64)(*TopicSummary,error){
 if memberID<=0||topicID<=0||summaryID<=0{return nil,ErrTopicSummaryContentInput}
 var size int64
 err:=tx.QueryRow(`SELECT length(CAST(s.content AS BLOB)) FROM md_topic_summaries s
 JOIN md_topics t ON t.topic_id=s.topic_id
 WHERE s.summary_id=? AND s.topic_id=? AND t.member_id=?`,summaryID,topicID,memberID).Scan(&size)
 if err!=nil{return nil,err}
 if size<0||size>80000{return nil,ErrTopicSummaryContentInput}
 result:=&TopicSummary{};var source []byte
 err=tx.QueryRow(`SELECT s.summary_id,s.topic_id,CAST(s.content AS BLOB),s.summary_type,s.order_sort,
 s.create_time,s.modify_time,(SELECT COUNT(*) FROM md_topic_comments c WHERE c.topic_id=s.topic_id
 AND c.target_type='summary' AND c.target_id=s.summary_id)
 FROM md_topic_summaries s JOIN md_topics t ON t.topic_id=s.topic_id
 WHERE s.summary_id=? AND s.topic_id=? AND t.member_id=?`,summaryID,topicID,memberID).Scan(
 &result.SummaryID,&result.TopicID,&source,&result.SummaryType,&result.OrderSort,
 &result.CreateTime,&result.ModifyTime,&result.CommentCount)
 if err!=nil{return nil,err}
 if int64(len(source))!=size||!utf8.Valid(source){return nil,ErrTopicSummaryContentInput}
 result.Content=string(source);return result,nil
}
func ReadOwnedTopicSummaryContent(memberID,topicID,summaryID int64)(*TopicSummary,error){
 db:=DB;if db==nil{return nil,errors.New("topic database unavailable")}
 tx,err:=db.Begin();if err!=nil{return nil,err};defer tx.Rollback()
 result,err:=readOwnedTopicSummaryTx(tx,memberID,topicID,summaryID);if err!=nil{return nil,err}
 if err:=tx.Commit();err!=nil{return nil,err};return result,nil
}
// Source-only CAS, not metadata CAS. Type/order are never overwritten.
func UpdateOwnedTopicSummaryContent(memberID,topicID,summaryID int64,expected,content string)(*TopicSummary,error){
 decoded,err:=hex.DecodeString(expected);content=strings.TrimSpace(content)
 if err!=nil||len(decoded)!=32||hex.EncodeToString(decoded)!=expected||!utf8.ValidString(content)||
 content==""||len(content)>80000||utf8.RuneCountInString(content)>20000{return nil,ErrTopicSummaryContentInput}
 db:=DB;if db==nil{return nil,errors.New("topic database unavailable")}
 tx,err:=db.Begin();if err!=nil{return nil,err};defer tx.Rollback()
 current,err:=readOwnedTopicSummaryTx(tx,memberID,topicID,summaryID);if err!=nil{return nil,err}
 digest:=sha256.Sum256([]byte(current.Content))
 if hex.EncodeToString(digest[:])!=expected{return nil,ErrTopicSummaryContentConflict}
 now:=time.Now()
 result,err:=tx.Exec(`UPDATE md_topic_summaries SET content=?,modify_time=?
 WHERE summary_id=? AND topic_id=? AND CAST(content AS BLOB)=?
 AND EXISTS(SELECT 1 FROM md_topics t WHERE t.topic_id=md_topic_summaries.topic_id AND t.member_id=?)`,
 content,now,summaryID,topicID,[]byte(current.Content),memberID)
 if err!=nil{return nil,err}
 count,err:=result.RowsAffected();if err!=nil{return nil,err};if count!=1{return nil,ErrTopicSummaryContentConflict}
 parent,err:=tx.Exec("UPDATE md_topics SET modify_time=? WHERE topic_id=? AND member_id=?",now,topicID,memberID)
 if err!=nil{return nil,err};count,err=parent.RowsAffected();if err!=nil{return nil,err};if count!=1{return nil,sql.ErrNoRows}
 current,err=readOwnedTopicSummaryTx(tx,memberID,topicID,summaryID);if err!=nil{return nil,err}
 if err:=tx.Commit();err!=nil{return nil,err};return current,nil
}
