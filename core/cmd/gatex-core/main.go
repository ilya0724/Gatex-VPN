// gatex-core is the desktop helper the GateX app starts with admin rights.
//
//	gatex-core run   -c config.json [-assets dir] [-watch-stdin]
//	gatex-core check -c config.json
//	gatex-core delay -c outbound-config.json [-url u] [-timeout ms]
//	gatex-core version
//
// With -watch-stdin the core exits as soon as its stdin closes, so the
// tunnel and its system routes never outlive the app that started it.
package main

import (
	"flag"
	"fmt"
	"io"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/ilya0724/gatex-vpn/core/gatexcore"
)

func main() {
	if len(os.Args) < 2 {
		usage()
	}
	cmd, args := os.Args[1], os.Args[2:]
	fs := flag.NewFlagSet(cmd, flag.ExitOnError)
	configPath := fs.String("c", "", "path to the Xray JSON config")
	assets := fs.String("assets", "", "folder with geoip.dat and geosite.dat")
	watchStdin := fs.Bool("watch-stdin", false, "exit when stdin closes")
	probeURL := fs.String("url", "https://www.gstatic.com/generate_204", "delay probe URL")
	timeout := fs.Int("timeout", 5000, "delay probe timeout, ms")
	fs.Parse(args)
	gatexcore.SetAssetDir(*assets)

	switch cmd {
	case "version":
		fmt.Println(gatexcore.Version())
	case "check":
		fail(gatexcore.CheckConfig(readConfig(*configPath)))
		fmt.Println("ok")
	case "delay":
		ms, err := gatexcore.MeasureDelay(readConfig(*configPath), *probeURL, *timeout)
		fail(err)
		fmt.Println(ms)
	case "run":
		fail(gatexcore.Start(readConfig(*configPath), 0))
		fmt.Println("started")
		// The app shows the speed from these.
		go func() {
			for range time.Tick(time.Second) {
				fmt.Println("traffic", gatexcore.Traffic())
			}
		}()
		wait(*watchStdin)
		fail(gatexcore.Stop())
	default:
		usage()
	}
}

func wait(watchStdin bool) {
	done := make(chan struct{}, 1)
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, os.Interrupt, syscall.SIGTERM)
	go func() { <-sig; done <- struct{}{} }()
	if watchStdin {
		go func() {
			io.Copy(io.Discard, os.Stdin)
			done <- struct{}{}
		}()
	}
	<-done
}

func readConfig(path string) string {
	if path == "" {
		fail(fmt.Errorf("-c is required"))
	}
	data, err := os.ReadFile(path)
	fail(err)
	return string(data)
}

func fail(err error) {
	if err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}

func usage() {
	fmt.Fprintln(os.Stderr, "usage: gatex-core run|check|delay|version [-c config.json]")
	os.Exit(2)
}
