package models

// Draft regression only: NOT gofmt/compiled/run; no production DB is used.
import (
 "database/sql"
 "errors"
 "fmt"
 "testing"
)

func summaryTransactionTopic(t *testing.T) *Topic {
 t.Helper()
 topic := &Topic{Title:"summary atomicity", Question:"preserve question", MemberID:1, IsPinned:true}
 if err:=CreateTopic(topic);err!=nil {t.Fatal(err)}
 return topic
}
func summaryTopicMetadata(t *testing.T,id int64) string {
 t.Helper()
 var title,question,created,modified string
 var owner,pinned int64
 err:=DB.QueryRow("SELECT title, question, member_id, is_pinned, CAST(create_time AS TEXT), CAST(modify_time AS TEXT) FROM md_topics WHERE topic_id=?",id).
  Scan(&title,&question,&owner,&pinned,&created,&modified)
 if err!=nil {t.Fatal(err)}
 return fmt.Sprintf("%q|%q|%d|%d|%q|%q",title,question,owner,pinned,created,modified)
}
func summaryCount(t *testing.T,table string,topicID int64) int {
 t.Helper()
 if table!="md_topic_summaries"&&table!="md_topic_comments" {t.Fatal("invalid test table")}
 var n int
 if err:=DB.QueryRow("SELECT COUNT(*) FROM "+table+" WHERE topic_id=?",topicID).Scan(&n);err!=nil {t.Fatal(err)}
 return n
}
func TestSummaryCreateTouchFailureRollsBackInsertAndTopicMetadataNext(t *testing.T) {
 initAssetTestDB(t)
 topic:=summaryTransactionTopic(t)
 before:=summaryTopicMetadata(t,topic.TopicID)
 if _,err:=DB.Exec("CREATE TRIGGER fail_summary_touch_next BEFORE UPDATE ON md_topics BEGIN SELECT RAISE(ABORT, 'controlled touch failure'); END");err!=nil {t.Fatal(err)}
 summary:=&TopicSummary{TopicID:topic.TopicID,Content:" exact summary ",SummaryType:" AI ",OrderSort:19}
 if err:=CreateTopicSummary(summary);err==nil {t.Fatal("touch must fail")}
 if summary.SummaryID!=0 {t.Fatal("rolled back insert must not expose committed ID")}
 if got:=summaryCount(t,"md_topic_summaries",topic.TopicID);got!=0 {t.Fatalf("summary count=%d",got)}
 if after:=summaryTopicMetadata(t,topic.TopicID);after!=before {t.Fatal("topic metadata changed on failed transaction")}
 if _,err:=DB.Exec("DROP TRIGGER fail_summary_touch_next");err!=nil {t.Fatal(err)}
 if err:=CreateTopicSummary(summary);err!=nil {t.Fatal(err)}
 if got:=summaryCount(t,"md_topic_summaries",topic.TopicID);got!=1 {t.Fatalf("summary count=%d",got)}
 var content,kind string
 var order int
 if err:=DB.QueryRow("SELECT content,summary_type,order_sort FROM md_topic_summaries WHERE summary_id=?",summary.SummaryID).Scan(&content,&kind,&order);err!=nil {t.Fatal(err)}
 if content!="exact summary"||kind!=TopicSummaryAI||order!=19 {t.Fatal("existing normalization/order semantics changed")}
}
func TestSummaryCreateMissingTopicRollsBackOrphanNext(t *testing.T) {
 initAssetTestDB(t)
 summary:=&TopicSummary{TopicID:999999,Content:"must not persist"}
 err:=CreateTopicSummary(summary)
 // Some drivers enforce FK before UPDATE; either error path must rollback.
 if err==nil {t.Fatal("missing topic accepted")}
 if !errors.Is(err,sql.ErrNoRows) {
  if summaryCount(t,"md_topic_summaries",999999)!=0 {t.Fatal("orphan summary persisted")}
 }
 if summaryCount(t,"md_topic_summaries",999999)!=0 {t.Fatal("orphan summary persisted")}
}
func TestExistingCommentTransactionTouchFailureAlsoPreservesTopicTimeNext(t *testing.T) {
 initAssetTestDB(t)
 topic:=summaryTransactionTopic(t)
 summary:=&TopicSummary{TopicID:topic.TopicID,Content:"target"}
 if err:=CreateTopicSummary(summary);err!=nil {t.Fatal(err)}
 before:=summaryTopicMetadata(t,topic.TopicID)
 if _,err:=DB.Exec("CREATE TRIGGER fail_comment_touch_next BEFORE UPDATE ON md_topics BEGIN SELECT RAISE(ABORT, 'controlled touch failure'); END");err!=nil {t.Fatal(err)}
 comment:=&TopicComment{TopicID:topic.TopicID,MemberID:1,TargetType:TopicCommentSummary,TargetID:summary.SummaryID,Content:"must rollback"}
 if err:=CreateTopicComment(comment);err==nil {t.Fatal("touch must fail")}
 if summaryCount(t,"md_topic_comments",topic.TopicID)!=0 {t.Fatal("comment insert not rolled back")}
 if summaryTopicMetadata(t,topic.TopicID)!=before {t.Fatal("topic metadata/time changed")}
 if _,err:=DB.Exec("DROP TRIGGER fail_comment_touch_next");err!=nil {t.Fatal(err)}
 comment=&TopicComment{TopicID:topic.TopicID,MemberID:1,TargetType:TopicCommentSummary,TargetID:summary.SummaryID,Content:"one"}
 if err:=CreateTopicComment(comment);err!=nil {t.Fatal(err)}
 if summaryCount(t,"md_topic_comments",topic.TopicID)!=1 {t.Fatal("success must create exactly once")}
 reply:=&TopicComment{TopicID:topic.TopicID,MemberID:1,TargetType:TopicCommentSummary,TargetID:summary.SummaryID,ParentCommentID:comment.CommentID,Content:"reply"}
 if err:=CreateTopicComment(reply);!errors.Is(err,ErrTopicCommentReplyUnsupported) {t.Fatal("reply policy changed")}
 if summaryCount(t,"md_topic_comments",topic.TopicID)!=1 {t.Fatal("rejected reply inserted")}
}
func TestCommentResourceTargetRemainsRelationIDNext(t *testing.T) {
 initAssetTestDB(t)
 topic:=summaryTransactionTopic(t)
 task:=&Task{Content:"task target",DueDate:"2026-11-20",TopicID:topic.TopicID,MemberID:1}
 if err:=CreateTask(task);err!=nil {t.Fatal(err)}
 resource:=&TopicResource{TopicID:topic.TopicID,ResourceType:TopicResourceTask,TargetID:task.TaskID,TitleSnapshot:"task target"}
 if err:=CreateTopicResource(resource);err!=nil {t.Fatal(err)}
 // Make relation and underlying task IDs deliberately different.
 result,err:=DB.Exec("UPDATE md_topic_resources SET topic_resource_id=? WHERE topic_resource_id=?",resource.TopicResourceID+100,resource.TopicResourceID)
 if err!=nil {t.Fatal(err)}
 affected,err:=result.RowsAffected();if err!=nil||affected!=1 {t.Fatal("fixture UPDATE must affect one relation")}
 resource.TopicResourceID+=100
 if resource.TopicResourceID==task.TaskID {t.Fatal("fixture identities must differ")}
 comment:=&TopicComment{TopicID:topic.TopicID,MemberID:1,TargetType:TopicCommentResource,TargetID:resource.TopicResourceID,Content:"resource relation"}
 if err:=CreateTopicComment(comment);err!=nil {t.Fatal(err)}
 wrong:=&TopicComment{TopicID:topic.TopicID,MemberID:2,TargetType:TopicCommentResource,TargetID:resource.TopicResourceID,Content:"wrong owner"}
 if err:=CreateTopicComment(wrong);err==nil {t.Fatal("owner guard changed")}
 stored,err:=GetTopicCommentByID(comment.CommentID,topic.TopicID,1)
 if err!=nil {t.Fatal(err)}
 if stored.TargetType!=TopicCommentResource||stored.TargetID!=resource.TopicResourceID {t.Fatal("relation target identity changed")}
}
