package models

import (
 "database/sql"
 "path/filepath"
 "testing"
 "time"
)
func isolatedVisitDB(t *testing.T)*sql.DB{
 t.Helper()
 db,err:=sql.Open("sqlite",filepath.Join(t.TempDir(),"visits.db"))
 if err!=nil{t.Fatal(err)}
 t.Cleanup(func(){db.Close()})
 for _,statement:=range []string{
  "CREATE TABLE md_visit_log(visit_id INTEGER PRIMARY KEY,ip TEXT, path TEXT,member_id INTEGER,visit_time TEXT,UNIQUE(ip,member_id))",
  "CREATE TABLE md_visit_daily(date TEXT PRIMARY KEY,page_views INTEGER,unique_ips INTEGER)",
  "CREATE TABLE md_visit_daily_ip(date TEXT,ip TEXT,UNIQUE(date,ip))",
 }{if _,err:=db.Exec(statement);err!=nil{t.Fatal(err)}}
 return db
}
func visitBatch()[]VisitLog{
 return []VisitLog{{IP:"192.0.2.1",Path:"/one",MemberID:1,VisitTime:time.Date(2026,11,11,12,0,0,0,time.UTC)},
 {IP:"192.0.2.2",Path:"/two",MemberID:2,VisitTime:time.Date(2026,11,11,13,0,0,0,time.UTC)}}
}
func TestVisitFlushNilAndClosedDBFailSafeWithoutDisablingWriter(t *testing.T){
 flushVisitLogsDB(nil,visitBatch())
 recalcDailyUniqueIPsDB(nil,"2026-11-11")
 db:=isolatedVisitDB(t)
 if err:=db.Close();err!=nil{t.Fatal(err)}
 flushVisitLogsDB(db,visitBatch())
 recalcDailyUniqueIPsDB(db,"2026-11-11")
}
func TestVisitFlushUsesCapturedDatabaseForCommitAndDailyRecount(t *testing.T){
 db:=isolatedVisitDB(t)
 flushVisitLogsDB(db,visitBatch())
 var visits,pages,unique int
 if err:=db.QueryRow("SELECT COUNT(*) FROM md_visit_log").Scan(&visits);err!=nil{t.Fatal(err)}
 if err:=db.QueryRow("SELECT page_views,unique_ips FROM md_visit_daily WHERE date='2026-11-11'").Scan(&pages,&unique);err!=nil{t.Fatal(err)}
 if visits!=2||pages!=2||unique!=2{t.Fatalf("real visit transaction/recount lost: %d/%d/%d",visits,pages,unique)}
}
func TestVisitFlushWriteFailureRollsBackEntireBatch(t *testing.T){
 db:=isolatedVisitDB(t)
 if _,err:=db.Exec("CREATE TRIGGER reject_daily BEFORE INSERT ON md_visit_daily BEGIN SELECT RAISE(ABORT,'owned failure'); END");err!=nil{t.Fatal(err)}
 flushVisitLogsDB(db,visitBatch())
 for _,table:=range []string{"md_visit_log","md_visit_daily","md_visit_daily_ip"}{
  var count int
  if err:=db.QueryRow("SELECT COUNT(*) FROM "+table).Scan(&count);err!=nil{t.Fatal(err)}
  if count!=0{t.Fatalf("failed visit batch partially changed %s",table)}
 }
}
