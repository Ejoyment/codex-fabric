package crypto

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"errors"
	"fmt"
	"hash"
	"io"

	"golang.org/x/crypto/curve25519"
	"golang.org/x/crypto/hkdf"
	"golang.org/x/crypto/pbkdf2"
)

var (
	// ErrInvalidKey is returned when a key is invalid
	ErrInvalidKey = errors.New("invalid key")
	// ErrDecryptionFailed is returned when decryption fails
	ErrDecryptionFailed = errors.New("decryption failed")
	// ErrInvalidSignature is returned when signature verification fails
	ErrInvalidSignature = errors.New("invalid signature")
)

const (
	// KeySize for AES-256
	KeySize = 32
	// NonceSize for GCM
	NonceSize = 12
	// SaltSize for key derivation
	SaltSize = 32
	// SessionIDSize for session identifiers
	SessionIDSize = 16
)

// KeyPair represents an Ed25519 key pair for signing and key exchange
type KeyPair struct {
	PublicKey  ed25519.PublicKey
	PrivateKey ed25519.PrivateKey
}

// SessionKeys holds the keys for a secure session
type SessionKeys struct {
	EncryptionKey []byte
	SigningKey    []byte
	SessionID     string
}

// GenerateKeyPair generates a new Ed25519 key pair
func GenerateKeyPair() (*KeyPair, error) {
	publicKey, privateKey, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		return nil, fmt.Errorf("failed to generate key pair: %w", err)
	}

	return &KeyPair{
		PublicKey:  publicKey,
		PrivateKey: privateKey,
	}, nil
}

// GenerateSessionKeys creates session keys using HKDF
func GenerateSessionKeys(sharedSecret []byte, info []byte) (*SessionKeys, error) {
	salt := make([]byte, SaltSize)
	if _, err := rand.Read(salt); err != nil {
		return nil, fmt.Errorf("failed to generate salt: %w", err)
	}

	hkdfReader := hkdf.New(sha256.New, sharedSecret, salt, info)

	encryptionKey := make([]byte, KeySize)
	if _, err := io.ReadFull(hkdfReader, encryptionKey); err != nil {
		return nil, fmt.Errorf("failed to derive encryption key: %w", err)
	}

	signingKey := make([]byte, KeySize)
	if _, err := io.ReadFull(hkdfReader, signingKey); err != nil {
		return nil, fmt.Errorf("failed to derive signing key: %w", err)
	}

	sessionID := make([]byte, SessionIDSize)
	if _, err := io.ReadFull(hkdfReader, sessionID); err != nil {
		return nil, fmt.Errorf("failed to derive session ID: %w", err)
	}

	return &SessionKeys{
		EncryptionKey: encryptionKey,
		SigningKey:    signingKey,
		SessionID:     hex.EncodeToString(sessionID),
	}, nil
}

// ECDH performs Elliptic Curve Diffie-Hellman key exchange
func ECDH(privateKey, peerPublicKey []byte) ([]byte, error) {
	sharedSecret, err := curve25519.X25519(privateKey[:32], peerPublicKey)
	if err != nil {
		return nil, fmt.Errorf("ECDH failed: %w", err)
	}

	return sharedSecret, nil
}

// Encrypt encrypts plaintext using AES-256-GCM
func Encrypt(plaintext, key []byte) ([]byte, error) {
	if len(key) != KeySize {
		return nil, ErrInvalidKey
	}

	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, fmt.Errorf("failed to create cipher: %w", err)
	}

	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("failed to create GCM: %w", err)
	}

	nonce := make([]byte, NonceSize)
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return nil, fmt.Errorf("failed to generate nonce: %w", err)
	}

	ciphertext := gcm.Seal(nonce, nonce, plaintext, nil)
	return ciphertext, nil
}

// Decrypt decrypts ciphertext using AES-256-GCM
func Decrypt(ciphertext, key []byte) ([]byte, error) {
	if len(key) != KeySize {
		return nil, ErrInvalidKey
	}

	if len(ciphertext) < NonceSize {
		return nil, ErrDecryptionFailed
	}

	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, fmt.Errorf("failed to create cipher: %w", err)
	}

	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("failed to create GCM: %w", err)
	}

	nonce := ciphertext[:NonceSize]
	data := ciphertext[NonceSize:]

	plaintext, err := gcm.Open(nil, nonce, data, nil)
	if err != nil {
		return nil, ErrDecryptionFailed
	}

	return plaintext, nil
}

// Sign creates a digital signature for a message
func Sign(message []byte, privateKey ed25519.PrivateKey) []byte {
	return ed25519.Sign(privateKey, message)
}

// Verify verifies a digital signature
func Verify(message, signature []byte, publicKey ed25519.PublicKey) bool {
	return ed25519.Verify(publicKey, message, signature)
}

// Hash creates a SHA-256 hash of the input
func Hash(data []byte) []byte {
	hash := sha256.Sum256(data)
	return hash[:]
}

// GenerateRandomBytes generates cryptographically secure random bytes
func GenerateRandomBytes(n int) ([]byte, error) {
	bytes := make([]byte, n)
	if _, err := rand.Read(bytes); err != nil {
		return nil, fmt.Errorf("failed to generate random bytes: %w", err)
	}
	return bytes, nil
}

// DeriveKey derives a key from a password using PBKDF2
func DeriveKey(password, salt []byte, iterations int) ([]byte, error) {
	key := pbkdf2.Key(password, salt, iterations, KeySize, sha256.New)
	return key, nil
}

// EncryptWithPassword encrypts data using a password
func EncryptWithPassword(plaintext []byte, password string) ([]byte, error) {
	salt, err := GenerateRandomBytes(SaltSize)
	if err != nil {
		return nil, err
	}

	key, err := DeriveKey([]byte(password), salt, 100000) // 100k iterations
	if err != nil {
		return nil, err
	}

	ciphertext, err := Encrypt(plaintext, key)
	if err != nil {
		return nil, err
	}

	// Prepend salt to ciphertext
	result := append(salt, ciphertext...)
	return result, nil
}

// DecryptWithPassword decrypts data using a password
func DecryptWithPassword(ciphertext []byte, password string) ([]byte, error) {
	if len(ciphertext) < SaltSize {
		return nil, ErrDecryptionFailed
	}

	salt := ciphertext[:SaltSize]
	data := ciphertext[SaltSize:]

	key, err := DeriveKey([]byte(password), salt, 100000)
	if err != nil {
		return nil, err
	}

	return Decrypt(data, key)
}

// ValidateKeyPair validates that a key pair is valid
func ValidateKeyPair(keyPair *KeyPair) bool {
	if len(keyPair.PrivateKey) != ed25519.PrivateKeySize {
		return false
	}
	if len(keyPair.PublicKey) != ed25519.PublicKeySize {
		return false
	}

	// Verify that the public key matches the private key
	derivedPublic := keyPair.PrivateKey.Public().(ed25519.PublicKey)
	return equal(derivedPublic, keyPair.PublicKey)
}

// equal performs constant-time comparison of two byte slices
func equal(a, b []byte) bool {
	return len(a) == len(b) && subtle.ConstantTimeCompare(a, b) == 1
}

// ImportPublicKey imports a hex-encoded public key
func ImportPublicKey(hexKey string) (ed25519.PublicKey, error) {
	keyBytes, err := hex.DecodeString(hexKey)
	if err != nil {
		return nil, fmt.Errorf("failed to decode hex key: %w", err)
	}

	if len(keyBytes) != ed25519.PublicKeySize {
		return nil, fmt.Errorf("invalid public key size: got %d, want %d", len(keyBytes), ed25519.PublicKeySize)
	}

	return ed25519.PublicKey(keyBytes), nil
}

// ExportPublicKey exports a public key to hex string
func ExportPublicKey(key ed25519.PublicKey) string {
	return hex.EncodeToString(key)
}

// ImportPrivateKey imports a hex-encoded private key
func ImportPrivateKey(hexKey string) (ed25519.PrivateKey, error) {
	keyBytes, err := hex.DecodeString(hexKey)
	if err != nil {
		return nil, fmt.Errorf("failed to decode hex key: %w", err)
	}

	if len(keyBytes) != ed25519.PrivateKeySize {
		return nil, fmt.Errorf("invalid private key size: got %d, want %d", len(keyBytes), ed25519.PrivateKeySize)
	}

	return ed25519.PrivateKey(keyBytes), nil
}

// ExportPrivateKey exports a private key to hex string
func ExportPrivateKey(key ed25519.PrivateKey) string {
	return hex.EncodeToString(key)
}

// SecureRandomString generates a cryptographically secure random hex string
func SecureRandomString(length int) (string, error) {
	bytes, err := GenerateRandomBytes(length / 2)
	if err != nil {
		return "", err
	}
	return hex.EncodeToString(bytes), nil
}

// KeyWrap wraps a key using AES-GCM
func KeyWrap(key, wrappingKey []byte) ([]byte, error) {
	return Encrypt(key, wrappingKey)
}

// KeyUnwrap unwraps a key using AES-GCM
func KeyUnwrap(wrappedKey, wrappingKey []byte) ([]byte, error) {
	return Decrypt(wrappedKey, wrappingKey)
}