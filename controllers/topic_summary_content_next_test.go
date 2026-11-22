package controllers_test

import (
 "crypto/sha256"
 "encoding/hex"
 "encoding/json"
 "net/http"
 "reflect"
 "strings"
 "testing"
 "bookstark/models"
)
func TestOwnedSummarySourceRoutesPreserveMetadataAndRejectInvalidCASWithoutMutation(t *testing.T){
 router,token:=initAssetControllerTest(t)
 topic:=&models.Topic{MemberID:1,Title:"actual summary topic"}
 if err:=models.CreateTopic(topic);err!=nil{t.Fatal(err)}
 summary:=&models.TopicSummary{TopicID:topic.TopicID,Content:"\ufeff# exact 😀\r\nbody",SummaryType:"manual",OrderSort:2}
 if err:=models.CreateTopicSummary(summary);err!=nil{t.Fatal(err)}
 if _,err:=models.DB.Exec("UPDATE md_topic_summaries SET summary_type='ai',order_sort=99 WHERE summary_id=?",summary.SummaryID);err!=nil{t.Fatal(err)}
 path:="/api/topics/"+itoa(topic.TopicID)+"/summaries/"+itoa(summary.SummaryID)+"/content"
 response:=adminAssetRequest(router,token,http.MethodGet,path,nil)
 if response.Code!=200{t.Fatalf("registered source GET status %d",response.Code)}
 var read topicSummaryResponse
 if err:=json.Unmarshal(response.Body.Bytes(),&read);err!=nil{t.Fatal(err)}
 if read.Data.Content!=summary.Content{t.Fatal("GET changed source BOM/CRLF")}
 sum:=sha256.Sum256([]byte(summary.Content));expected:=hex.EncodeToString(sum[:])
 before,err:=models.ReadOwnedTopicSummaryContent(1,topic.TopicID,summary.SummaryID);if err!=nil{t.Fatal(err)}
 for _,tc:=range []struct{body map[string]any;status int}{
  {map[string]any{"content":"bad","expected_source_sha256":expected,"order_sort":0},400},
  {map[string]any{"content":"bad"},400},
  {map[string]any{"content":"bad","expected_source_sha256":strings.Repeat("0",64)},409},
  {map[string]any{"content":strings.Repeat("x",20001),"expected_source_sha256":expected},400},
 }{
  response=adminAssetRequest(router,token,http.MethodPut,path,tc.body)
  if response.Code!=tc.status{t.Fatalf("expected rejection %d got %d",tc.status,response.Code)}
  after,err:=models.ReadOwnedTopicSummaryContent(1,topic.TopicID,summary.SummaryID);if err!=nil{t.Fatal(err)}
  if !reflect.DeepEqual(before,after){t.Fatal("rejected source update mutated body/metadata/time")}
 }
 response=adminAssetRequest(router,token,http.MethodPut,path,map[string]any{"content":"saved body","expected_source_sha256":expected})
 if response.Code!=200{t.Fatalf("typed source PUT status %d",response.Code)}
 actual,err:=models.ReadOwnedTopicSummaryContent(1,topic.TopicID,summary.SummaryID);if err!=nil{t.Fatal(err)}
 if actual.Content!="saved body"||actual.SummaryType!="ai"||actual.OrderSort!=99||!actual.CreateTime.Equal(before.CreateTime){
  t.Fatal("source-only endpoint overwrote metadata")
 }
}
