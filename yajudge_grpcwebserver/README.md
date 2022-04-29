# gRPC[-Web] Proxy and Static Web Server Bundle

HTTP/2 server for Single-Page Applications with gRPC-exposed APIs.

Correctly handles regular gRPC (`application/grpc`), gRPC-Web
(`application/grpc-web`) protocols and also in-memory cached static 
web application content serving with HTTP/2 Push capabilities.

**Note** current implementation targets gRPC proxy first and
has not so good static files handling implementation, so
it's highly recommended to use reverse-proxy below this service.

## Nginx reverse proxy configuration

Nginx configuration example for rever-proxying:

```nginx configuration
server {
    server_name YOUR-SERVER-NAME;
    
    ## NOTE on http2 protocol usage - it is important!
    listen 443 ssl http2;
    
    ## path to your SSL certificates
    ssl_certificate ....;
    ssl_certificate_key ...;
    
    ## `location` subtree is required for `grpc_pass` nginx token,
    ## so match everything and just pass to yajudge-grpcwebserver
    ## that handles static content, gRPC requests and gRPC-Web
    location ~* /.+$ {
        # port must match yajudge_grpweserver configuration
        grpc_pass localhost:8080;        
        # required headers
        grpc_set_header Host            $host;
        grpc_set_header X-Forwarded-For $remote_addr;
    }
}

## additional port 80 declaration to force http -> https redirection
server {
    server_name YOUR-SERVER-NAME;
    return 301 https://YOUR-SERVER-NAME$request_uri;
}

```
