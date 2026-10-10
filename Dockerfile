# FreeRADIUS Docker image para freeRadius_LDAP.
#
# Build image:
# 1. docker compose build radius
#
# Run the container:
# 1. docker run -p 1812:1812/udp -p 1813:1813/udp -d freeradius-ldap:3.2.10-local

FROM freeradius/freeradius-server:3.2.10
LABEL maintainer="freeRadius_LDAP"
LABEL Description="FreeRADIUS 3.2.10 para freeRadius_LDAP." \
	License="GPLv2" \
	Usage="docker build -t freeradius-ldap:3.2.10-local -f Dockerfile && docker run -d -p 1812:1812/udp -p 1813:1813/udp freeradius-ldap:3.2.10-local" \
	Version="1.0"

ENV DEBIAN_FRONTEND=noninteractive

# default timezone
ENV TZ=Europe/Vienna

RUN apt-get update \
	&& apt-get install --yes --no-install-recommends \
		ipcalc \
		tzdata \
		net-tools \
		mariadb-client \
	&& rm -rf /var/lib/apt/lists/*

# Create directories
# /data should be mounted as volume to avoid recreation of database entries
RUN mkdir /app /data
WORKDIR /app

# Copy init script to image
COPY ./init-freeradius-ldap.sh /app

# Make init.sh script executable
RUN sed -i 's/\r$//' /app/init-freeradius-ldap.sh \
	&& chmod +x /app/init-freeradius-ldap.sh

# Expose FreeRADIUS Ports
EXPOSE 1812 1813

ENTRYPOINT ["/app/init-freeradius-ldap.sh"]
