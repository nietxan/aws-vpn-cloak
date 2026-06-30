package main

import (
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"net/url"
	"os"
)

// Minimal HTTP listener that catches the SAML assertion the IdP POSTs back to
// the loopback callback (default :35001) and writes it to a file the connect
// flow reads. ADDR lets the container bind 0.0.0.0 so a host-browser POST,
// forwarded via the published port, reaches the listener.
func main() {
	addr := os.Getenv("ADDR")
	if addr == "" {
		addr = "127.0.0.1:35001"
	}
	http.HandleFunc("/", SAMLServer)
	log.Printf("Starting SAML callback server at %s", addr)
	log.Fatal(http.ListenAndServe(addr, nil))
}

func SAMLServer(w http.ResponseWriter, r *http.Request) {
	out := os.Getenv("SAML_FILE")
	if out == "" {
		out = "saml-response.txt"
	}
	switch r.Method {
	case "POST":
		if err := r.ParseForm(); err != nil {
			fmt.Fprintf(w, "ParseForm() err: %v", err)
			return
		}
		SAMLResponse := r.FormValue("SAMLResponse")
		if len(SAMLResponse) == 0 {
			log.Printf("SAMLResponse field is empty or does not exist")
			return
		}
		ioutil.WriteFile(out, []byte(url.QueryEscape(SAMLResponse)), 0600)
		fmt.Fprintf(w, "Got SAMLResponse, it is now safe to close this window\n")
		log.Printf("Saved SAMLResponse to %s", out)
		return
	default:
		fmt.Fprintf(w, "Error: POST expected, got %s", r.Method)
	}
}
