package controllers

import (
 "database/sql"
 "errors"
 "encoding/json"
 "io"
 "net/http"
 "bookstark/middleware"
 "bookstark/models"
 "github.com/gin-gonic/gin"
)
func topicSummaryContentError(c *gin.Context,err error){
 switch{
 case errors.Is(err,sql.ErrNoRows):apiError(c,http.StatusNotFound,"小结不存在")
 case errors.Is(err,models.ErrTopicSummaryContentConflict):apiError(c,http.StatusConflict,"正文已变化，请重新核对")
 case errors.Is(err,models.ErrTopicSummaryContentInput):apiError(c,http.StatusBadRequest,"小结内容或版本无效")
 default:apiError(c,http.StatusInternalServerError,"小结正文暂不可用")
 }
}
func ReadTopicSummaryContentAPI(c *gin.Context){
 topic,ok:=mustOwnTopic(c);if !ok{return}
 id,ok:=parseParamID(c,"summaryId","无效小结ID");if !ok{return}
 value,err:=models.ReadOwnedTopicSummaryContent(middleware.GetMemberID(c),topic.TopicID,id)
 if err!=nil{topicSummaryContentError(c,err);return};apiSuccess(c,value)
}
func UpdateTopicSummaryContentAPI(c *gin.Context){
 topic,ok:=mustOwnTopic(c);if !ok{return}
 id,ok:=parseParamID(c,"summaryId","无效小结ID");if !ok{return}
 var request struct{
  Content string `json:"content"`
  ExpectedSHA string `json:"expected_source_sha256"`
 }
 c.Request.Body=http.MaxBytesReader(c.Writer,c.Request.Body,256*1024)
 decoder:=json.NewDecoder(c.Request.Body);decoder.DisallowUnknownFields()
 if err:=decoder.Decode(&request);err!=nil{apiError(c,http.StatusBadRequest,"请求格式错误");return}
 var extra interface{}
 if err:=decoder.Decode(&extra);err!=io.EOF{apiError(c,http.StatusBadRequest,"请求包含额外数据");return}
 value,err:=models.UpdateOwnedTopicSummaryContent(middleware.GetMemberID(c),topic.TopicID,id,request.ExpectedSHA,request.Content)
 if err!=nil{topicSummaryContentError(c,err);return};apiSuccess(c,value)
}
