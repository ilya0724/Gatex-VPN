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

	"github.com/xtls/xray-core/common/platform"
	"github.com/xtls/xray-core/core"
	xnet "github.com/xtls/xray-core/common/net"

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
	inst, err := core.StartInstance("json", []byte(configJSON))
	if err != nil {
		return -1, err
	}
	defer inst.Close()

	timeout := time.Duration(timeoutMs) * time.Millisecond
	client := &http.Client{
		Timeout: timeout,
		Transport: &http.Transport{
			DisableKeepAlives: true,
			DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
				dest, err := xnet.ParseDestination(network + ":" + addr)
				if err != nil {
					return nil, err
				}
				return core.Dial(ctx, inst, dest)
			},
		},
	}
	// The first request pays for the handshake, which is what users feel
	// when they connect, so it is the one we time.
	begin := time.Now()
	resp, err := client.Get(probeURL)
	if err != nil {
		// The HTTP side often fails at once ("closed pipe") while Xray is
		// still dialing; give the outbound time to log the real reason.
		if wait := timeout - time.Since(begin); wait > 0 {
			time.Sleep(min(wait, 2500*time.Millisecond))
		}
		return -1, err
	}
	io.Copy(io.Discard, resp.Body)
	resp.Body.Close()
	if resp.StatusCode >= 500 {
		return -1, fmt.Errorf("probe answered %d", resp.StatusCode)
	}
	return int(time.Since(begin).Milliseconds()), nil
}
