package gatexcore

import (
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"
)

func TestTrafficAndFetch(t *testing.T) {
	site := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		io.WriteString(w, strings.Repeat("gatex ", 1000))
	}))
	defer site.Close()

	cfg := `{"log":{"loglevel":"none"},"stats":{},
"policy":{"system":{"statsInboundUplink":true,"statsInboundDownlink":true}},
"inbounds":[{"tag":"tun-in","protocol":"socks","listen":"127.0.0.1","port":18666}],
"outbounds":[{"protocol":"freedom"}]}`
	if err := Start(cfg, 0); err != nil {
		t.Fatal(err)
	}
	defer Stop()

	body, err := Fetch(site.URL, 3000)
	if err != nil || !strings.HasPrefix(body, "gatex") {
		t.Fatalf("fetch: %q %v", body, err)
	}

	// Traffic counts what comes in through the inbound.
	proxy, _ := url.Parse("socks5://127.0.0.1:18666")
	c := &http.Client{Transport: &http.Transport{Proxy: http.ProxyURL(proxy), DisableKeepAlives: true}}
	resp, err := c.Get(site.URL)
	if err != nil {
		t.Fatal(err)
	}
	io.Copy(io.Discard, resp.Body)
	resp.Body.Close()
	time.Sleep(300 * time.Millisecond)
	var up, down int
	if n, _ := fmt.Sscan(Traffic(), &up, &down); n != 2 || up == 0 || down < 6000 {
		t.Fatalf("traffic %q", Traffic())
	}
}
