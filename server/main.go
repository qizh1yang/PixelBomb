package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"bomberman-server/logic"
	"bomberman-server/metrics"
	"bomberman-server/storage"

	"github.com/lonng/nano"
	"github.com/lonng/nano/component"
	"github.com/lonng/nano/serialize/json"
)

func printBanner() {
	banner, err := os.ReadFile("banner.txt")
	if err != nil {
		log.Println("PixelBomb Server starting...")
		return
	}
	fmt.Print(string(banner))
}

func main() {
	printBanner()

	// ── 1. Initialize Redis tombstone store (optional, falls back to memory) ──
	redisStore := storage.NewRedisTombstoneStore()
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	if err := redisStore.Ping(ctx); err != nil {
		log.Printf("[Server] Redis not available (%v) — using in-memory tombstone store", err)
	} else {
		log.Println("[Server] Redis connected — using Redis-backed tombstone store")
		logic.UseRedisStore(redisStore)
	}

	// ── 2. Start Prometheus metrics server ──
	metricsAddr := os.Getenv("METRICS_PORT")
	if metricsAddr == "" {
		metricsAddr = ":9090"
	}
	if !strings.HasPrefix(metricsAddr, ":") {
		metricsAddr = ":" + metricsAddr
	}
	metrics.StartMetricsServer(metricsAddr)
	log.Printf("[Server] Prometheus metrics endpoint at %s/metrics", metricsAddr)

	// ── 3. Initialize Nano components ──
	userComp := logic.NewUserComponent()
	roomComp := logic.NewRoomComponent(userComp)

	components := &component.Components{}
	components.Register(userComp, component.WithName("User"))
	components.Register(roomComp, component.WithName("Room"))

	// ── 4. Health check server ──
	go func() {
		http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
			w.Write([]byte("OK"))
		})
		if err := http.ListenAndServe(":8081", nil); err != nil {
			log.Printf("Health check server error: %v", err)
		}
	}()

	// ── 5. Launch Nano game server ──
	log.Println("[Server] Nano engine starting on :8080...")
	nano.Listen(":8080",
		nano.WithIsWebsocket(true),
		nano.WithWSPath("/ws"),
		nano.WithSerializer(json.NewSerializer()),
		nano.WithHeartbeatInterval(5*time.Second),
		nano.WithComponents(components),
		nano.WithDebugMode(),
	)
}
