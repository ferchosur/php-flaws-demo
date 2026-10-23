# Mercado Norte: imagen mínima y endurecida para el sitio estático de la demo.
#
# - Sin PHP, sin secretos, sin herramientas de administración.
# - Corre como usuario 101 (sin root). Tras la compilación se eliminan el intérprete de
#   comandos, apk y los clientes de red, de modo que un atacante no tenga shell ni wget/curl.
# - El sistema de archivos debe montarse de solo lectura; solo /tmp es escribible.
#
# Para reproducir en local:
#   docker build -f app/Dockerfile -t php-flaws-demo:local .
#   docker run --rm -p 8080:8080 --read-only --tmpfs /tmp --user 101:101 \
#     --cap-drop ALL --security-opt no-new-privileges php-flaws-demo:local
#
# Fijar la imagen base por digest antes de un despliegue real:
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

# Sin shell, el entrypoint de la imagen base no existe: se arranca nginx directamente.
ENTRYPOINT ["/usr/sbin/nginx"]
CMD ["-g", "daemon off;"]

USER 101
EXPOSE 8080
