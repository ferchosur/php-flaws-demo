# Mercado Norte: minimal, hardened image for the demo's static site.
#
# - No PHP, no secrets, no administration tools.
# - Runs as user 101 (non-root). After the build the command interpreter, apk and
#   the network clients are removed, so an attacker has no shell or wget/curl.
# - The filesystem must be mounted read-only; only /tmp is writable.
#
# To reproduce locally:
#   docker build -f app/Dockerfile -t php-flaws-demo:local .
#   docker run --rm -p 8080:8080 --read-only --tmpfs /tmp --user 101:101 \
#     --cap-drop ALL --security-opt no-new-privileges php-flaws-demo:local
#
# Pin the base image by digest before a real deployment:
#   docker buildx imagetools inspect nginxinc/nginx-unprivileged:1.27-alpine

FROM nginxinc/nginx-unprivileged:1.27-alpine

COPY app/nginx.conf /etc/nginx/nginx.conf
COPY web/ /usr/share/nginx/html/

USER root
RUN rm -f /etc/nginx/conf.d/*.conf \
 && find /usr/share/nginx/html -type d -exec chmod 0755 {} + \
 && find /usr/share/nginx/html -type f -exec chmod 0644 {} + \
 && rm -f /bin/sh /bin/busybox /sbin/apk /usr/bin/wget /usr/bin/curl \
 && rm -rf /etc/apk /lib/apk /var/cache/apk

# With no shell, the base image's entrypoint does not exist: start nginx directly.
ENTRYPOINT ["/usr/sbin/nginx"]
CMD ["-g", "daemon off;"]

USER 101
EXPOSE 8080
