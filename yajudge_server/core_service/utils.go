package core_service

import (
	"context"
	"crypto/sha512"
	"database/sql"
	"encoding/hex"
	"fmt"
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

func MakeEntryCopyName(db *sql.DB, tableName string, entryName string) (string, error) {
	const copyPrefix = "Копия"
	const limit = 100
	i := 1
	for i=1; i<limit ; i++ {
		testName := fmt.Sprintf("%s %d %s", copyPrefix, i, entryName)
		q, err := db.Query("select id from "+tableName+" where name=$1", testName)
		if err != nil {
			return "", err
		}
		found := q.Next()
		q.Close()
		if !found {
			break
		}
	}
	return fmt.Sprintf("%s %d %s", copyPrefix, i, entryName), nil
}

func QueryForTableItemUpdate(db *sql.DB, tableName string, entryId int64,
	fieldNames []string, fieldVals []interface{}) error {
	if len(fieldNames)!=len(fieldVals) {
		return fmt.Errorf("field names count do not match values count")
	}
	setStrings := make([]string, len(fieldNames))
	for i:=0; i<len(fieldNames); i++ {
		setStrings[i] = fmt.Sprintf("%s=$%d", fieldNames, i+1)
	}
	query := fmt.Sprintf("update %s set %s where id=$%d",
		tableName, strings.Join(setStrings, ","), len(fieldNames))
	fieldVals = append(fieldVals, entryId)
	_, err := db.Exec(query, fieldVals...)
	return err
}

func QueryForTableItemInsert(db *sql.DB, tableName string,
	fieldNames []string, fieldVals []interface{}) (int64, error) {
	if len(fieldNames)!=len(fieldVals) {
		return 0, fmt.Errorf("field names count do not match values count")
	}
	setStrings := make([]string, len(fieldNames))
	for i:=0; i<len(fieldNames); i++ {
		setStrings[i] = fmt.Sprintf("$%d", i+1)
	}
	query := fmt.Sprintf("insert into %s(%s) values (%s) returning id",
		tableName, strings.Join(fieldNames, ","), strings.Join(setStrings, ","))
	var returningId int64
	err := db.QueryRow(query, fieldVals...).Scan(&returningId)
	return returningId, err
}
