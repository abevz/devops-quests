package main
import("fmt";"net";"net/http";"os";"time")
func main(){
 if len(os.Args)>1 && os.Args[1]=="crash" { _,e:=os.ReadFile("/config/app.yaml");fmt.Println(e);os.Exit(3) }
 os.WriteFile("/data/marker",[]byte("original\n"),0600)
 go func(){for{_,e:=os.ReadFile("/config/app.yaml");if e!=nil{fmt.Println(e)};time.Sleep(time.Second)}}()
 go func(){l,e:=net.Listen("tcp",":8082");if e!=nil{panic(e)};for{c,e:=l.Accept();if e!=nil{continue};go func(c net.Conn){b:=make([]byte,1024);c.Read(b);c.(*net.TCPConn).SetLinger(0);c.Close()}(c)}}()
 http.HandleFunc("/",func(w http.ResponseWriter,r *http.Request){fmt.Fprintln(w,"ok")})
 panic(http.ListenAndServe(":8080",nil))
}
