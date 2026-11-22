package models

import (
 "reflect"
 "testing"
)

type searchEnvelopeRow struct{ID,Member int64;Title,Body,Description []byte}
func searchEnvelopeSnapshot(t *testing.T)[]searchEnvelopeRow{
 t.Helper();rows,err:=DB.Query("SELECT blog_id,member_id,CAST(blog_title AS BLOB),CAST(blog_content AS BLOB),CAST(COALESCE(blog_desc,'') AS BLOB) FROM md_blogs ORDER BY blog_id")
 if err!=nil{t.Fatal(err)};defer rows.Close()
 out:=[]searchEnvelopeRow{}
 for rows.Next(){var r searchEnvelopeRow;if err=rows.Scan(&r.ID,&r.Member,&r.Title,&r.Body,&r.Description);err!=nil{t.Fatal(err)};out=append(out,r)}
 if err=rows.Err();err!=nil{t.Fatal(err)};return out
}
func TestSearchProtectionMatchesActualEnvelopeProtocolWithoutTrimmingProse(t *testing.T){
 for _,content:=range []string{
  "ENC:v1: CipherNeedle","ENC:v2: CipherNeedle","ENC:future: CipherNeedle","ENC: CipherNeedle",
  "\ufeffENC:v1: CipherNeedle","\ufeffENC:v2: CipherNeedle","\ufeffENC:future: CipherNeedle",
  " ENC:v2: CipherNeedle","text ENC:v2: CipherNeedle","enc:v2: CipherNeedle",
  "\ufeff\ufeffENC:v2: CipherNeedle",
 }{
  t.Run(content,func(t *testing.T){
   initAssetTestDB(t)
   blog:=&Blog{BlogTitle:"Visible title",BlogIdentify:"search-envelope-exact",MemberID:1,
    BlogContent:content,BlogType:"note",EditorType:"markdown"}
   if err:=blog.Insert();err!=nil{t.Fatal(err)}
   book:=&Book{BookName:"Container",Identify:"envelope-container",MemberID:1}
   if err:=book.Insert();err!=nil{t.Fatal(err)}
   doc:=&Document{DocumentName:"DocVisible",Identify:"envelope-document",BookID:book.BookID,
    MemberID:1,DocType:"markdown",Markdown:content}
   if err:=doc.Insert();err!=nil{t.Fatal(err)}
   var docBefore []byte
   if err:=DB.QueryRow("SELECT CAST(markdown AS BLOB) FROM md_documents WHERE document_id=?",doc.DocumentID).Scan(&docBefore);err!=nil{t.Fatal(err)}
   before:=searchEnvelopeSnapshot(t)
   hidden,err:=GlobalSearch(1,"CipherNeedle");if err!=nil{t.Fatal(err)}
   protected:=ownedProtected(content)
   if protected&&len(hidden.Blogs)!=0{t.Fatal("protected body produced a search hit",hidden.Blogs)}
   if !protected&&(len(hidden.Blogs)!=1||hidden.Blogs[0].Snippet==""){t.Fatal("ordinary prose was incorrectly hidden",hidden.Blogs)}
   if protected&&len(hidden.Documents)!=0{t.Fatal("protected document body produced a hit")}
   if !protected&&len(hidden.Documents)!=1{t.Fatal("ordinary document prose hidden")}
   docTitle,err:=GlobalSearch(1,"DocVisible");if err!=nil{t.Fatal(err)}
   if len(docTitle.Documents)!=1{t.Fatal("document title disappeared")}
   if protected&&docTitle.Documents[0].Snippet!=""{t.Fatal("protected document snippet exposed")}
   var docAfter []byte
   if err:=DB.QueryRow("SELECT CAST(markdown AS BLOB) FROM md_documents WHERE document_id=?",doc.DocumentID).Scan(&docAfter);err!=nil{t.Fatal(err)}
   if !reflect.DeepEqual(docBefore,docAfter){t.Fatal("document source changed")}

   title,err:=GlobalSearch(1,"Visible");if err!=nil{t.Fatal(err)}
   if len(title.Blogs)!=1{t.Fatal("protected title disappeared",title.Blogs)}
   if protected&&title.Blogs[0].Snippet!=""{t.Fatal("title hit exposed ciphertext",title.Blogs[0].Snippet)}
   if !reflect.DeepEqual(before,searchEnvelopeSnapshot(t)){t.Fatal("search changed exact original rows")}
   if _,err=DB.Exec("UPDATE md_blogs SET blog_desc='PublicNeedle description' WHERE blog_id=?",blog.BlogID);err!=nil{t.Fatal(err)}
   publicBefore:=searchEnvelopeSnapshot(t)
   desc,err:=GlobalSearch(1,"PublicNeedle");if err!=nil{t.Fatal(err)}
   if len(desc.Blogs)!=1||desc.Blogs[0].Snippet!="PublicNeedle description"{t.Fatal("public description search changed",desc.Blogs)}
   if !reflect.DeepEqual(publicBefore,searchEnvelopeSnapshot(t)){t.Fatal("description search changed original rows")}
  })
 }
}
