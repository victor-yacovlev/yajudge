package main

import (
	"crypto/sha512"
	"fmt"
	log "github.com/sirupsen/logrus"
	"io/ioutil"
	"net/http"
	"os"
	"path"
	"strconv"
	"strings"
	"time"
)

var contentTypes = map[string]string{
	".html": "text/html",
	".js":   "application/javascript",
	".json": "application/json",
	".png":  "image/png",
	".css":  "text/css",
	".ttf":  "font/ttf",
	".otf":  "font/otf",
	".wasm": "application/wasm",
}

type fileCacheEntry struct {
	ContentType  string
	LastModified string
	ETag         string

	Data []byte
}

type StaticHandler struct {
	config *SiteConfig
	files  map[string]fileCacheEntry
}

func NewStaticHandler(config *SiteConfig) (*StaticHandler, error) {
	result := &StaticHandler{
		files:  map[string]fileCacheEntry{},
		config: config,
	}
	if config.WebAppStaticRoot == "" {
		log.Panicf("web root not set in configuration")
	}
	if err := result.loadDirectoryContent(config.WebAppStaticRoot, ""); err != nil {
		return nil, err
	}
	return result, nil
}

func (handler *StaticHandler) loadDirectoryContent(dirPath, prefix string) error {
	entries, err := os.ReadDir(dirPath)
	if err != nil {
		return fmt.Errorf("cant read directory %s: %v", dirPath, err)
	}
	for _, entry := range entries {
		entryPath := dirPath + "/" + entry.Name()
		entryRelativePath := prefix + "/" + entry.Name()
		if entry.IsDir() {
			handler.loadDirectoryContent(entryPath, entryRelativePath)
		} else {
			content, err := ioutil.ReadFile(entryPath)
			if err != nil {
				return fmt.Errorf("cant read file %s: %v", entryPath, err)
			}
			fileInfo, err := os.Stat(entryPath)
			if err != nil {
				return fmt.Errorf("cant stat file %s: %v", entryPath, err)
			}
			lastModified := fileInfo.ModTime()
			lastModifiedHeader := lastModified.UTC().Format(time.RFC1123)
			hasher := sha512.New()
			hasher.Write(content)
			etag := fmt.Sprintf("\"%x\"", hasher.Sum(nil))
			handler.files[entryRelativePath] = fileCacheEntry{
				Data:         content,
				ContentType:  guessContentType(entry.Name()),
				LastModified: lastModifiedHeader,
				ETag:         etag,
			}
		}
	}
	return nil
}

func (handler *StaticHandler) Handle(w http.ResponseWriter, req *http.Request) {
	reqPath := req.URL.Path
	log.Printf("%s requested %s", req.RemoteAddr, reqPath)
	if reqPath == "/" {
		reqPath = "/index.html"
	}
	entry, exists := handler.files[reqPath]
	if !exists && strings.HasPrefix(reqPath, "/favicon.") {
		http.Error(w, "", 404)
	} else if !exists {
		// might be SPA-based nagivation, so return index.html
		entry = handler.files["/index.html"]
		reqPath = "/index.html"
	}
	if req.Proto == "HTTP/2.0" && reqPath == "/index.html" {
		handler.pushHttp2Resources(w)
	}
	w.Header().Set("Content-Type", entry.ContentType)
	w.Header().Set("Content-Length", strconv.Itoa(len(entry.Data)))
	w.Header().Set("Last-Modified", entry.LastModified)
	w.Header().Set("ETag", entry.ETag)
	w.Header().Set("Cache-Control", "public, max-age=31536000")
	w.WriteHeader(200)
	w.Write(entry.Data)
}

func (handler *StaticHandler) pushHttp2Resources(w http.ResponseWriter) {
	pusher, _ := w.(http.Pusher)
	for name, _ := range handler.files {
		if name != "/index.html" {
			err := pusher.Push(name, nil)
			if err != nil {
				log.Warningf("failed to push %s via HTTP/2.0: %v", name, err)
			}
		}
	}
}

func guessContentType(fileBaseName string) string {
	suffix := path.Ext(fileBaseName)
	base := fileBaseName[0 : len(fileBaseName)-len(suffix)]
	value, exists := contentTypes[suffix]
	if !exists {
		if suffix != "" && base != "" {
			log.Warningf("Unknown mime type for suffix %s", suffix)
		}
		return "application/binary"
	}
	return value
}
