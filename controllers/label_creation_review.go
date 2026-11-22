package controllers

import (
 "database/sql"
 "errors"
 "net/http"
 "strconv"
 "bookstark/middleware"
 "bookstark/models"
 "github.com/gin-gonic/gin"
)
func ReadLabelCreationReviewAPI(c *gin.Context) {
 id,err:=strconv.ParseInt(c.Param("id"),10,64)
 if err!=nil||id<=0{apiError(c,http.StatusBadRequest,"Actual label ID required");return}
 row,err:=models.ReadLabelCreationReview(id,middleware.GetMemberID(c))
 if errors.Is(err,sql.ErrNoRows){apiError(c,http.StatusNotFound,"Global label unavailable");return}
 if errors.Is(err,models.ErrLabelCreationReviewBound){apiError(c,http.StatusRequestEntityTooLarge,"Global label review exceeds limits");return}
 if err!=nil{apiError(c,http.StatusInternalServerError,"Global label review unavailable");return}
 apiSuccess(c,row)
}
