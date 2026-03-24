FROM openresty/openresty:alpine

# Install lua-resty-openssl (required by lua-resty-http for mTLS support)
RUN apk add --no-cache luarocks5.1 && \
    luarocks-5.1 install lua-resty-openssl

# Install lua-resty-http directly into openresty's lua path (no luarocks needed)
COPY vendor/ /usr/local/openresty/lualib/

# Copy NGINX configuration
COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf

# Copy Lua modules
COPY lua/ /usr/local/openresty/nginx/lua/

# Copy Web UI static files
COPY html/ /usr/local/openresty/nginx/html/

# Create log directory
RUN mkdir -p /var/log/nginx

EXPOSE 80

CMD ["/usr/local/openresty/bin/openresty", "-g", "daemon off;"]

