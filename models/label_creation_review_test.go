package models

import (
 "bytes"
 "database/sql"
 "errors"
 "reflect"
 "testing"
)

func TestLabelCreationReviewIsGlobalCompleteReadOnlyAndPreservesExactName(t *testing.T) {
 initAssetTestDB(t)
 label:=&Label{LabelName:" \ufeff研究/Flutter "}
 if err:=label.Insert();err!=nil{t.Fatal(err)}
 other:=&Member{Account:"label-review-other",Password:"synthetic-only",Role:1,Status:0}
 if err:=other.Insert();err!=nil{t.Fatal(err)}
 for i,kind:=range []string{"book","book","blog","blog","blog","bookmark","document"} {
  if _,err:=DB.Exec("INSERT INTO md_label_relation(label_id,resource_id,relation_type) VALUES(?,?,?)",
   label.LabelID,i+10,kind);err!=nil{t.Fatal(err)}
 }
 first,err:=ReadLabelCreationReview(label.LabelID,1);if err!=nil{t.Fatal(err)}
 if first.LabelName!=label.LabelName||first.RelationCount!=7||len(first.Relations)!=7||
 first.BookCount!=2||first.BlogCount!=3||first.BookmarkCount!=1||first.DocumentCount!=1 {
  t.Fatal("complete global metadata missing")
 }
 // The second authenticated member reads the same GLOBAL label. No label owner
 // is fabricated from its creator, from the record scope, or from resource IDs.
 second,err:=ReadLabelCreationReview(label.LabelID,other.MemberID)
 if err!=nil||!reflect.DeepEqual(first,second){t.Fatal("global label incorrectly owned",err)}
 if _,err=ReadLabelCreationReview(label.LabelID,999999);!errors.Is(err,sql.ErrNoRows){t.Fatal("missing actor accepted",err)}
 third,err:=ReadLabelCreationReview(label.LabelID,1)
 if err!=nil||!reflect.DeepEqual(first,third){t.Fatal("read mutated actual data",err)}
 var actual []byte
 if err=DB.QueryRow("SELECT CAST(label_name AS BLOB) FROM md_label WHERE label_id=?",label.LabelID).Scan(&actual);
 err!=nil||!bytes.Equal(actual,[]byte(label.LabelName)){t.Fatal("read changed exact UTF8 bytes",err)}
}

func TestLabelCreationReviewBoundAndUnknownRelationNeverReturnPartialOrRewrite(t *testing.T) {
 initAssetTestDB(t);label:=&Label{LabelName:"Bounded"}
 if err:=label.Insert();err!=nil{t.Fatal(err)}
 tx,err:=DB.Begin();if err!=nil{t.Fatal(err)}
 for i:=0;i<501;i++ {
  if _,err=tx.Exec("INSERT INTO md_label_relation(label_id,resource_id,relation_type) VALUES(?,?,'book')",
   label.LabelID,i+1);err!=nil{tx.Rollback();t.Fatal(err)}
 }
 if err=tx.Commit();err!=nil{t.Fatal(err)}
 if _,err=ReadLabelCreationReview(label.LabelID,1);!errors.Is(err,ErrLabelCreationReviewBound) {
  t.Fatal("501 rows returned as truncated editable proof",err)
 }
 var count int
 if err=DB.QueryRow("SELECT COUNT(*) FROM md_label_relation WHERE label_id=?",label.LabelID).Scan(&count);
 err!=nil||count!=501{t.Fatal("bound refusal mutated relations",err)}
 if _,err=DB.Exec("DELETE FROM md_label_relation WHERE id=(SELECT MAX(id) FROM md_label_relation WHERE label_id=?)",label.LabelID);err!=nil{t.Fatal(err)}
 actual,err:=ReadLabelCreationReview(label.LabelID,1)
 if err!=nil||len(actual.Relations)!=500{t.Fatal("legal complete boundary refused",err)}
 if _,err=DB.Exec("UPDATE md_label_relation SET relation_type='legacy-unknown' WHERE id=?",actual.Relations[0].ID);err!=nil{t.Fatal(err)}
 if _,err=ReadLabelCreationReview(label.LabelID,1);!errors.Is(err,ErrLabelCreationReviewBound){t.Fatal("unknown relation omitted",err)}
 var kind string
 if err=DB.QueryRow("SELECT relation_type FROM md_label_relation WHERE id=?",actual.Relations[0].ID).Scan(&kind);
 err!=nil||kind!="legacy-unknown"{t.Fatal("legacy relation rewritten",err)}
 if _,err=DB.Exec("UPDATE md_label SET label_name=CAST(? AS TEXT) WHERE label_id=?",[]byte{0xff},label.LabelID);err!=nil{t.Fatal(err)}
 if _,err=ReadLabelCreationReview(label.LabelID,1);!errors.Is(err,ErrLabelCreationReviewBound){t.Fatal("malformed name accepted",err)}
 var raw []byte
 if err=DB.QueryRow("SELECT CAST(label_name AS BLOB) FROM md_label WHERE label_id=?",label.LabelID).Scan(&raw);
 err!=nil||!bytes.Equal(raw,[]byte{0xff}){t.Fatal("malformed original bytes changed",err)}
}
