ARG PHP_APACHE_IMAGE=php:8.3.26-apache-bookworm@sha256:33025d411fb4ed9b96947af349dd382afee37024e5d940f9fa17e1fa41753ff3
FROM ${PHP_APACHE_IMAGE}

ENV APACHE_RUN_DIR=/var/run/apache2 \
    APACHE_RUN_USER=www-data \
    APACHE_RUN_GROUP=www-data \
    APACHE_PID_FILE=/var/run/apache2/apache2.pid \
    APACHE_LOCK_DIR=/var/lock/apache2 \
    APACHE_LOG_DIR=/var/log/apache2

COPY labs/php-test-site/target/apache-ports.conf /etc/apache2/ports.conf
COPY labs/php-test-site/target/apache-lab.conf /etc/apache2/sites-enabled/000-default.conf
COPY labs/php-test-site/target/scanner-lab.ini /usr/local/etc/php/conf.d/zz-scanner-lab.ini
COPY labs/php-test-site/target/www/index.php /var/www/html/index.php

RUN install -d -o www-data -g www-data \
      /var/run/apache2 /var/lock/apache2 /var/log/apache2 /var/lib/php/sessions \
 && chown -R www-data:www-data /var/www/html \
 && chmod -R a=rX /var/www/html

USER 33:33
EXPOSE 8080
CMD ["apache2-foreground"]
