FROM nginx:alpine

# Copy OpenAPI spec and Swagger UI HTML
COPY openapi.yaml /usr/share/nginx/html/openapi.yaml
COPY index.html /usr/share/nginx/html/index.html

# Configure nginx
RUN echo 'server { \
    listen 8080; \
    server_name localhost; \
    location / { \
        root /usr/share/nginx/html; \
        index index.html; \
        try_files $uri $uri/ /index.html; \
    } \
    location ~ \.(yaml|yml)$ { \
        add_header Content-Type application/x-yaml; \
    } \
}' > /etc/nginx/conf.d/default.conf

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]
