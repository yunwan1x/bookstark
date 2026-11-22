package models
import (
 "database/sql"
 "errors"
 "strings"
 "testing"
)
func TestTopicCreationReviewExactOwnerBodyAndReadOnly(t *testing.T){
 initAssetTestDB(t)
 topic:=&Topic{Title:"Actual",Question:"Question",MemberID:1}
 if err:=CreateTopic(topic);err!=nil{t.Fatal(err)}
 summary:=&TopicSummary{TopicID:topic.TopicID,Content:"temporary",SummaryType:"manual",OrderSort:3}
 if err:=CreateTopicSummary(summary);err!=nil{t.Fatal(err)}
 exact:="\ufeffExact\r\n😀"
 if _,err:=DB.Exec("UPDATE md_topic_summaries SET content=? WHERE summary_id=?",exact,summary.SummaryID);err!=nil{t.Fatal(err)}
 row,err:=ReadOwnedTopicCreationReview("summary",summary.SummaryID,1)
 if err!=nil{t.Fatal(err)}
 if row["content"]!=exact||row["topic_id"]!=topic.TopicID||row["member_id"]!=int64(1){
  t.Fatalf("exact review differs: identity/source types")
 }
 if _,err:=ReadOwnedTopicCreationReview("summary",summary.SummaryID,2);!errors.Is(err,sql.ErrNoRows){t.Fatal("other owner was not rejected",err)}
 if _,err:=ReadOwnedTopicCreationReview("invalid",summary.SummaryID,1);err==nil{t.Fatal("unknown kind accepted")}
 var after string
 if err:=DB.QueryRow("SELECT content FROM md_topic_summaries WHERE summary_id=?",summary.SummaryID).Scan(&after);err!=nil{t.Fatal(err)}
 if after!=exact{t.Fatal("review mutated source")}
 if _,err:=DB.Exec("UPDATE md_topic_summaries SET content=? WHERE summary_id=?",strings.Repeat("x",80001),summary.SummaryID);err!=nil{t.Fatal(err)}
 if _,err:=ReadOwnedTopicCreationReview("summary",summary.SummaryID,1);!errors.Is(err,sql.ErrNoRows){t.Fatal("oversized source accepted",err)}
 if err:=DB.QueryRow("SELECT content FROM md_topic_summaries WHERE summary_id=?",summary.SummaryID).Scan(&after);err!=nil{t.Fatal(err)}
 if len(after)!=80001{t.Fatal("oversized source was mutated")}
}
