// Package gatexcore wraps Xray-core for the GateX client.
//
// The exported API uses only types gomobile can bind, so the same package
// backs the Android library (gomobile bind) and the desktop binary
// (cmd/gatex-core).
package gatexcore

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	xnet "github.com/xtls/xray-core/common/net"
	"github.com/xtls/xray-core/common/platform"
	"github.com/xtls/xray-core/core"
	"github.com/xtls/xray-core/features/stats"

	// Registers every Xray protocol, transport and the JSON config loader.
	_ "github.com/xtls/xray-core/main/distro/all"
)

var (
	mu       sync.Mutex
	instance *core.Instance
)

// SetAssetDir points Xray at the folder with geoip.dat and geosite.dat.
func SetAssetDir(dir string) {
	if dir != "" {
		os.Setenv(platform.AssetLocation, dir)
	}
}

// Start runs Xray with the given JSON config. tunFd is the TUN file
// descriptor handed over by the platform (Android VpnService); pass 0 or a
// negative value when Xray creates the TUN itself (desktop).
func Start(configJSON string, tunFd int) error {
	mu.Lock()
	defer mu.Unlock()
	if instance != nil {
		return errors.New("core is already running")
	}
	if tunFd > 0 {
		os.Setenv(platform.TunFdKey, strconv.Itoa(tunFd))
	} else {
		os.Unsetenv(platform.TunFdKey)
	}
	inst, err := core.StartInstance("json", []byte(configJSON))
	if err != nil {
		return err
	}
	instance = inst
	return nil
}

// Stop shuts the running instance down. It is a no-op when nothing runs.
func Stop() error {
	mu.Lock()
	defer mu.Unlock()
	if instance == nil {
		return nil
	}
	err := instance.Close()
	instance = nil
	return err
}

// IsRunning reports whether an instance is up.
func IsRunning() bool {
	mu.Lock()
	defer mu.Unlock()
	return instance != nil
}

func running() *core.Instance {
	mu.Lock()
	defer mu.Unlock()
	return instance
}

// Traffic returns the bytes that went up and down through the tunnel since
// Start, as "up down", or "" when nothing runs. The config turns on stats
// for the TUN inbound only, so nothing is counted twice.
func Traffic() string {
	inst := running()
	if inst == nil {
		return ""
	}
	m, _ := inst.GetFeature(stats.ManagerType()).(stats.Manager)
	if m == nil {
		return ""
	}
	var up, down int64
	m.VisitCounters(func(name string, c stats.Counter) bool {
		switch {
		case strings.HasSuffix(name, ">>>traffic>>>uplink"):
			up += c.Value()
		case strings.HasSuffix(name, ">>>traffic>>>downlink"):
			down += c.Value()
		}
		return true
	})
	return fmt.Sprintf("%d %d", up, down)
}

// Fetch GETs url through the running tunnel, by its routing rules, and
// returns the body. The app's own traffic bypasses the TUN on Android, so
// this is how it sees the internet the way the tunnel does.
func Fetch(url string, timeoutMs int) (string, error) {
	inst := running()
	if inst == nil {
		return "", errors.New("core is not running")
	}
	client := proxyClient(inst, time.Duration(timeoutMs)*time.Millisecond)
	resp, err := client.Get(url)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, 64<<10))
	return string(body), err
}

func proxyClient(inst *core.Instance, timeout time.Duration) *http.Client {
	return &http.Client{
		Timeout: timeout,
		Transport: &http.Transport{
			MaxIdleConnsPerHost: 1,
			DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
				dest, err := xnet.ParseDestination(network + ":" + addr)
				if err != nil {
					return nil, err
				}
				return core.Dial(ctx, inst, dest)
			},
		},
	}
}

// Version returns the Xray-core version compiled in.
func Version() string {
	return core.Version()
}

// CheckConfig parses and builds the config without starting it.
func CheckConfig(configJSON string) error {
	_, err := core.LoadConfig("json", strings.NewReader(configJSON))
	return err
}

// MeasureDelay starts a throwaway instance from configJSON (normally a
// single proxy outbound and no inbounds), fetches probeURL through it and
// returns the round trip in milliseconds. It returns -1 and an error when
// the server does not answer within timeoutMs.
func MeasureDelay(configJSON string, probeURL string, timeoutMs int) (int, error) {
	// Some transports can hang past the HTTP timeouts (or in Close), which
	// left the app's spinner turning forever; the caller always gets an
	// answer by this deadline.
	type result struct {
		ms  int
		err error
	}
	done := make(chan result, 1)
	go func() {
		ms, err := measureDelay(configJSON, probeURL, timeoutMs)
		done <- result{ms, err}
	}()
	timeout := time.Duration(timeoutMs) * time.Millisecond
	select {
	case r := <-done:
		return r.ms, r.err
	case <-time.After(2*timeout + 3*time.Second):
		return -1, errors.New("probe timed out")
	}
}

func measureDelay(configJSON string, probeURL string, timeoutMs int) (int, error) {
	inst, err := core.StartInstance("json", []byte(configJSON))
	if err != nil {
		return -1, err
	}
	defer func() { go inst.Close() }()

	timeout := time.Duration(timeoutMs) * time.Millisecond
	client := proxyClient(inst, timeout)
	get := func() error {
		resp, err := client.Get(probeURL)
		if err != nil {
			return err
		}
		io.Copy(io.Discard, resp.Body)
		resp.Body.Close()
		if resp.StatusCode >= 500 {
			return fmt.Errorf("probe answered %d", resp.StatusCode)
		}
		return nil
	}
	// The first request pays for the handshakes (to the server, then TLS
	// to the probe host through it), several round trips that say little
	// about the route. The second one rides the open connection, so it is
	// one round trip through the server: the ping other clients show.
	begin := time.Now()
	if err := get(); err != nil {
		// The HTTP side often fails at once ("closed pipe") while Xray is
		// still dialing; give the outbound time to log the real reason.
		if wait := timeout - time.Since(begin); wait > 0 {
			time.Sleep(min(wait, 2500*time.Millisecond))
		}
		return -1, err
	}
	cold := time.Since(begin)
	begin = time.Now()
	if err := get(); err != nil {
		return int(cold.Milliseconds()), nil
	}
	return int(time.Since(begin).Milliseconds()), nil
}
