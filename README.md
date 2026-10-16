# freeRadius_LDAP — FreeRADIUS + MariaDB con autenticacion LDAP

Despliegue de FreeRADIUS 3.2.10 con MariaDB 11.8, derivado de
`src/daloradius/docker-compose.yml` SIN el servicio `radius-web`.
La autenticacion se delega a un directorio de identidad mediante las variables
`LDAP_*` (`configure_ldap()` en `init-freeradius-ldap.sh`): si `LDAP_HOST` esta
vacia el servidor funciona en modo base solo SQL; al rellenarla se activa el
modulo `ldap`, la resolucion de grupos y la asignacion dinamica de VLAN.
Algunos de los scripts utilizados se basan en los del proyecto daloRADIUS. (lirantal/daloradius) Licencia GPLv2.

## Servicios

| Servicio | Imagen | Puertos | Descripcion |
|---|---|---|---|
| `radius-mysql` | `mariadb:11.8` | interno 3306 | Base de datos RADIUS con healthcheck |
| `radius` | build `Dockerfile` (`freeradius/freeradius-server:3.2.10`) | `1812:1812/udp`, `1813:1813/udp` | Servidor FreeRADIUS + healthcheck `radclient status` |

## Despliegue

```powershell
cd src/freeRadius_LDAP  # raiz de este repositorio
./scripts/init-env.ps1        # genera .env con MYSQL_PASSWORD, MYSQL_ROOT_PASSWORD y DEFAULT_CLIENT_SECRET
docker compose config         # valida el compose con el .env generado
docker compose build radius   # radius es imagen local (build: Dockerfile), no viene de un registry
docker compose pull
docker compose up -d
docker compose ps
```

```bash
cd src/freeRadius_LDAP   # raiz de este repositorio
bash  ./scripts/init-env.sh         # genera .env con MYSQL_PASSWORD, MYSQL_ROOT_PASSWORD y DEFAULT_CLIENT_SECRET
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

El directorio de identidad (Outpost LDAP) se activa mediante las variables
`LDAP_*` de `.env`, ya presentes en `docker-compose.yml`:

| Variable | Obligatoria | Por defecto | Para que sirve |
|---|---|---|---|
| `LDAP_HOST` | no (vacia = modo base) | — | Host del Outpost LDAP. **Si esta vacia no se toca LDAP** y el servidor sigue en modo solo SQL. |
| `LDAP_PORT` | no | `389` | Puerto del Outpost LDAP. |
| `LDAP_BASE_DN` | si (con `LDAP_HOST`) | — | Base DN / parent DN del Provider LDAP. |
| `LDAP_BIND_DN` | si (con `LDAP_HOST`) | — | DN del usuario de servicio de solo lectura. |
| `LDAP_BIND_PW` | si (con `LDAP_HOST`) | — | App password del usuario de servicio. |
| `LDAP_USER_FILTER` | no | `(cn=%{User-Name})` | Filtro de busqueda de usuarios. |
| `LDAP_GROUP_BASE_DN` | no | `ou=groups,<LDAP_BASE_DN>` | Rama del directorio donde rlm_ldap busca los grupos del usuario. |
| `LDAP_GROUP_FILTER` | no | `(objectClass=group)` | Filtro de busqueda de grupos. |
| `DEFAULT_VLAN` | no | `20` | VLAN de reserva si el grupo no define `FreeRADIUSVLAN`. |

`configure_ldap()` en `init-freeradius-ldap.sh` valida esas variables: si
`LDAP_HOST` esta vacia registra `LDAP disabled (LDAP_HOST empty), base mode` y
sigue en modo base; si `LDAP_HOST` esta definida y falta `LDAP_BASE_DN`,
`LDAP_BIND_DN` o `LDAP_BIND_PW`, escribe el nombre de la variable que falta por
stderr y termina con codigo 1 (fail-fast) en lugar de arrancar con un bind
anonimo o una busqueda en la raiz equivocada.

Con LDAP activo el script habilita `mods-available/ldap` (server, port, identity,
password, base_dn y el filtro de usuario), activa la resolucion de grupos
(`base_dn`, `filter`, `name_attribute = cn`, `membership_attribute = memberOf`
dentro del bloque `group {}`), enlaza `mods-enabled/ldap`, anade `ldap` a
`authorize`, habilita `Auth-Type LDAP` en `authenticate` e inserta el bloque de
VLAN en `post-auth`. Todas las pasos son idempotentes: reiniciar el contenedor
no duplica nada.

`LDAP_GROUP_BASE_DN` y `LDAP_GROUP_FILTER` controlan donde y como se buscan los
grupos; si llegan vacias el script aplica los defaults (`ou=groups,<LDAP_BASE_DN>`
y `(objectClass=group)`) y lo avisa por log una vez, sin fallar. Ajustalas solo
si tu directorio publica los grupos en otra rama (por ejemplo `ou=Grupos,...`)
o los tipa con otro objectClass (`posixGroup`, `groupOfUniqueNames`): el filtro
tiene que corresponder al objectClass que sirva ese directorio. El valor por
defecto es el que sirve el Outpost LDAP de este despliegue, que publica los
grupos bajo `ou=groups` con el atributo `member` (DNs completos). Con un filtro
equivocado la resolucion de grupos queda inactiva y la VLAN cae siempre a
`DEFAULT_VLAN`.

La VLAN se resuelve en `post-auth` leyendo el atributo custom `FreeRADIUSVLAN`
del grupo LDAP del usuario; si el grupo no lo define se aplica `DEFAULT_VLAN`.

Nota de operacion: `server`, `port`, `identity`, `password`, `base_dn`, el
filtro de usuario y el bloque `group {}` (`base_dn`, `filter`,
`name_attribute`, `membership_attribute`) se reescriben en cada arranque (son
idempotentes). El bloque `VLAN CONFIG` de `post-auth` lleva un marcador
idempotente, asi que si cambias `LDAP_BASE_DN`, `LDAP_GROUP_BASE_DN` o
`DEFAULT_VLAN` tendras que reconstruir la imagen (`docker compose build radius`)
para que el bloque de VLAN se regenere con los nuevos valores.

## Integracion LDAP con el proveedor de identidad

FreeRADIUS no es aqui un almacen de identidades: es un **puente**. Este
despliegue no guarda contrasenas ni usuarios; cada peticion EAP se resuelve
contra un directorio de identidad externo que expone LDAP, y FreeRADIUS solo
aporta lo que LDAP no da: la validacion del secreto compartido contra la lista
de clientes, la sesion 802.1X y la respuesta RADIUS con la VLAN.

La division de responsabilidades es la siguiente:

| Dato | Donde vive | Quien lo resuelve |
|---|---|---|
| Credenciales de los usuarios | Directorio LDAP (`ou=users,<base DN>`) | `rlm_ldap` en `authorize`, con bind como `svc-freeradius` |
| Grupos y atributo `FreeRADIUSVLAN` | Directorio LDAP (`ou=groups,<base DN>`) | bloque `group {}` de `rlm_ldap` + lookup `?FreeRADIUSVLAN?sub?(member=...)` en `post-auth` |
| VLAN asignada al usuario | Atributo custom `FreeRADIUSVLAN` del grupo, con reserva `DEFAULT_VLAN` | Bloque `VLAN CONFIG` de `Post-Auth-Type REJECT`, que emite `Tunnel-Private-Group-Id` |
| Clientes RADIUS (NAS) y su secreto compartido | Tabla `nas` de MariaDB | `mods-available/sql` con `read_clients = yes` |

Por que los NAS **no** van al directorio: FreeRADIUS valida el secreto
compartido que llega en cada peticion contra su propia lista de clientes
cargada de SQL; si el AP no esta en la tabla `nas` su peticion se descarta
antes de tocar LDAP. Y `rlm_ldap` solo sabe resolver usuarios y grupos, no
registrar dispositivos de red con IP y secreto. Mantenerlo separado evita que
un switch aparezca como una "persona" del directorio y mantiene claro quien
se autentica frente a que equipos pueden hablar con el servidor.

Flujo de una autenticacion completa:

```
   Cliente 802.1X (supplicant)
            |
            |  EAP-Identity / EAP-Response
            v
   +-----------------------------------------------+
   |  NAS: access point / switch                   |   secreto compartido
   |  172.16.1.10  --(UDP 1812)-->                |   contra la tabla `nas`
   +-----------------------------------------------+
            |
            v
   +---------------------------------------------------+
   |            FreeRADIUS  172.16.1.25                 |
   |                                                   |
   |  1. authorize                                     |
   |       sql  -> busca el NAS en la tabla `nas`      |
   |                (si no esta: Access-Reject)         |
   |       ldap -> bind como svc-freeradius             |
   |                (host:389)                          |
   |                busca el usuario con                |
   |                LDAP_USER_FILTER (cn=%{User-Name})   |
   |                resuelve grupos con group {}         |
   |                    name_attribute    = cn          |
   |                    membership_attribute = memberOf  |
   |                                                   |
   |  2. authenticate                                  |
   |       Auth-Type LDAP -> compara la contrasena     |
   |                       contra el directorio        |
   |                                                   |
   |  3. post-auth  (bloque VLAN CONFIG)               |
   |       busca FreeRADIUSVLAN en el grupo del        |
   |       usuario sobre LDAP_GROUP_BASE_DN            |
   |       -> Tunnel-Private-Group-Id = <VLAN>         |
   |       -> si no aparece, Tunnel-Private-Group-Id   |
   |          = DEFAULT_VLAN                           |
   +---------------------------------------------------+
            |
            |  Access-Accept + Tunnel-Private-Group-Id
            v
   +-----------------------------------------------+
   |  NAS aplica la VLAN y abre la sesion            |
   +-----------------------------------------------+
            |
            v
   Access-Request / AccountingStart
            --(UDP 1813)-->
   FreeRADIUS (Accounting)
```

### Estado actual del lado del proveedor de identidad

Verificado contra el servidor `172.16.1.25`:

| Comprobacion | Resultado | Significado |
|---|---|---|
| Puerto `9000/tcp` (panel y API del proveedor de identidad) | Alcanzable | El panel responde desde esta maquina. |
| `GET http://172.16.1.25:9000/api/v3/root/config/` | HTTP 200 | La API v3 esta viva y responde sin token. |
| `GET /api/v3/core/providers/` sin token | HTTP 404 | Comportamiento normal: el proveedor oculta los recursos a quien no esta autenticado. |
| Puerto `389/tcp` (LDAP del Outpost) | **Cerrado** | El Outpost LDAP todavia **no existe** en el panel. |

Consecuencia practica: el panel y la API ya estan disponibles, pero todavia no
se puede rellenar `LDAP_HOST`, ni probar con `ldapsearch`, ni autenticar por
LDAP, porque el Outpost LDAP es el que publica el puerto 389. Crear el Outpost
es el paso 3 de la seccion siguiente y es lo que abre el 389.

## Pasos en el panel del proveedor de identidad

Los siete pasos se hacen en el panel web del proveedor de identidad, en el
servidor `172.16.1.25:9000`. El orden importa: el Outpost necesita el Provider,
y el Provider necesita un usuario de servicio al que enlazar.

### 1. Crear la Aplicacion

Ruta de menu: **Applications -> Applications -> Create**.

- Nombre: `freeRadius_LDAP` (debe ser unico dentro del panel).
- Provider de identidad: el proveedor integrado que ya tiene el panel.
- Protocolo: **LDAP**.

Se espera ver: la aplicacion listada en **Applications** con el icono de LDAP y
con una fila en su pestana de configuracion. Se crea primero porque el Outpost
LDAP se asocia a una aplicacion; sin ella no hay contra que colgar el
proveedor LDAP ni el outpost.

### 2. Crear el LDAP Provider

Ruta de menu: **Directory -> Providers -> Create**, tipo **LDAP**.

- Nombre: `freeRadius_LDAP-ldap`.
- Application: la del paso 1.
- **Base DN / parent DN**: el DN raiz que publica el directorio. Apuntalo tal
  cual, es el valor de `LDAP_BASE_DN`.
- **Bind flow**: elige el modo de autenticacion del outpost. Usa el flujo
  **Token / App password**: el outpost se autenticara con las credenciales
  del usuario de servicio del paso 4, no con un password de usuario final.
- Protocol binding / TLS: activa **StartTLS** o LDAPS si el servicio lo ofrece;
  si la integracion es local en la misma red se puede empezar sin TLS y
  endurecer despues.

Se espera ver: el provider creado y, en su detalle, el **Base DN (parent DN)**
mostrado como `dc=...,dc=...`. Este dato no se inventa: se copia del panel,
porque el bloque `group {}` de `rlm_ldap` y el lookup de la VLAN cuelgan
sematicamente de ese DN y un valor equivocado deja la resolucion de grupos y
la VLAN caidas en `DEFAULT_VLAN`.

### 3. Crear el Outpost LDAP

Ruta de menu: **Applications -> Outposts -> Create**, tipo **LDAP**.

- Nombre: `freeRadius_LDAP-outpost`.
- Application: la del paso 1 (quien decide el contenido).
- Provider: el del paso 2 (de donde sale el contenido).
- **Integracion**: **Docker / Kubernetes (local)** en este despliegue.
- Configuracion **LDAP**: escucha en el puerto **389**, identificado por el nombre
  del contenedor. Con integracion local el outpost se ejecuta junto al panel en
  el mismo host, asi que `LDAP_HOST=172.16.1.25` y `LDAP_PORT=389`.

Se espera ver: el outpost en estado **Running / Healthy** en **Outposts**, con
el puerto 389 en su informacion de servicio. Este paso es el que abre el
puerto 389: hasta que exista, `Test-NetConnection 172.16.1.25 -Port 389`
devuelve `TcpTestSucceeded: False` y `ldapsearch` no conecta. Es el paso que
falta hoy en este despliegue.

### 4. Crear el usuario de servicio y su rol

Ruta de menu: **Directory -> Users -> Create** y despues
**Directory -> Groups -> Create** + asignacion del usuario al grupo.

- Usuario: `svc-freeradius`, tipo **internal user**, estado inactivo o activo
  segun la politica del panel.
- Rol (grupo con permisos): asigna a `svc-freeradius` el permiso
  **"Search full LDAP directory"** limitado al provider del paso 2.

Por que el permiso es indispensable: por defecto un usuario del directorio solo
puede buscar dentro de su propia ficha y de los grupos que el mismo pertenece.
El usuario de servicio no pertenece a ningun grupo de usuarios, asi que sin ese
permiso su bind funciona pero toda busqueda devuelve cero entradas: el usuario
no se encuentra, el grupo no se resuelve y la VLAN cae siempre a
`DEFAULT_VLAN`. Ese es el fallo mas dificil de diagnosticar porque el log
muestra la consulta LDAP vacia y no un error de credenciales.

Se espera ver: el usuario `svc-freeradius` creado, su rol mostrando el permiso
"Search full LDAP directory" con el provider como objeto, y el usuario
asignado a ese rol.

### 5. Generar el app password de `svc-freeradius`

Ruta de menu: **Directory -> Users -> svc-freeradius -> App passwords ->
Create**.

- Nombre: `freeradius-bind`.
- El panel muestra la contrasena **una sola vez**.

Se espera ver: la fila del app password con la fecha de expiracion y un boton
para copiar el valor. Este es el valor de `LDAP_BIND_PW`, y existe para poder
cambiar o revocar la credencial del bind sin tocar la del usuario. Si el panel
ofrece caducidad, conviene fijarla y rotar el valor en `.env` cuando expire.

### 6. Anadir el atributo custom `FreeRADIUSVLAN` a los grupos

Ruta de menu: **Directory -> Groups -> <grupo> -> Attributes -> Create**
(con el tipo de atributo `text` o `integer`, segun admita el panel).

- Nombre del atributo: `FreeRADIUSVLAN`.
- Valor: el numero de VLAN que ese grupo debe recibir, por ejemplo `30`.

Hazlo en **cada grupo** que deba asignar una VLAN distinta de la de reserva.
El lookup de `post-auth` busca `?FreeRADIUSVLAN?sub?(member=<dn del usuario>)`
dentro de `LDAP_GROUP_BASE_DN`, asi que el atributo tiene que estar en el grupo
y no en el usuario, y el nombre es exactamente `FreeRADIUSVLAN` (mayusculas
incluidas, el lookup distingue mayusculas).

El directorio publica ademas los atributos custom como atributos LDAP
ordinarios, que es justo lo que permite que `rlm_ldap` los lea sin ninguna
configuracion extra.

Se espera ver: cada grupo con el atributo `FreeRADIUSVLAN` visible en su
pestana de atributos. Un grupo sin ese atributo no es un error: su usuarios
caen en `DEFAULT_VLAN`, que es el comportamiento previsto.

### 7. Verificar con `ldapsearch`

Desde la maquina de trabajo, con el Outpost ya en marcha:

```bash
ldapsearch -x -H ldap://172.16.1.25:389 \
  -D 'cn=svc-freeradius,ou=users,<base DN del paso 2>' \
  -W \
  -b '<base DN del paso 2>' \
  '(cn=<nombre de un usuario de prueba>)' \
  cn uid mail memberOf
```

Para comprobar el atributo de VLAN:

```bash
ldapsearch -x -H ldap://172.16.1.25:389 \
  -D 'cn=svc-freeradius,ou=users,<base DN del paso 2>' \
  -W \
  -b 'ou=groups,<base DN del paso 2>' \
  '(objectClass=group)' \
  cn memberOf FreeRADIUSVLAN
```

Se espera ver:

| Consulta | Resultado esperado |
|---|---|
| Puerto 389 | `Test-NetConnection 172.16.1.25 -Port 389` devuelve `TcpTestSucceeded : True`. |
| Bind | Devuelve `dn: cn=svc-freeradius,...` sin `Invalid credentials`. |
| Usuario | Una entrada con `cn`, `uid`, `mail`, `memberOf` y `ak-active`. |
| Grupos | Entradas con `cn`, `uid`, `gidNumber`, `member`, `memberOf`. |
| VLAN | `FreeRADIUSVLAN: 30` en los grupos que la tienen definida. |
| Con un usuario normal | Solo devuelve su propia ficha y sus grupos: confirma que el permiso del paso 4 esta bien acotado. |

Si la consulta con `svc-freeradius` devuelve `No such object` o cero
entradas para un usuario que si existe en el panel, el problema es de permiso
(paso 4) y no de credenciales.

## Configurar el `.env` para LDAP

Las nueve variables van en `.env` (no en `.env.example`, que es la plantilla sin
secretos). `docker-compose.yml` las pasa al contenedor `radius` y
`configure_ldap()` las valida al arrancar.

```bash
# --- Conexion al Outpost LDAP ---
# Del paso 3: host donde escucha el Outpost y puerto configurado en el outpost.
LDAP_HOST=172.16.1.25
LDAP_PORT=389

# Del paso 2: campo "Base DN (parent DN)" del Provider LDAP, copiado tal cual.
LDAP_BASE_DN=dc=ejemplo,dc=local

# Del paso 4: DN completo del usuario de servicio, incluido el usuario.
LDAP_BIND_DN=cn=svc-freeradius,ou=users,dc=ejemplo,dc=local

# Del paso 5: el app password generado para ese usuario.
LDAP_BIND_PW=

# Del paso 2: filtro de busqueda de usuarios. El directorio publica cn, uid,
# mail, memberOf y ak-active, asi que por defecto se busca por cn.
LDAP_USER_FILTER=(cn=%{User-Name})

# Del paso 2: rama donde el Provider publica los grupos. Vacio = default del
# script: ou=groups,<LDAP_BASE_DN>. Ajustar solo si el directorio publica los
# grupos en otra rama.
LDAP_GROUP_BASE_DN=ou=groups,dc=ejemplo,dc=local

# Vacio = default del script: (objectClass=group). Debe corresponder al
# objectClass con el que el directorio sirve los grupos.
LDAP_GROUP_FILTER=(objectClass=group)

# Del paso 6 / politica de red: VLAN aplicada cuando el usuario autentica y su
# grupo no define FreeRADIUSVLAN.
DEFAULT_VLAN=20
```

Que dato del panel corresponde a cada una:

| Variable | Obligatoria | Origen en el panel | Si esta mal |
|---|---|---|---|
| `LDAP_HOST` | no (vacia = modo base) | Host del Outpost (paso 3) | Modo base: LDAP queda completamente desactivado y solo se autentica contra SQL. |
| `LDAP_PORT` | no (`389`) | Puerto configurado en el Outpost (paso 3) | Fallo de conexion del modulo `ldap`; la autenticacion LDAP nunca llega a ejecutarse. |
| `LDAP_BASE_DN` | si con `LDAP_HOST` | Base DN (parent DN) del Provider (paso 2) | Contenedor termina con codigo 1 por fail-fast, nombrando la variable que falta. |
| `LDAP_BIND_DN` | si con `LDAP_HOST` | DN del usuario `svc-freeradius` (paso 4) | Idem, fail-fast en el arranque. |
| `LDAP_BIND_PW` | si con `LDAP_HOST` | App password (paso 5) | Idem, fail-fast en el arranque. |
| `LDAP_USER_FILTER` | no (`(cn=%{User-Name})`) | Atributos publicados por el Provider (paso 2) | El usuario no se encuentra aunque el bind sea correcto. |
| `LDAP_GROUP_BASE_DN` | no (`ou=groups,<LDAP_BASE_DN>`) | Rama de grupos del Provider (paso 2) | Sin resolucion de grupos y VLAN siempre en `DEFAULT_VLAN`. |
| `LDAP_GROUP_FILTER` | no (`(objectClass=group)`) | ObjectClass real de los grupos (paso 2) | Igual que el anterior: filtro equivocado, grupos vacios. |
| `DEFAULT_VLAN` | no (`20`) | Politica de red, no del panel | Todos los usuarios sin atributo caen a otra VLAN; ademas exige reconstruir la imagen (ver siguiente seccion). |

`LDAP_BIND_PW` es la unica que es un secreto puro: no aparece en ningun sitio del
panel una vez generado. Guardala en `.env`, que esta en `.gitignore`, y en
ningun otro archivo.

## Levantar y probar

### 1. Reconstruir la imagen de FreeRADIUS

```bash
docker compose build radius
```

Este paso es **obligatorio** cuando se tocan `LDAP_BASE_DN`,
`LDAP_GROUP_BASE_DN`, `LDAP_GROUP_FILTER` o `DEFAULT_VLAN`, y no es opcional
poco mas:

- El bloque `VLAN CONFIG` de `Post-Auth-Type REJECT` se inserta en
  `sites-available/default` con un marcador idempotente. En el primer arranque
  escribe el lookup de `FreeRADIUSVLAN` con la `group_base_dn` **horneada en el
  texto** y el valor de `DEFAULT_VLAN` **horneado tambien**. En arranques
  siguientes el script encuentra el marcador, imprime `VLAN post-auth already
  applied, skipping.` y no reescribe nada.
- Es decir: `docker compose up -d` o `docker compose restart radius` por si
  solos **no** cambian el bloque de VLAN aunque cambies esas variables en
  `.env`. Sin `build` seguirian apuntando al base DN y al VLAN antiguos.
- Lo que si se reescribe en cada arranque son `server`, `port`, `identity`,
  `password`, `base_dn`, el filtro de usuario y el bloque `group {}`; esos si
  cambian sin reconstruir.

### 2. Levantar los contenedores

```bash
docker compose up -d
docker compose ps
```

### 3. Confirmar en el log que LDAP quedo configurado

```bash
docker compose logs radius | grep -Ei 'ldap|vlan'
```

| Linea del log | Significado |
|---|---|
| `LDAP configured against 172.16.1.25:389 (base_dn=..., group_base_dn=..., group_filter=...).` | LDAP activo y completo: es la linea que confirma el exito. |
| `VLAN post-auth enabled.` | El bloque de VLAN se inserto en este arranque. |
| `VLAN post-auth already applied, skipping.` | Ya existia de un arranque anterior: si cambiaste `DEFAULT_VLAN` o `LDAP_GROUP_BASE_DN` y ves esto, falta `docker compose build radius`. |
| `LDAP group settings empty, using defaults for: LDAP_GROUP_BASE_DN LDAP_GROUP_FILTER` | Aviso, no error: se aplicaron `ou=groups,<base>` y `(objectClass=group)`. |
| `LDAP disabled (LDAP_HOST empty), base mode` | LDAP no activo: `LDAP_HOST` esta vacia en `.env`. |
| `LDAP_HOST is set but LDAP_BASE_DN is empty. Set LDAP_BASE_DN or unset LDAP_HOST.` | Fail-fast: el contenedor muere en el arranque nombrando la variable que falta. |
| `raddb/mods-available/ldap not found: the rlm_ldap module (freeradius-ldap) is missing from the image.` | La imagen no lleva `freeradius-ldap` instalado: problema de la imagen, no de `.env`. |

Comprobacion de que el modulo quedo enlazado y habilitado:

```bash
docker exec radius ls -l /etc/freeradius/mods-enabled/ldap
docker exec radius grep -A6 'group {' /etc/freeradius/mods-available/ldap
docker exec radius grep -c 'VLAN CONFIG' /etc/freeradius/sites-available/default
```

Lo esperado: el symlink a `ldap` existe, el bloque `group {}` muestra
`name_attribute = cn` y `membership_attribute = 'memberOf'`, y el ultimo
comando devuelve `1`.

### 4. Probar la autenticacion

Contra el propio contenedor, usando el secreto declarado en la tabla `nas`:

```bash
docker exec radius radtest usuario-prueba su-contrasena 127.0.0.1 0 "$DEFAULT_CLIENT_SECRET"
```

O desde la maquina, contra el puerto publicado:

```bash
radtest usuario-prueba su-contrasena 172.16.1.25 0 "$DEFAULT_CLIENT_SECRET"
```

Lo que hay que leer en la salida:

| Linea | Significado |
|---|---|
| `Access-Accept` | Credenciales validadas contra LDAP y sesion autorizada. |
| `Tunnel-Private-Group-Id = "30"` | La VLAN se resolvio desde el atributo `FreeRADIUSVLAN` del grupo. Es el resultado correcto y el que aplica el AP. |
| `Tunnel-Private-Group-Id = "20"` con `DEFAULT_VLAN=20` | La VLAN cayo a la reserva: el usuario no esta en ningun grupo resoluble o su grupo no define `FreeRADIUSVLAN`. |
| `Tunnel-Type := VLAN` y `Tunnel-Medium-Type := IEEE-802` | Siempre presentes cuando LDAP esta activo: los emite el bloque `VLAN CONFIG`. |
| `Access-Reject` | La autenticacion fallo; el bloque de VLAN no llega a decidir nada. |
| Sin linea `Tunnel-Private-Group-Id` | LDAP esta en modo base: el bloque de VLAN no se inserta cuando `LDAP_HOST` esta vacia. |

Ejemplo de salida satisfactoria:

```
Access-Request
    User-Name = "usuario-prueba"
    User-Password = "..."
    NAS-IP-Address = 172.16.1.25
    NAS-Port = 0

Access-Accept
    Tunnel-Type := VLAN
    Tunnel-Medium-Type := IEEE-802
    Tunnel-Private-Group-Id = "30"
```

Para comprobar el bind de forma aislada, sin FreeRADIUS de por medio:

```bash
docker exec radius ldapsearch -x -H "ldap://$LDAP_HOST:$LDAP_PORT" \
  -D "$LDAP_BIND_DN" -w "$LDAP_BIND_PW" \
  -b "$LDAP_BASE_DN" "(cn=usuario-prueba)" cn memberOf
```

### 5. Tabla de diagnostico

| Sintoma | Causa | Accion |
|---|---|---|
| `Access-Reject` aunque el bind LDAP sea correcto | El metodo EAP del NAS no es compatible con bind-as-user (tipico con PEAP/EAP-TLS contra un directorio que solo valida contrasenas) | Cambiar el metodo EAP del NAS a PAP o MSCHAPv2, o configurar en el NAS un metodo que el Provider acepte. |
| `Tunnel-Private-Group-Id` siempre igual a `DEFAULT_VLAN` | El usuario no pertenece a ningun grupo resoluble, o su grupo no tiene el atributo `FreeRADIUSVLAN` | Comprobar con `ldapsearch ... "(cn=usuario)" memberOf` que el `memberOf` apunta a un grupo existente, y anadir `FreeRADIUSVLAN` a ese grupo (paso 6). |
| `Tunnel-Private-Group-Id` siempre igual al valor antiguo tras cambiar `.env` | El bloque `VLAN CONFIG` ya existia y el marcador idempotente impidio reescribirlo | `docker compose build radius` y despues `docker compose up -d` (paso 1). |
| Log: `LDAP disabled (LDAP_HOST empty), base mode` | `LDAP_HOST` vacia en `.env`, o el `.env` no se esta leyendo | Rellenar `LDAP_HOST` y ejecutar `docker compose config` para ver que valor llega al contenedor. |
| Contenedor `radius` sale con codigo 1 al arrancar | Fail-fast: falta `LDAP_BASE_DN`, `LDAP_BIND_DN` o `LDAP_BIND_PW` | Rellenar la variable que nombra el mensaje de error, o vaciar `LDAP_HOST` para volver a modo base. |
| Modulo `ldap` no conecta (fallo de `rlm_ldap` al hacer bind) | El Outpost LDAP no existe todavia o el puerto 389 sigue cerrado | Crear el Outpost (paso 3) y verificar `Test-NetConnection 172.16.1.25 -Port 389`. |
| `Invalid credentials` en el log de `rlm_ldap` | App password caducado o mal copiado en `LDAP_BIND_PW` | Generar un app password nuevo (paso 5) y actualizar `.env`. |
| La busqueda LDAP devuelve cero entradas sin error de credenciales | Falta el permiso "Search full LDAP directory" en el rol de `svc-freeradius` | Asignar el permiso sobre el provider (paso 4). |
| `Access-Reject` con el NAS registrado pero sin peticion en el log | El NAS no esta en la tabla `nas` o el secreto compartido no coincide | Ver **Registrar NAS** mas abajo y despues `docker compose restart radius`. |
| El AP autentica pero no cambia la VLAN | La WLAN no tiene activa la asignacion de VLAN por RADIUS | Activar en el AP la asignacion de VLAN por RADIUS (consume `Tunnel-Private-Group-Id`). |

## API del proveedor de identidad (automatizar)

El panel ya expone una API REST v3 en la misma maquina que sirve la web. Sirve
para lo que no conviene hacer a mano: migrar usuarios en lote, crear grupos y
asignar membresias desde un script, o sincronizar un inventario.

Datos de conexion:

| Dato | Valor |
|---|---|
| Base de la API | `http://172.16.1.25:9000/api/v3` |
| Autenticacion | `Authorization: Bearer <token>` |
| Formato | JSON en peticiones y respuestas (`Content-Type: application/json`) |
| Origen del token | Panel: **User settings -> Tokens -> Create Token** (ruta de menu del propio usuario con sesion iniciada) |

Al crear el token el panel muestra el valor **una sola vez**. Copialo
inmediatamente: despues no se vuelve a mostrar.

> El token es una credencial de administracion. No se versiona, no se pega en un
> README, issue ni mensaje: va solo en `.env` o en una variable de entorno del
> entorno desde el que se ejecuta el script.

Variables de entorno para los ejemplos:

```bash
export IDP_BASE='http://172.16.1.25:9000/api/v3'
export IDP_TOKEN='<el token del panel>'
```

### Listar usuarios

```bash
curl -sS -H "Authorization: Bearer $IDP_TOKEN" \
  "$IDP_BASE/core/users/?page_size=200"
```

```json
{
  "pagination": {
    "next": "http://172.16.1.25:9000/api/v3/core/users/?page=2&page_size=200",
    "previous": null,
    "count": 2,
    "current": 1,
    "total_pages": 1,
    "start": 1,
    "end": 2
  },
  "results": [
    {
      "pk": "b4a1f2c8-0d3e-4f5a-9b6c-1d2e3f4a5b6c",
      "username": "svc-freeradius",
      "name": "svc-freeradius",
      "email": "svc-freeradius@ejemplo.local",
      "is_active": true,
      "type": "internal_user",
      "ak_groups": []
    },
    {
      "pk": "9e8d7c6b-5a4f-3e2d-1c0b-9a8f7e6d5c4b",
      "username": "usuario-prueba",
      "name": "Usuario Prueba",
      "email": "usuario.prueba@ejemplo.local",
      "is_active": true,
      "type": "internal_user",
      "ak_groups": []
    }
  ]
}
```

Para filtrar por nombre de usuario:

```bash
curl -sS -H "Authorization: Bearer $IDP_TOKEN" \
  "$IDP_BASE/core/users/?username=usuario-prueba"
```

### Crear usuario

```bash
curl -sS -X POST \
  -H "Authorization: Bearer $IDP_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
        "username": "nuevo.usuario",
        "name": "Nuevo Usuario",
        "email": "nuevo.usuario@ejemplo.local",
        "is_active": true,
        "type": "internal_user"
      }' \
  "$IDP_BASE/core/users/"
```

Respuesta `201 Created` con el usuario creado:

```json
{
  "pk": "3c2b1a09-8f7e-4d6c-b5a4-9382716f5e4d",
  "username": "nuevo.usuario",
  "name": "Nuevo Usuario",
  "email": "nuevo.usuario@ejemplo.local",
  "is_active": true,
  "type": "internal_user",
  "ak_groups": []
}
```

El campo `type` es obligatorio y debe ser `internal_user`; sin el la peticion
se rechaza con `400 Bad Request`. La respuesta es la que hay que guardar: el
campo `pk` (UUID) es el que se usa como referencia en las llamadas a grupos.

### Listar grupos

```bash
curl -sS -H "Authorization: Bearer $IDP_TOKEN" \
  "$IDP_BASE/core/groups/?page_size=200"
```

```json
{
  "pagination": {
    "next": null,
    "previous": null,
    "count": 2,
    "current": 1,
    "total_pages": 1,
    "start": 1,
    "end": 2
  },
  "results": [
    {
      "pk": "7f6e5d4c-3b2a-4190-8f7e-6d5c4b3a2190",
      "name": "red-lobby",
      "is_superuser": false,
      "parent": null,
      "users": [],
      "attributes": {
        "FreeRADIUSVLAN": "30"
      }
    },
    {
      "pk": "5a4b3c2d-1e0f-4a9b-8c7d-6e5f4a3b2c1d",
      "name": "red-oficina",
      "is_superuser": false,
      "parent": null,
      "users": [],
      "attributes": {
        "FreeRADIUSVLAN": "40"
      }
    }
  ]
}
```

Aqui se ve tambien el atributo custom del paso 6: cada grupo lleva su
`FreeRADIUSVLAN`, que es exactamente lo que el lookup de `post-auth` busca en
el directorio.

### Crear grupo

```bash
curl -sS -X POST \
  -H "Authorization: Bearer $IDP_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
        "name": "red-almacen",
        "is_superuser": false,
        "attributes": {
          "FreeRADIUSVLAN": "50"
        }
      }' \
  "$IDP_BASE/core/groups/"
```

Respuesta `201 Created`:

```json
{
  "pk": "1a2b3c4d-5e6f-4071-8293-a4b5c6d7e8f9",
  "name": "red-almacen",
  "is_superuser": false,
  "parent": null,
  "users": [],
  "attributes": {
    "FreeRADIUSVLAN": "50"
  }
}
```

Incluir `FreeRADIUSVLAN` en el mismo `POST` evita el paso intermedio de crear
el grupo y anadir despues el atributo, que es el estado en el que los usuarios
del grupo ya caen en `DEFAULT_VLAN` mientras se completa.

### Agregar un usuario a un grupo

Con los UUID obtenidos en los dos pasos anteriores:

```bash
curl -sS -X POST \
  -H "Authorization: Bearer $IDP_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
        "user": "9e8d7c6b-5a4f-3e2d-1c0b-9a8f7e6d5c4b"
      }' \
  "$IDP_BASE/core/groups/7f6e5d4c-3b2a-4190-8f7e-6d5c4b3a2190/add_user/"
```

```json
{
  "pk": "d4c3b2a1-9087-4f6e-b5c4-d3c2b1a09876",
  "name": "red-lobby",
  "is_superuser": false,
  "parent": null,
  "users": [
    "9e8d7c6b-5a4f-3e2d-1c0b-9a8f7e6d5c4b"
  ],
  "attributes": {
    "FreeRADIUSVLAN": "30"
  }
}
```

El cuerpo lleva **el UUID del usuario**, no su nombre: el UUID sale del `pk`
devuelto por `POST /core/users/` o por `GET /core/users/`. Es un endpoint de
accion y devuelve el grupo ya actualizado con la lista `users`, asi que sirve
tambien para verificar si la membresia se aplico.

Al terminar un lote de altas conviene comprobar el resultado por LDAP, que es
la vista que consume FreeRADIUS:

```bash
ldapsearch -x -H ldap://172.16.1.25:389 \
  -D 'cn=svc-freeradius,ou=users,<base DN>' -W \
  -b 'ou=groups,<base DN>' '(cn=nuevo.usuario)' memberOf FreeRADIUSVLAN
```

## Registrar NAS

> Para alta manual de uno en uno, sigue leyendo esta seccion. Si lo que hace
> falta es dar de alta muchos equipos de una vez, la via practica es preparar un
> archivo CSV con una fila por NAS (IP, nombre corto, secreto, descripcion) y
> cargarlo en bloque: bucle sobre el CSV llamando a `scripts/add-nas.sh` por
> linea, o un `INSERT ... SELECT ... WHERE NOT EXISTS` generado y ejecutado
> directamente en SQL. El `INSERT` es idempotente, asi que repetir la carga no
> duplica entradas; ver tambien la seccion **API del proveedor de identidad
> (automatizar)** para el caso de que el inventario venga de la API.

Los clientes RADIUS (NAS: access points, switches, controladores) **no** viven
en el directorio de identidad, sino en la tabla `nas` de MariaDB, porque
`read_clients = yes` esta activo en `mods-available/sql` y FreeRADIUS carga esa
tabla al arrancar. El directorio LDAP solo modela usuarios y grupos.

Cada NAS se registra con su IP/CIDR, un nombre corto y el secreto compartido que
tendra configurado el propio dispositivo:

| Columna | Valor | Nota |
|---|---|---|
| `nasname` | IP o CIDR del NAS | Clave de identificacion (`WHERE NOT EXISTS` la usa). |
| `shortname` | Nombre corto | Identificacion legible. |
| `type` | `other` | Los AP UniFi no necesitan `type` mas especifico. |
| `ports` | `0` | Todos los puertos. |
| `secret` | Secreto compartido | Debe coincidir con el configurado en el NAS. |
| `description` | Texto libre | Opcional. |

### Con `scripts/add-nas.sh`

```bash
export MYSQL_HOST=radius-mysql MYSQL_DATABASE=radius MYSQL_USER=radius
export MYSQL_PASSWORD='<la de tu .env>'
./scripts/add-nas.sh 172.16.1.10 AP-Lobby 'secreto-del-ap' 'AP del lobby'
```

El script usa un fichero de credenciales temporal con permisos `600` y hace un
`INSERT` idempotente: si el NAS ya existe no lo duplica.

### INSERT manual en SQL

```sql
INSERT INTO nas (nasname, shortname, type, ports, secret, server, community, description)
SELECT '172.16.1.10', 'AP-Lobby', 'other', 0, 'secreto-del-ap', NULL, '', 'AP del lobby'
WHERE NOT EXISTS (SELECT 1 FROM nas WHERE nasname = '172.16.1.10');
```

### Reinicio

FreeRADIUS lee los clientes al arrancar, asi que despues de registrar un NAS:

```bash
docker compose restart radius
```

### Lado UniFi (Settings -> Network -> RADIUS)

- Servidor de autenticacion: `172.16.1.25`, puerto `1812`.
- Servidor de contabilidad: `172.16.1.25`, puerto `1813`.
- Secreto compartido: el mismo que el del `INSERT` (columna `secret`).
- Para que la VLAN asignada por RADIUS se aplique, activa la asignacion de
  VLAN por RADIUS en la WLAN; es el atributo `Tunnel-Private-Group-Id` que
  devuelve el bloque `VLAN CONFIG` de `post-auth`.

## Referencias

- Docker Hub tags: https://hub.docker.com/r/freeradius/freeradius-server/tags
- GitHub freeradius-server: https://github.com/FreeRADIUS/freeradius-server
- Atribucion de origen: el script `init-freeradius-ldap.sh` se basa en el script `init-freeradius.sh` del proyecto daloRADIUS (https://github.com/lirantal/daloradius), licencia GPLv2.
