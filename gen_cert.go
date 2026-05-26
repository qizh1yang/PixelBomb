package main

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"fmt"
	"math/big"
	"os"
	"path/filepath"
	"time"
)

func main() {
	fmt.Println("[SSL Generator] Generating self-signed ECDSA private key...")
	privateKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		fmt.Printf("Failed to generate private key: %v\n", err)
		os.Exit(1)
	}

	serialNumberLimit := new(big.Int).Lsh(big.NewInt(1), 128)
	serialNumber, err := rand.Int(rand.Reader, serialNumberLimit)
	if err != nil {
		fmt.Printf("Failed to generate serial number: %v\n", err)
		os.Exit(1)
	}

	template := x509.Certificate{
		SerialNumber: serialNumber,
		Subject: pkix.Name{
			Organization: []string{"PixelBomb Developer Studio"},
			CommonName:   "localhost",
		},
		NotBefore:             time.Now().Add(-10 * time.Minute), // Prevent clock skew issues
		NotAfter:              time.Now().Add(365 * 24 * time.Hour),
		KeyUsage:              x509.KeyUsageKeyEncipherment | x509.KeyUsageDigitalSignature,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		BasicConstraintsValid: true,
		DNSNames:              []string{"localhost", "127.0.0.1"},
	}

	fmt.Println("[SSL Generator] Creating self-signed certificate...")
	derBytes, err := x509.CreateCertificate(rand.Reader, &template, &template, &privateKey.PublicKey, privateKey)
	if err != nil {
		fmt.Printf("Failed to create certificate DER: %v\n", err)
		os.Exit(1)
	}

	sslDir := "ssl"
	if err := os.MkdirAll(sslDir, 0755); err != nil {
		fmt.Printf("Failed to create directory '%s': %v\n", sslDir, err)
		os.Exit(1)
	}

	// Write cert.pem
	certPath := filepath.Join(sslDir, "cert.pem")
	certOut, err := os.Create(certPath)
	if err != nil {
		fmt.Printf("Failed to open %s for writing: %v\n", certPath, err)
		os.Exit(1)
	}
	defer certOut.Close()
	
	if err := pem.Encode(certOut, &pem.Block{Type: "CERTIFICATE", Bytes: derBytes}); err != nil {
		fmt.Printf("Failed to PEM-encode cert: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("[SSL Generator] Successfully created %s\n", certPath)

	// Write key.pem
	keyPath := filepath.Join(sslDir, "key.pem")
	keyOut, err := os.OpenFile(keyPath, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0600)
	if err != nil {
		fmt.Printf("Failed to open %s for writing: %v\n", keyPath, err)
		os.Exit(1)
	}
	defer keyOut.Close()

	privBytes, err := x509.MarshalECPrivateKey(privateKey)
	if err != nil {
		fmt.Printf("Failed to marshal ECDSA private key: %v\n", err)
		os.Exit(1)
	}
	
	if err := pem.Encode(keyOut, &pem.Block{Type: "EC PRIVATE KEY", Bytes: privBytes}); err != nil {
		fmt.Printf("Failed to PEM-encode private key: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("[SSL Generator] Successfully created %s\n", keyPath)
	fmt.Println("[SSL Generator] All self-signed SSL files generated successfully in ./ssl/ directory!")
}
