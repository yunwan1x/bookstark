package controllers
import (
 "database/sql"
 "errors"
 "net/http"
 "strconv"
 "github.com/gin-gonic/gin"
 "bookstark/middleware"
 "bookstark/models"
)
func GetTopicCreationReviewAPI(c *gin.Context) {
 id,err:=strconv.ParseInt(c.Param("resourceId"),10,64)
 if err!=nil||id<=0 {apiError(c,http.StatusBadRequest,"Invalid actual ID");return}
 kind:=c.Param("kind")
 if kind!="topic"&&kind!="summary"&&kind!="comment" {apiError(c,http.StatusBadRequest,"Invalid resource kind");return}
 row,err:=models.ReadOwnedTopicCreationReview(kind,id,middleware.GetMemberID(c))
 if err!=nil{
  if errors.Is(err,sql.ErrNoRows){apiError(c,http.StatusNotFound,"Resource unavailable");return}
  apiError(c,http.StatusInternalServerError,"Read-only review unavailable");return
 }
 apiSuccess(c,row)
}
