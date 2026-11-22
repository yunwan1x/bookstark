package models

import (
 "crypto/sha256"
 "encoding/hex"
 "errors"
 "reflect"
 "strings"
 "testing"
)
func summarySourceSHA(source string)string{sum:=sha256.Sum256([]byte(source));return hex.EncodeToString(sum[:])}
func TestOwnedSummaryBodyCASPreservesConcurrentTypeOrderAndRejectsStaleSource(t *testing.T){
 initAssetTestDB(t)
 topic:=&Topic{MemberID:1,Title:"owned summary"};if err:=CreateTopic(topic);err!=nil{t.Fatal(err)}
 summary:=&TopicSummary{TopicID:topic.TopicID,Content:"\ufeff# source 😀\r\nbody",SummaryType:"manual",OrderSort:2}
 if err:=CreateTopicSummary(summary);err!=nil{t.Fatal(err)}
 baseline,err:=ReadOwnedTopicSummaryContent(1,topic.TopicID,summary.SummaryID);if err!=nil{t.Fatal(err)}
 if baseline.Content!=summary.Content{t.Fatal("source BOM/CRLF changed")}
 if _,err:=DB.Exec("UPDATE md_topic_summaries SET summary_type='ai',order_sort=99 WHERE summary_id=?",summary.SummaryID);err!=nil{t.Fatal(err)}
 actual,err:=UpdateOwnedTopicSummaryContent(1,topic.TopicID,summary.SummaryID,summarySourceSHA(baseline.Content),"new body")
 if err!=nil{t.Fatal(err)}
 if actual.Content!="new body"||actual.SummaryType!="ai"||actual.OrderSort!=99||!actual.CreateTime.Equal(baseline.CreateTime){
  t.Fatal("body-only update overwrote actual metadata")
 }
 before:=*actual
 if _,err:=UpdateOwnedTopicSummaryContent(1,topic.TopicID,summary.SummaryID,summarySourceSHA(baseline.Content),"stale overwrite");!errors.Is(err,ErrTopicSummaryContentConflict){t.Fatalf("stale source accepted: %v",err)}
 after,err:=ReadOwnedTopicSummaryContent(1,topic.TopicID,summary.SummaryID);if err!=nil{t.Fatal(err)}
 if !reflect.DeepEqual(before,*after){t.Fatal("rejection mutated source/metadata/timestamps")}
 if _,err:=UpdateOwnedTopicSummaryContent(2,topic.TopicID,summary.SummaryID,summarySourceSHA(actual.Content),"wrong owner");err==nil{t.Fatal("foreign owner accepted")}
 if _,err:=ReadOwnedTopicSummaryContent(1,topic.TopicID+1,summary.SummaryID);err==nil{t.Fatal("retargeted topic accepted")}
}
func TestOwnedSummarySourceBudgetRejectsLegacyOversizeBeforeWriting(t *testing.T){
 initAssetTestDB(t)
 topic:=&Topic{MemberID:1,Title:"legacy summary"};if err:=CreateTopic(topic);err!=nil{t.Fatal(err)}
 summary:=&TopicSummary{TopicID:topic.TopicID,Content:"source",SummaryType:"manual"}
 if err:=CreateTopicSummary(summary);err!=nil{t.Fatal(err)}
 source:=strings.Repeat("x",80001)
 if _,err:=DB.Exec("UPDATE md_topic_summaries SET content=? WHERE summary_id=?",source,summary.SummaryID);err!=nil{t.Fatal(err)}
 if _,err:=ReadOwnedTopicSummaryContent(1,topic.TopicID,summary.SummaryID);!errors.Is(err,ErrTopicSummaryContentInput){t.Fatalf("oversize read accepted: %v",err)}
 if _,err:=UpdateOwnedTopicSummaryContent(1,topic.TopicID,summary.SummaryID,summarySourceSHA(source),"replacement");!errors.Is(err,ErrTopicSummaryContentInput){t.Fatalf("oversize source overwritten: %v",err)}
 var unchanged string;if err:=DB.QueryRow("SELECT content FROM md_topic_summaries WHERE summary_id=?",summary.SummaryID).Scan(&unchanged);err!=nil{t.Fatal(err)}
 if unchanged!=source{t.Fatal("restricted old source changed")}
}
