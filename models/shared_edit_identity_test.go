package models
import(
 "context"
 "encoding/base64"
 "errors"
 "reflect"
 "strings"
 "testing"
)
func TestTypedSharedIdentityRejectsSameContentRetarget(t *testing.T){
 initAssetTestDB(t)
 before,share,token:=sharedEditFixture(t,"markdown","")
 read,err:=ReadSharedContentIdentity(context.Background(),share.ShareIdentify,token,"");if err!=nil{t.Fatal(err)}
 other:=&Blog{BlogTitle:"Actual second target",BlogIdentify:"typed-second",BlogType:"article",EditorType:"markdown",MemberID:1,BlogContent:before.BlogContent}
 if err:=other.Insert();err!=nil{t.Fatal(err)}
 sharedSetupUpdate(t,"UPDATE md_shares SET target_id=? WHERE share_id=?",other.BlogID,share.ShareID)
 unchanged,_:=GetBlogByID(other.BlogID)
 _,err=SaveSharedContentWithIdentity(context.Background(),share.ShareIdentify,token,"new wrong target","",read.SourceSHA256,read.Identity)
 if !errors.Is(err,ErrSharedEditConflict){t.Fatal("same content retarget accepted")}
 after,_:=GetBlogByID(other.BlogID)
 if !reflect.DeepEqual(unchanged,after){t.Fatal("wrong target was mutated")}
}
func TestTypedSharedNoopPreservesGzipNULLAndMetadata(t *testing.T){
 for _,nullBody:=range []bool{false,true}{
  t.Run(map[bool]string{false:"old gzip",true:"SQL NULL"}[nullBody],func(t *testing.T){
   initAssetTestDB(t)
   blog,share,token:=sharedEditFixture(t,"html","")
   if nullBody{sharedSetupUpdate(t,"UPDATE md_blogs SET blog_content=NULL WHERE blog_id=?",blog.BlogID)}
   var raw any;var version int
   if err:=DB.QueryRow("SELECT blog_content,version FROM md_blogs WHERE blog_id=?",blog.BlogID).Scan(&raw,&version);err!=nil{t.Fatal(err)}
   metadata:=sharedEditMetadata(t,blog.BlogID)
   read,err:=ReadSharedContentIdentity(context.Background(),share.ShareIdentify,token,"");if err!=nil{t.Fatal(err)}
   plain,err:=base64.StdEncoding.Strict().DecodeString(read.SourceBase64);if err!=nil{t.Fatal(err)}
   receipt,err:=SaveSharedContentWithIdentity(context.Background(),share.ShareIdentify,token,string(plain),"",read.SourceSHA256,read.Identity)
   if err!=nil||receipt.SourceSHA256!=read.SourceSHA256{t.Fatal("no-op receipt failed",err)}
   var after any;var afterVersion int
   if err:=DB.QueryRow("SELECT blog_content,version FROM md_blogs WHERE blog_id=?",blog.BlogID).Scan(&after,&afterVersion);err!=nil{t.Fatal(err)}
   if !reflect.DeepEqual(raw,after)||version!=afterVersion||!reflect.DeepEqual(metadata,sharedEditMetadata(t,blog.BlogID)){t.Fatal("no-op normalized raw or metadata")}
  })
 }
}
func TestTypedSharedMalformedEnvelopeAndPlainReservedPrefixNeverMutate(t *testing.T){
 for _,cipher:=range []string{"ENC:v1:malformed","ENC:v2:malformed","\ufeffENC:v999:malformed"}{
  t.Run(cipher,func(t *testing.T){
   initAssetTestDB(t);blog,share,token:=sharedEditFixture(t,"html","")
   baseline,err:=ReadSharedContentIdentity(context.Background(),share.ShareIdentify,token,"");if err!=nil{t.Fatal(err)}
   sharedSetupUpdate(t,"UPDATE md_blogs SET blog_content=? WHERE blog_id=?",cipher,blog.BlogID)
   if _,err:=ReadSharedContentIdentity(context.Background(),share.ShareIdentify,token,"");!errors.Is(err,ErrSharedEditPassword){t.Fatal("cipher appeared plain",err)}
   if _,err:=SaveSharedContentWithIdentity(context.Background(),share.ShareIdentify,token,"plain","",baseline.SourceSHA256,baseline.Identity);!errors.Is(err,ErrSharedEditPassword){t.Fatal("stale snapshot overwrote cipher",err)}
   var after string;DB.QueryRow("SELECT blog_content FROM md_blogs WHERE blog_id=?",blog.BlogID).Scan(&after)
   if after!=cipher{t.Fatal("cipher mutated")}
  })
 }
 initAssetTestDB(t);_,share,token:=sharedEditFixture(t,"html","")
 read,_:=ReadSharedContentIdentity(context.Background(),share.ShareIdentify,token,"")
 if _,err:=SaveSharedContentWithIdentity(context.Background(),share.ShareIdentify,token,"\ufeffENC:v3:plain","",read.SourceSHA256,read.Identity);!errors.Is(err,ErrSharedEditInput){t.Fatal("reserved source accepted")}
}
func TestTypedSharedExactSourceAndLegacyCompatibility(t *testing.T){
 initAssetTestDB(t);blog,share,token:=sharedEditFixture(t,"html","passphrase")
 read,err:=ReadSharedContentIdentity(context.Background(),share.ShareIdentify,token,"passphrase");if err!=nil{t.Fatal(err)}
 metadata:=sharedEditMetadata(t,blog.BlogID)
 source:="\ufeff<p>emoji🙂\r\n</p>"
 receipt,err:=SaveSharedContentWithIdentity(context.Background(),share.ShareIdentify,token,source,"passphrase",read.SourceSHA256,read.Identity)
 if err!=nil{t.Fatal(err)}
 reread,err:=ReadSharedContentIdentity(context.Background(),share.ShareIdentify,token,"passphrase");if err!=nil{t.Fatal(err)}
 plain,_:=base64.StdEncoding.Strict().DecodeString(reread.SourceBase64)
 if string(plain)!=source||receipt.SourceSHA256!=reread.SourceSHA256||!reflect.DeepEqual(metadata,sharedEditMetadata(t,blog.BlogID)){t.Fatal("bytes/metadata changed")}
 // Existing optional-CAS legacy wrapper is neither removed nor silently forced.
 if _,err:=SaveSharedContent(share.ShareIdentify,token,"<p>legacy</p>","passphrase",nil);err!=nil{t.Fatal("legacy regression",err)}
}
func TestTypedSharedStoredBudgetBeforeDecode(t *testing.T){
 initAssetTestDB(t);blog,share,token:=sharedEditFixture(t,"html","")
 sharedSetupUpdate(t,"UPDATE md_blogs SET blog_content=? WHERE blog_id=?",strings.Repeat("x",32*1024*1024+1),blog.BlogID)
 if _,err:=ReadSharedContentIdentity(context.Background(),share.ShareIdentify,token,"");!errors.Is(err,ErrSharedEditInput){t.Fatal("stored bound not enforced")}
}
