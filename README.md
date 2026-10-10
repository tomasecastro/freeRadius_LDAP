# freeRadius_LDAP — despliegue base FreeRADIUS + MariaDB (hook LDAP reservado)

Despliegue base de FreeRADIUS 3.2.10 con MariaDB 11.8, derivado de
`src/daloradius/docker-compose.yml` SIN el servicio `radius-web`.
Incluye un hook LDAP documentado (`configure_ldap()` en
`init-freeradius-ldap.sh` + variables `LDAP_*` comentadas en el compose)
que se ajusta despues del despliegue base.

## Servicios

| Servicio | Imagen | Puertos | Descripcion |
|---|---|---|---|
| `radius-mysql` | `mariadb:11.8` | interno 3306 | Base de datos RADIUS con healthcheck |
| `radius` | build `Dockerfile` (`freeradius/freeradius-server:3.2.10`) | `1812:1812/udp`, `1813:1813/udp` | Servidor FreeRADIUS + healthcheck `radclient status` |

## Despliegue

```powershell
cd src/freeRadius_LDAP
./scripts/init-env.ps1        # genera .env con MYSQL_PASSWORD y DEFAULT_CLIENT_SECRET
docker compose config         # valida el compose con el .env generado
docker compose build radius   # radius es imagen local (build: Dockerfile), no viene de un registry
docker compose pull
docker compose up -d
docker compose ps
```

```bash
cd src/freeRadius_LDAP
./scripts/init-env.sh         # genera .env con MYSQL_PASSWORD y DEFAULT_CLIENT_SECRET
docker compose config         # valida el compose con el .env generado
docker compose build radius   # radius es imagen local (build: Dockerfile), no viene de un registry
docker compose pull
docker compose up -d
docker compose ps
```

## Verificacion

```powershell
docker compose ps
docker compose logs radius --tail 50
docker exec radius bash -c "echo 'FreeRADIUS-Statistics-Type = 1' | radclient -q -r 1 -t 3 127.0.0.1:18121 status adminsecret && echo STATUS_OK"
```

```bash
docker compose ps
docker compose logs radius --tail 50
echo "User-Name = test, User-Password = test" | radclient -q -r 1 -t 3 127.0.0.1:1812 auth "$DEFAULT_CLIENT_SECRET"
radtest test test 127.0.0.1 0 "$DEFAULT_CLIENT_SECRET"
```

## Nota LDAP

El ajuste LDAP se hace DESPUES del despliegue base: las variables
`LDAP_HOST`, `LDAP_PORT`, `LDAP_BASE_DN` y `LDAP_BIND_DN` estan comentadas
en `docker-compose.yml` y `.env.example`, y la funcion `configure_ldap()`
en `init-freeradius-ldap.sh` solo registra
`LDAP hook reservado, se ajusta tras despliegue base` sin tocar configuracion.

## Referencias

- Docker Hub tags: https://hub.docker.com/r/freeradius/freeradius-server/tags
- GitHub freeradius-server: https://github.com/FreeRADIUS/freeradius-server
- Base: `src/daloradius/docker-compose.yml` (proyecto lirantal/daloradius)
