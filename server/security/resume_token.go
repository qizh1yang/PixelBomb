// Package security provides cryptographic utilities for resume token generation and verification.
package security

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"strings"
	"time"
)

// DefaultTombstoneTTL is the tombstone lifetime before hard cleanup.
const DefaultTombstoneTTL = 30 * time.Second

// HMACSecret is the server-side secret key for signing resume tokens.
// Set via SetHMACSecret before use, or a random one is generated on first call.
var HMACSecret []byte

func init() {
	HMACSecret = make([]byte, 32)
	if _, err := rand.Read(HMACSecret); err != nil {
		copy(HMACSecret, []byte("pixelbomb-default-hmac-secret-32b"))
	}
}

// SetHMACSecret allows overriding the HMAC secret (e.g., from config or env).
func SetHMACSecret(secret []byte) {
	if len(secret) < 16 {
		panic("HMAC secret must be at least 16 bytes")
	}
	HMACSecret = make([]byte, len(secret))
	copy(HMACSecret, secret)
}

// ResumeToken holds the parsed components of a resume token.
type ResumeToken struct {
	Random    string // base64url-encoded 32 random bytes
	Signature string // base64url-encoded HMAC-SHA256
	ExpireAt  int64  // unix timestamp
}

// String reconstructs the full token string: random.signature.expire
func (rt *ResumeToken) String() string {
	return fmt.Sprintf("%s.%s.%d", rt.Random, rt.Signature, rt.ExpireAt)
}

// GenerateResumeToken creates a cryptographically secure resume token.
//
// Format: base64url(32_random_bytes).base64url(hmac_sha256(uid|roomID|expireAt))
//
// The random prefix (256 bits) prevents guessing.
// The HMAC signature prevents forgery.
// The embedded expiry timestamp enables offline validation.
func GenerateResumeToken(uid int64, roomID string) *ResumeToken {
	randomBytes := make([]byte, 32)
	if _, err := rand.Read(randomBytes); err != nil {
		// Fallback: mix time + ids (should never happen on modern systems)
		fallback := fmt.Sprintf("%d.%s.%d", uid, roomID, time.Now().UnixNano())
		copy(randomBytes, []byte(fallback))
	}

	expireAt := time.Now().Add(DefaultTombstoneTTL).Unix()
	payload := base64.RawURLEncoding.EncodeToString(randomBytes)
	signature := computeSignature(uid, roomID, expireAt)

	return &ResumeToken{
		Random:    payload,
		Signature: signature,
		ExpireAt:  expireAt,
	}
}

// ParseResumeToken splits a token string into its components.
// Returns nil if the format is invalid.
func ParseResumeToken(token string) *ResumeToken {
	// Split into at most 3 parts (random, signature, expire)
	idx1 := strings.IndexByte(token, '.')
	if idx1 < 0 {
		return nil
	}
	idx2 := strings.IndexByte(token[idx1+1:], '.')
	if idx2 < 0 {
		return nil
	}
	idx2 += idx1 + 1

	random := token[:idx1]
	signature := token[idx1+1 : idx2]
	expireStr := token[idx2+1:]

	if len(random) == 0 || len(signature) == 0 {
		return nil
	}

	var expireAt int64
	if _, err := fmt.Sscanf(expireStr, "%d", &expireAt); err != nil {
		return nil
	}

	return &ResumeToken{
		Random:    random,
		Signature: signature,
		ExpireAt:  expireAt,
	}
}

// VerifyResumeToken validates the HMAC signature of a resume token against the
// provided uid and roomID. Returns true if the token is authentic and unexpired.
func VerifyResumeToken(tokenStr string, uid int64, roomID string) bool {
	rt := ParseResumeToken(tokenStr)
	if rt == nil {
		return false
	}

	// Check expiry
	if time.Now().Unix() > rt.ExpireAt {
		return false
	}

	// Verify HMAC signature
	expectedSig := computeSignature(uid, roomID, rt.ExpireAt)
	return hmac.Equal([]byte(expectedSig), []byte(rt.Signature))
}

// computeSignature returns the base64url-encoded HMAC-SHA256 of "uid|roomID|expireAt".
func computeSignature(uid int64, roomID string, expireAt int64) string {
	mac := hmac.New(sha256.New, HMACSecret)
	fmt.Fprintf(mac, "%d|%s|%d", uid, roomID, expireAt)
	return base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}
