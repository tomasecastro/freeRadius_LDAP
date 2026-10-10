#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_PATH="$PROJECT_ROOT/.env"
EXAMPLE_PATH="$PROJECT_ROOT/.env.example"
PLACEHOLDER="CHANGE_ME"
FORCE=0

log_info() { printf 'init-env: %s\n' "$1"; }
log_warn() { printf 'init-env: AVISO: %s\n' "$1" >&2; }
log_err()  { printf 'init-env: ERROR: %s\n' "$1" >&2; }

while [ $# -gt 0 ]; do
    case "$1" in
        --force|-f) FORCE=1; shift ;;
        -h|--help)
            log_info "Uso: $0 [--force]"
            log_info "Genera .env con secretos aleatorios para freeRadius_LDAP (Docker Compose)."
            log_info "  --force  regenera los secretos aunque ya tengan valores reales"
            exit 0
            ;;
        *)
            log_err "Argumento desconocido: $1"
            log_err "Uso: $0 [--force]"
            exit 1
            ;;
    esac
done

if ! command -v openssl >/dev/null 2>&1; then
    log_err "openssl no esta instalado o no esta en el PATH."
    log_err "Se requiere openssl para generar los secretos (openssl rand -base64 36)."
    log_err "Instalalo con: sudo apt install openssl   (Debian/Ubuntu)"
    log_err "Instalalo con: sudo dnf install openssl   (Fedora/RHEL)"
    exit 1
fi

if [ ! -f "$ENV_PATH" ]; then
    if [ ! -f "$EXAMPLE_PATH" ]; then
        log_err "No se encontro $EXAMPLE_PATH. No se puede crear el .env."
        exit 1
    fi
    cp "$EXAMPLE_PATH" "$ENV_PATH"
    log_info "No existia .env; se copio .env.example -> .env"
else
    log_info "El archivo .env ya existe: $ENV_PATH"
fi

for dir in data; do
    if [ ! -d "$PROJECT_ROOT/$dir" ]; then
        mkdir -p "$PROJECT_ROOT/$dir"
        log_info "Carpeta creada: ./$dir"
    fi
done

get_current_value() {
    local name="$1"
    sed -n "s/^[[:space:]]*${name}[[:space:]]*=//p" "$ENV_PATH" | head -n 1 | tr -d '\r'
}

set_var() {
    local name="$1"
    local value="$2"
    local tmp
    tmp="$(mktemp)"
    if grep -qE "^[[:space:]]*${name}[[:space:]]*=" "$ENV_PATH"; then
        awk -v name="$name" -v value="$value" '
            BEGIN { done = 0 }
            $0 ~ "^[[:space:]]*" name "[[:space:]]*=" {
                if (done == 0) { print name "=" value; done = 1 }
                next
            }
            { print }
        ' "$ENV_PATH" > "$tmp"
    else
        cat "$ENV_PATH" > "$tmp"
        printf '%s=%s\n' "$name" "$value" >> "$tmp"
    fi
    mv "$tmp" "$ENV_PATH"
}

GENERATED=""
PRESERVED=""

handle_secret() {
    local name="$1"
    local bytes="$2"
    local current secret

    current="$(get_current_value "$name")"
    current="${current//$'\r'/}"

    if [ "$FORCE" -eq 0 ] && [ -n "$current" ] && [[ "$current" != "$PLACEHOLDER"* ]]; then
        log_warn "$name ya tiene un valor real; se preserva (usa --force para regenerarlo)."
        PRESERVED="$PRESERVED $name"
        return 0
    fi

    secret="$(openssl rand -base64 "$bytes" | tr -d '\n')"
    set_var "$name" "$secret"
    log_info "$name generado (${#secret} caracteres)."
    GENERATED="$GENERATED $name"
}

handle_secret 'MYSQL_PASSWORD' 36
handle_secret 'MYSQL_ROOT_PASSWORD' 36
handle_secret 'DEFAULT_CLIENT_SECRET' 36

chmod 600 "$ENV_PATH"
log_info "Permisos de .env ajustados a 600 (solo lectura/escritura del propietario)."

printf '\n'
log_info "Variables generadas:${GENERATED:- ninguna}"
log_info "Variables preservadas:${PRESERVED:- ninguna}"
log_info "Los valores de los secretos NO se imprimen por seguridad."
log_info "Siguiente paso: docker compose pull && docker compose up -d"
