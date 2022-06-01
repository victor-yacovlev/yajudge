package main

import (
	"crypto/sha512"
	"fmt"
	"github.com/gabriel-vasile/mimetype"
	log "github.com/sirupsen/logrus"
	"io/ioutil"
	"net/http"
	"os"
	"path"
	"strconv"
	"strings"
	"sync"
	"time"
)

var extraContentTypes = map[string]string{
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

	readDirLock sync.RWMutex
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
	periodicChecker := func() {
		for {
			time.Sleep(time.Duration(config.StaticReloadInterval) * time.Second)
			result.reloadDirectoryContent()
		}
	}
	go periodicChecker()
	return result, nil
}

func (handler *StaticHandler) reloadDirectoryContent() {
	handler.readDirLock.Lock()
	handler.files = map[string]fileCacheEntry{}
	err := handler.loadDirectoryContent(handler.config.WebAppStaticRoot, "")
	if err != nil {
		log.Error(err)
	}
	handler.readDirLock.Unlock()
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
			err = handler.loadDirectoryContent(entryPath, entryRelativePath)
			if err != nil {
				return fmt.Errorf("cant read file %s: %v", entryPath, err)
			}
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
				ContentType:  guessContentType(entryPath),
				LastModified: lastModifiedHeader,
				ETag:         etag,
			}
		}
	}
	return nil
}

func (handler *StaticHandler) Handle(w http.ResponseWriter, req *http.Request) {
	reqPath := req.URL.Path
	log.Debugf("%s requested %s", req.RemoteAddr, reqPath)
	if reqPath == "/" {
		reqPath = "/index.html"
	}
	handler.readDirLock.RLock()
	entry, exists := handler.files[reqPath]
	handler.readDirLock.RUnlock()
	if !exists && strings.HasPrefix(reqPath, "/favicon.") {
		http.Error(w, "", 404)
	} else if !exists {
		// might be SPA-based navigation, so return index.html
		handler.readDirLock.RLock()
		entry = handler.files["/index.html"]
		handler.readDirLock.RUnlock()
		reqPath = "/index.html"
	}
	if req.Proto == "HTTP/2.0" && reqPath == "/index.html" {
		handler.pushHttp2Resources(w)
	}
	w.Header().Set("Content-Type", entry.ContentType)
	w.Header().Set("Content-Length", strconv.Itoa(len(entry.Data)))
	w.Header().Set("Last-Modified", entry.LastModified)
	w.Header().Set("ETag", entry.ETag)
	maxAge := handler.config.WebAppStaticMaxAge
	w.Header().Set("Cache-Control", "public, max-age="+strconv.Itoa(maxAge))
	w.WriteHeader(200)
	w.Write(entry.Data)
}

func (handler *StaticHandler) pushHttp2Resources(w http.ResponseWriter) {
	pusher, _ := w.(http.Pusher)
	handler.readDirLock.RLock()
	for name, _ := range handler.files {
		if name != "/index.html" {
			err := pusher.Push(name, nil)
			if err != nil {
				log.Debugf("failed to push %s via HTTP/2.0: %v", name, err)
			}
		}
	}
	handler.readDirLock.RUnlock()
}

func guessContentType(filePath string) string {

	suffix := path.Ext(filePath)
	base := filePath[0 : len(filePath)-len(suffix)]
	value, exists := extraContentTypes[suffix]
	if !exists {
		standardType, err := mimetype.DetectFile(filePath)
		if err == nil {
			return standardType.String()
		} else if suffix != "" && base != "" {
			log.Warningf("Unknown mime type for suffix %s", suffix)
		} else {
			return "application/binary"
		}
	}
	return value
}
