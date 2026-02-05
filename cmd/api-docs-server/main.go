package main

import (
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
)

func main() {
	// Parse command-line flags
	port := flag.String("port", "8080", "Port to serve API documentation on")
	dir := flag.String("dir", "../../docs/api", "Directory containing API documentation")
	flag.Parse()

	// Get absolute path to docs directory
	absDir, err := filepath.Abs(*dir)
	if err != nil {
		log.Fatalf("Failed to get absolute path: %v", err)
	}

	// Verify directory exists
	if _, err := os.Stat(absDir); os.IsNotExist(err) {
		log.Fatalf("Documentation directory does not exist: %s", absDir)
	}

	// Create file server
	fs := http.FileServer(http.Dir(absDir))

	// Set up routes
	http.Handle("/", fs)

	// Start server
	addr := fmt.Sprintf(":%s", *port)
	log.Printf("🚀 MinIO Enterprise API Documentation Server")
	log.Printf("📚 Serving documentation from: %s", absDir)
	log.Printf("🌐 Server running at: http://localhost%s", addr)
	log.Printf("📖 Open in browser: http://localhost%s/index.html", addr)
	log.Printf("\nPress Ctrl+C to stop the server")

	if err := http.ListenAndServe(addr, nil); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}
