package core_service

import (
	"context"
	"crypto/sha512"
	"encoding/hex"
	"google.golang.org/grpc/metadata"
	"strings"
)

func SnakeCaseToCamelCase(s string) string {
	parts := strings.Split(s, "_")
	for i := 0; i < len(parts); i++ {
		parts[i] = strings.ToTitle(parts[i])
	}
	return strings.Join(parts, "")
}

func MakePasswordHash(src string) string {
	sha512Hash := sha512.New()
	sha512Hash.Write([]byte(src))
	sha512Data := sha512Hash.Sum(nil)
	hexString := strings.ToLower(hex.EncodeToString(sha512Data))
	return hexString
}

func PartialStringMatch(partial bool, candidate, filter string) bool {
	if !partial && filter != "" {
		return candidate == filter
	} else if partial && filter != "" {
		normalizedCandidate := strings.ReplaceAll(strings.ToLower(candidate), "ё", "е")
		normalizedFilter := strings.ReplaceAll(strings.ToLower(filter), "ё", "е")
		return strings.Contains(normalizedCandidate, normalizedFilter)
	} else {
		return true
	}
}

func UpdateContextWithSession(ctx context.Context, session *Session) context.Context {
	oldMd, _ := metadata.FromOutgoingContext(ctx)
	md := metadata.Pairs("session", session.Cookie)
	return metadata.NewOutgoingContext(ctx, metadata.Join(oldMd, md))
}