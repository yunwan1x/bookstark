//go:build ignore

// Public synthetic Go timestamp vectors; standard library only.
package main
import("encoding/json";"os";"runtime";"strings";"time")
func main(){
 cases:=[]string{
  "2026-11-08T01:02:03Z","2026-11-08T09:02:03+08:00",
  "2026-11-08T01:02:03.123456789Z","2026-11-08 01:02:03",
  "2026-11-08 01:02:03.123","1969-12-31T23:59:59.999999999Z",
  "1969-12-31T23:59:59.000000001Z","0001-01-01T00:00:00Z",
  "0000-01-01T00:00:00Z","9999-12-31T23:59:59.999999999Z",
  "2024-02-29T23:59:59Z","2026-02-29T00:00:00Z","2026-02-31T00:00:00Z",
  "2026-13-01T00:00:00Z","2026-11-08T24:00:00Z","2026-11-08T01:02:60Z",
  "2026-11-08T01:02:03"," 2026-11-08 01:02:03 ",
  "\ufeff2026-11-08T01:02:03Z","\u00a0\u20032026-11-08T01:02:03Z\u3000",
  "","\u00a0\t","2026-11-08T01:02:03,123+00:00",
  "2026-11-08T01:02:03.1-05:30","2026-11-08T01:02:03+23:59",
 }
 rows:=[]map[string]interface{}{}
 for _,raw:=range cases{
  text:=strings.TrimSpace(raw);var value time.Time;ok:=false
  for _,layout:=range []string{time.RFC3339Nano,time.RFC3339,"2006-01-02 15:04:05","2006-01-02T15:04:05Z07:00"}{
   t,e:=time.Parse(layout,text);if e==nil{value=t;ok=true;break}
  }
  row:=map[string]interface{}{"input":raw,"empty":text=="","ok":ok}
  if ok{row["unix_millis"]=value.UnixMilli()}
  rows=append(rows,row)
 }
 out,e:=os.OpenFile("legacy-time-vectors.json",os.O_WRONLY|os.O_CREATE|os.O_EXCL,0600);if e!=nil{panic(e)}
 defer out.Close()
 encoder:=json.NewEncoder(out);encoder.SetIndent("","  ")
 if e=encoder.Encode(map[string]interface{}{"go_version":runtime.Version(),"synthetic_only":true,"vectors":rows});e!=nil{panic(e)}
}
