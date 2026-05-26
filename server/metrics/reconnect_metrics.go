// Package metrics provides Prometheus instrumentation for the reconnection system.
package metrics

import (
	"net/http"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
	// TombstoneCreatedTotal counts tombstones created on disconnect.
	TombstoneCreatedTotal = promauto.NewCounter(prometheus.CounterOpts{
		Name: "tombstone_created_total",
		Help: "Total number of tombstones created on player disconnect.",
	})

	// TombstoneResumedTotal counts successful resume operations.
	TombstoneResumedTotal = promauto.NewCounter(prometheus.CounterOpts{
		Name: "tombstone_resumed_total",
		Help: "Total number of successful tombstone resume operations.",
	})

	// TombstoneExpiredTotal counts tombstones that expired without resume.
	TombstoneExpiredTotal = promauto.NewCounter(prometheus.CounterOpts{
		Name: "tombstone_expired_total",
		Help: "Total number of tombstones that expired without successful resume.",
	})

	// ResumeFailedTotal counts failed resume attempts.
	ResumeFailedTotal = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "resume_failed_total",
		Help: "Total number of failed resume attempts, partitioned by reason.",
	}, []string{"reason"})

	// ActiveTombstones tracks the current number of active tombstones.
	ActiveTombstones = promauto.NewGauge(prometheus.GaugeOpts{
		Name: "tombstone_active_current",
		Help: "Current number of active (unresolved) tombstones.",
	})

	// ResumeLatency tracks resume operation duration.
	ResumeLatency = promauto.NewHistogram(prometheus.HistogramOpts{
		Name:    "tombstone_resume_duration_seconds",
		Help:    "Duration of resume operations in seconds.",
		Buckets: prometheus.DefBuckets,
	})
)

const (
	ReasonExpired        = "expired"
	ReasonInvalidToken   = "invalid_token"
	ReasonRoomNotFound   = "room_not_found"
	ReasonBindFailed     = "bind_failed"
	ReasonPlayerIDFormat = "player_id_format"
	ReasonUnknown        = "unknown"
)

// StartMetricsServer starts a standalone HTTP server for Prometheus metrics scraping.
// Runs in a goroutine, panics if the port cannot be bound.
func StartMetricsServer(addr string) {
	if addr == "" {
		addr = ":9090"
	}

	mux := http.NewServeMux()
	mux.Handle("/metrics", promhttp.Handler())
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("OK"))
	})

	go func() {
		if err := http.ListenAndServe(addr, mux); err != nil {
			// Log but don't crash — metrics are auxiliary
			panic("Metrics server failed: " + err.Error())
		}
	}()
}
