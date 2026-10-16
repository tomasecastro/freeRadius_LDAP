#!/bin/bash
# Registra un NAS (cliente RADIUS) en la tabla `nas` de la base de datos FreeRADIUS.
#
# POR QUE el NAS vive en SQL y no en el directorio de identidad (LDAP):
# el directorio de identidad (Outpost LDAP) solo modela usuarios y grupos. Un NAS
# es un dispositivo de red con IP y secreto compartido, no una identidad de
# persona; mantenerlo en la tabla `nas` evita que un equipo de red quede como
# "usuario" del directorio y mantiene separado " quien se autentica" de
# " que equipos pueden hablar con el servidor RADIUS".
#
# Uso: ./scripts/add-nas.sh <IP> <SHORTNAME> <SECRET> [DESCRIPTION]
#   IP          direccion IP o CIDR del NAS (ej. 192.168.1.1 o 10.0.0.0/24)
#   SHORTNAME   nombre corto del NAS (columna `shortname`)
#   SECRET      secreto compartido RADIUS (coincide con el configurado en el NAS)
#   DESCRIPTION descripcion opcional
#
# Credenciales MySQL: se toman del entorno (MYSQL_HOST/PORT/DATABASE/USER/PASSWORD)
# usando un fichero de credenciales temporal con permisos 600 (patron de
# init-freeradius-ldap.sh). El INSERT es idempotente: si ya existe un NAS con esa
# IP no se duplica.
set -euo pipefail

MYSQL_HOST=${MYSQL_HOST:-radius-mysql}
MYSQL_PORT=${MYSQL_PORT:-3306}
MYSQL_DATABASE=${MYSQL_DATABASE:-radius}
MYSQL_USER=${MYSQL_USER:-radius}
MYSQL_PASSWORD=${MYSQL_PASSWORD:-}

function usage {
	echo "Uso: $0 <IP> <SHORTNAME> <SECRET> [DESCRIPTION]" >&2
	exit 1
}

if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
	usage
fi

NAS_IP="$1"
NAS_SHORTNAME="$2"
NAS_SECRET="$3"
NAS_DESCRIPTION="${4:-}"

if [ -z "$MYSQL_PASSWORD" ]; then
	echo "MYSQL_PASSWORD no esta definido. Exporta las credenciales MySQL o defines MYSQL_PASSWORD." >&2
	exit 1
fi

# Escapado para valores SQL de comilla simple.
function sql_escape {
	printf '%s' "$1" | sed -e "s/'/''/g"
}

NAS_IP_SQL=$(sql_escape "$NAS_IP")
NAS_SHORTNAME_SQL=$(sql_escape "$NAS_SHORTNAME")
NAS_SECRET_SQL=$(sql_escape "$NAS_SECRET")
NAS_DESCRIPTION_SQL=$(sql_escape "$NAS_DESCRIPTION")

MYSQL_DEFAULTS_FILE=$(mktemp)
chmod 600 "$MYSQL_DEFAULTS_FILE"
function cleanup {
	rm -f "$MYSQL_DEFAULTS_FILE"
}
trap cleanup EXIT

{
	printf '[client]\n'
	printf 'host=%s\n' "$MYSQL_HOST"
	printf 'port=%s\n' "$MYSQL_PORT"
	printf 'user=%s\n' "$MYSQL_USER"
	printf 'password=%s\n' "$MYSQL_PASSWORD"
} > "$MYSQL_DEFAULTS_FILE"

function mysql_radius {
	mysql --defaults-extra-file="$MYSQL_DEFAULTS_FILE" "$MYSQL_DATABASE" "$@"
}

# read_clients=yes esta activo en mods-available/sql, asi que FreeRADIUS lee la
# tabla nas al arrancar. El INSERT es idempotente (WHERE NOT EXISTS) para poder
# reejecutar el script sin duplicar el NAS.
mysql_radius <<EOSQL
INSERT INTO nas (nasname, shortname, type, ports, secret, server, community, description)
SELECT '$NAS_IP_SQL', '$NAS_SHORTNAME_SQL', 'other', 0, '$NAS_SECRET_SQL', NULL, '', '$NAS_DESCRIPTION_SQL'
WHERE NOT EXISTS (SELECT 1 FROM nas WHERE nasname = '$NAS_IP_SQL');
EOSQL

echo "NAS '$NAS_SHORTNAME' ($NAS_IP) registrado en la tabla nas."
echo "docker compose restart radius (clients load at startup)"