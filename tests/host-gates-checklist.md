# Host gates checklist — freeRadius_LDAP iteración 1 (lift)

Fecha: 2026-10-09 · Fase: Implement iteración 1 (lift) · Rol: qa-senior (plan, NO ejecutado: sin Docker en este entorno).
Ámbito: solo iteración 1. CA-01…CA-06 aplicables; CA-07 es iteración 2 (bloqueada por P-04 authentik, sin mocks).
Fuentes: `Documentacion/freeRadius_LDAP/specs/001-freeradius-ldap/spec.md` (FR-001…FR-007, CA-01…CA-07),
`specs/001-freeradius-ldap/converge.md` (gates L-01…L-07, CT-01…CT-08, §4 riesgos aceptados),
`src/freeRadius_LDAP/docker-compose.yml` (71 líneas), `.env.example` (32 líneas), `README.md` (61 líneas),
`Dockerfile` (45 líneas), `init-freeradius-ldap.sh` (401 líneas), `scripts/init-env.ps1` (102 líneas),
`scripts/init-env.sh` (117 líneas), `.gitignore` (5 líneas).

Cómo usar este archivo en el host con Docker: directorio de trabajo `src/freeRadius_LDAP/` para todos los
comandos salvo indicación contraria. Marcar cada casilla `[ ]` → `[x]` solo con la salida real guardada en
bitácora. El lift está verde solo si P-00 + L-01…L-07 + NR-01…NR-02 encadenan sin errores. Si un gate falla,
no avanzar al siguiente: diagnosticar, registrar y repetir desde el gate que falló.

Convención de veredicto usada en cada gate: PASS = salida esperada exacta + código 0 donde se indica.
FAIL = cualquier desviación listada como ejemplo de fallo. Los ejemplos de salida son ilustrativos del
formato (nombres, hashes y tiempos varían por host); lo normativo es el criterio PASS/FAIL, no el hash.

---

## P-00 — Previa: `init-env` + `.env` + permisos (obligatoria antes de L-01)

Mapeo: FR-007 (secretos fuera de git), CA-06 (sin secretos en git), converge §4 (rotación de secretos al
desplegar como mitigación mínima obligatoria del lift), tasks T4.

- [ ] P-00.1 — Generar `.env` desde plantilla limpia.

  Bash (Git Bash / Linux):

      cd src/freeRadius_LDAP
      rm -f .env
      ./scripts/init-env.sh
      ls -l .env && grep -c CHANGE_ME .env || true

  PowerShell 7+:

      cd src/freeRadius_LDAP
      Remove-Item -LiteralPath .env -ErrorAction SilentlyContinue
      ./scripts/init-env.ps1
      Get-Item .env | Select-Object Name, Length
      Select-String -Pattern 'CHANGE_ME' .env

  Salida esperada: `init-env` informa copia `.env.example -> .env` y dos variables generadas
  (`MYSQL_PASSWORD`, `DEFAULT_CLIENT_SECRET`); no imprime valores de secretos; crea `./data/` si falta.
  PASS: existe `.env`; `grep/Select-String CHANGE_ME` sobre `MYSQL_PASSWORD` y `DEFAULT_CLIENT_SECRET`
  devuelve 0 coincidencias; el operador confirma que jamás opera con `testing123` / `adminsecret`.
  FAIL (ejemplos): `No se encontro .env.example` (plantilla borrada); `.env` conserva
  `MYSQL_PASSWORD=CHANGE_ME_MYSQL_PASSWORD` (init-env no ejecutado o ejecutado con error);
  el operador reutiliza un `.env` antiguo con `DEFAULT_CLIENT_SECRET=testing123`.
  Si FAIL: repetir `init-env` (con `--force` / `-Force` solo si se quiere regenerar) y no pasar a L-01.

- [ ] P-00.2 — Permisos de `.env` a 600 y verificación de git.

  Bash:

      chmod 600 .env && stat -c '%a %n' .env
      git status --porcelain -- src/freeRadius_LDAP/.env src/freeRadius_LDAP/data/ || true
      git grep -i password -- src/freeRadius_LDAP/.env.example || echo NO_REAL_PASSWORDS_IN_EXAMPLE

  PowerShell 7+ (equivalente funcional; ver defecto D-05 reportado a devops):

      icacls .env
      git status --porcelain -- src/freeRadius_LDAP/.env src/freeRadius_LDAP/data/
      git grep -i password -- src/freeRadius_LDAP/.env.example

  Salida esperada: `stat` muestra `600 .env`; `git status --porcelain` no lista `.env` ni `data/`
  (ambos están en `src/freeRadius_LDAP/.gitignore:1-2`); `git grep -i password -- .env.example` solo muestra
  claves con valor `CHANGE_ME_*`, sin secretos reales.
  PASS: `600` confirmado + `git status` vacío para `.env`/`data/` + `.env.example` sin valores reales.
  FAIL (ejemplos): `stat` muestra `644` (permisos abiertos); `git status` lista `src/freeRadius_LDAP/.env`
  (`.gitignore` roto o `.env` forzado con `-f`); `.env.example` contiene una contraseña real en claro.
  Si FAIL: corregir permisos / `.gitignore` y repetir P-00 antes de L-01. Cubre CA-06.

- [ ] P-00.3 — Completar `MYSQL_ROOT_PASSWORD` manualmente (obligatorio; init-env no lo genera).

  Contexto real: `docker-compose.yml:15` exige `MYSQL_ROOT_PASSWORD` (`${...:?…}`) pero
  `scripts/init-env.sh:107-108` y `scripts/init-env.ps1:92-93` solo generan `MYSQL_PASSWORD` y
  `DEFAULT_CLIENT_SECRET` (defecto D-01 reportado a devops, sin corregir aquí). `.env.example:15` trae
  `MYSQL_ROOT_PASSWORD=CHANGE_ME_MYSQL_ROOT_PASSWORD`, que satisface la sintaxis `${:?}` pero es un
  marcador, no un secreto.

  Bash:

      grep -n 'MYSQL_ROOT_PASSWORD' .env || true
      python3 -c "import secrets; print(secrets.token_urlsafe(36))"

  Tomar el valor impreso y ponerlo en `.env` editando solo esa línea
  (`MYSQL_ROOT_PASSWORD=<valor-generado>`), sin tocar las dos variables ya generadas.
  Verificar después: `grep -c CHANGE_ME .env` debe ser `0`.

  PASS: ninguna línea de `.env` contiene `CHANGE_ME`; las tres claves (`MYSQL_PASSWORD`,
  `MYSQL_ROOT_PASSWORD`, `DEFAULT_CLIENT_SECRET`) tienen valores aleatorios distintos.
  FAIL (ejemplos): `.env` conserva `MYSQL_ROOT_PASSWORD=CHANGE_ME_MYSQL_ROOT_PASSWORD` (despliegue con
  marcador, viola el espíritu de CA-06/FR-007 aunque `config` salga 0); las tres claves comparten el mismo
  valor (copiar-pegar, rotación inválida). Si FAIL: generar y sustituir antes de L-03, porque L-03 aborta
  o arranca inseguro en caso contrario.

---

## L-01 — `config`: sintaxis válida, 2 servicios, sin `radius-web` (gate `config`)

Mapeo: CA-01 (`config` código 0, 2 servicios, imagen oficial), FR-001 (pila de 2 servicios), G-01/G-02/G-03,
tasks T1/T5, converge §3 L-01. Tras CT-01 la imagen de `radius` debe ser la propia del proyecto.

- [ ] L-01 — Ejecutar y validar configuración.

  Comando (Bash y PowerShell, desde `src/freeRadius_LDAP/`):

      docker compose config

  Comandos de apoyo para evidenciar (misma salida, filtrada):

      docker compose config | grep -E 'service:|image:|radius-web|lirantal|1812|1813' || true
      docker compose config --services

  Salida esperada (PASS): código de salida 0; `docker compose config --services` lista exactamente dos
  líneas, `radius-mysql` y `radius`, en cualquier orden; `image: mariadb:11.8` en `radius-mysql`
  (`docker-compose.yml:4`); `image: freeradius-ldap:3.2.10-local` en `radius` (`docker-compose.yml:27`,
  construida desde `Dockerfile:10` `FROM freeradius/freeradius-server:3.2.10`); puertos
  `'1812:1812/udp'` y `'1813:1813/udp'` en `radius` (`docker-compose.yml:40-42`); cero ocurrencias de las
  cadenas `radius-web` y `lirantal` en toda la salida (incluye verificación de que el volumen heredado
  `./data/daloradius` y las variables `MAIL_*` no existen).

  Ejemplo de salida PASS (formato; hashes y orden de claves varían):

      services:
        radius-mysql:
          image: mariadb:11.8
          ...
        radius:
          image: freeradius-ldap:3.2.10-local
          ports:
            - published: 1812
              target: 1812
              protocol: udp
            - published: 1813
              target: 1813
              protocol: udp

  y `docker compose config --services` →

      radius-mysql
      radius

  FAIL (ejemplos, cualquiera bloquea el lift): código distinto de 0 con `yaml: line …` (sintaxis rota);
  `config --services` lista `radius-web` (lift incompleto, FR-001 roto); `image: lirantal/dalofreeradius`
  en `radius` (CT-01 sin aplicar, ver defecto D-02); `Set MYSQL_PASSWORD in .env` / `Set
  MYSQL_ROOT_PASSWORD in .env` / `Set DEFAULT_CLIENT_SECRET in .env` (P-00 sin completar);
  ausencia de `1812:1812/udp` (FR-002 roto). Si FAIL por sintaxis, corregir YAML y repetir L-01; si FAIL
  por imagen antigua, aplicar CT-01 antes de continuar; si FAIL por variable, volver a P-00.

---

## L-02 — `pull/build`: imágenes disponibles localmente (gate `pull/build`)

Mapeo: tasks T2, converge §3 L-02, decisión D-03 (fallback `3.2.8` si `3.2.10` no existe en el registro),
CA-01 indirecto (la imagen documentada debe resolverse).

- [ ] L-02.1 — Construir la imagen propia (obligatoria: `radius` es `build:`, no `pull:`).

  Comando (desde `src/freeRadius_LDAP/`):

      docker compose build radius

  Salida esperada (PASS): código 0; paso `FROM freeradius/freeradius-server:3.2.10` resuelto
  (`Dockerfile:10`); `COPY ./init-freeradius-ldap.sh /app` + `chmod +x` sin errores; etiqueta final
  `freeradius-ldap:3.2.10-local`. Evidencia: `docker images freeradius-ldap --format '{{.Repository}}:{{.Tag}}'`
  lista `freeradius-ldap:3.2.10-local`.
  FAIL (ejemplos): `failed to resolve source … 3.2.10: not found` (aplicar fallback D-03 a `3.2.8` en
  `Dockerfile:10` y en el tag, anotarlo en bitácora y repetir); `COPY failed: init-freeradius-ldap.sh:
  no such file` (contexto de build erróneo, debe ser `.` según `docker-compose.yml:29-31`).

- [ ] L-02.2 — Descargar la base de datos.

  Comando:

      docker compose pull radius-mysql

  Salida esperada (PASS): `mariadb:11.8` descargada (`Downloaded newer image`) o ya actualizada
  (`up to date` / `Image is up to date`). Este paso separa fallos de red/registro de fallos de
  configuración: un fallo aquí nunca se diagnostica como bug del hook ni del LDAP.
  FAIL (ejemplos): `unauthorized` / `no such host` / `TLS handshake timeout` (red o registro, reintentar;
  no tocar el compose). Nota real: `docker compose pull` a secas intenta también `radius`, que al ser
  imagen local construida responde `no image to pull` o similar según versión; eso es comportamiento
  esperado, no fallo, siempre que L-02.1 esté en PASS (ver defecto D-03). Guardar ambas salidas.

---

## L-03 — `up -d`: arranque de la pila migrada (gate `up -d`)

Mapeo: tasks T6 (parte 1), FR-001/FR-003 (los dos contenedores existen), converge §3 L-03.

- [ ] L-03 — Levantar la pila en segundo plano.

  Comando (desde `src/freeRadius_LDAP/`):

      docker compose up -d

  Seguido inmediatamente de (solo lectura, sin sondas de protocolo todavía):

      docker compose ps --format '{{.Name}} {{.State}} {{.Health}}'

  Salida esperada (PASS): `up -d` informa `Creating/Created/Starting/Started radius-mysql` y `radius`
  (o `Running` si ya existían), crea la red por defecto, código 0, sin errores de variables y sin
  ninguna mención a `radius-web`. Tras este comando NO ejecutar `radclient`/`radtest` hasta que L-04
  confirme sano: una sonda prematura contra un demonio a medio iniciar produce timeouts indistinguibles
  de un fallo real.
  FAIL (ejemplos): `variable MYSQL_ROOT_PASSWORD is not set: Set MYSQL_ROOT_PASSWORD in .env` (volver a
  P-00.3); `Bind for 0.0.0.0:1812 failed: port is already allocated` (puerto ocupado por otro servicio o
  por un resto de daloRADIUS: liberar 1812/1813 y repetir); `service "radius" refers to undefined volume
  data/freeradius` (volúmenes manipulados a mano); `radius` entrando en bucle `Restarting (1) …` (pasar a
  `docker compose logs radius` y registrar la causa antes de cualquier reintento, no hacer `up -d`
  repetidos a ciegas).

---

## L-04 — `ps`: 2/2 sanos en <2 min (gate `ps`)

Mapeo: CA-02 (`ps` con `radius-mysql` y `radius` en healthy/running), FR-006 (healthchecks operativos con
sonda temporal aceptada), NFR-01 (2/2 healthy en <2 min sin contar `pull`), G-04, tasks T6.

- [ ] L-04 — Confirmar dos servicios sanos dentro del umbral.

  Comandos (desde `src/freeRadius_LDAP/`; medir tiempo con reloj desde el fin de L-03):

      docker compose ps
      docker inspect --format '{{.Name}} state={{.State.Status}} health={{.State.Health.Status}}' radius-mysql radius

  Salida esperada (PASS): `docker compose ps` muestra exactamente dos filas, `radius-mysql` y `radius`,
  ambas `running` con estado de salud `healthy` (p. ej. `Up X minutes (healthy)`); el `inspect` confirma
  `state=running health=healthy` en ambos; el tiempo desde `up -d` hasta 2/2 `healthy` es <120 s
  (descontando el `pull`/`build` de L-02). Healthchecks reales verificados: `radius-mysql` con
  `healthcheck.sh --connect --innodb_initialized` (`docker-compose.yml:19-24`, `start_period:
  ${MYSQL_HEALTH_START_PERIOD:-10m}`); `radius` con sonda interna `radclient … 127.0.0.1:18121 status
  adminsecret` (`docker-compose.yml:61-66`, `start_period: 30s`; el literal `adminsecret` y el puerto
  `18121` son la sonda temporal aceptada de CT-02/SR-02, ver nota).

  Ejemplo de salida PASS (tiempos ilustrativos):

      NAME           IMAGE                              STATUS
      radius-mysql   mariadb:11.8                       Up 45 seconds (healthy)
      radius         freeradius-ldap:3.2.10-local       Up 20 seconds (healthy)

  FAIL (ejemplos): `starting` persistente más allá de 2 min (apunta al healthcheck heredado CT-02:
  verificar sitio `status` habilitado por `init-freeradius-ldap.sh:141` con `docker compose exec radius
  ls -l /etc/freeradius/sites-enabled/status` y dejar constancia de sonda temporal vigente, sin tocar el
  compose en el lift); `unhealthy` en cualquiera (bloquea el lift: diagnosticar con `docker compose logs
  radius-mysql` / `docker compose logs radius` antes de pasar a L-05); tercera fila inesperada
  (`radius-web` resucitado, FR-001 roto). Nota: `MYSQL_HEALTH_START_PERIOD` por defecto es `10m`
  (`.env.example:25`), lo que puede enmascarar un mysql lento como `starting` largo; registrar el valor
  efectivo de la variable en bitácora junto al tiempo medido.

---

## L-05 — `radclient status` a `1812/udp` (gate Status-Server)

Mapeo: CA-03 (Status-Server responde en `1812/udp`), FR-002 (lado supervisión), FR-006, G-05, tasks T7
(parte 1), converge §3 L-05. Divergencia conocida A-02/CT-02: el healthcheck interno usa `18121` con
`adminsecret`; ESTE gate usa `1812` con el secreto real de `.env`.

- [ ] L-05 — Sonda Status-Server con el secreto real del NAS.

  Bash (con `.env` cargado en el shell):

      set -a; . ./.env; set +a
      echo 'FreeRADIUS-Statistics-Type = 1' | radclient -q -r 1 -t 3 127.0.0.1:1812 status "$DEFAULT_CLIENT_SECRET"
      echo "exit=$?"

  PowerShell 7+ (con `.env` cargado):

      Get-Content .env | Where-Object { $_ -match '^\s*[^#\s].*=' } | ForEach-Object { $k,$v = $_ -split '=',2; Set-Item -Path "env:$k" -Value $v }
      'FreeRADIUS-Statistics-Type = 1' | radclient -q -r 1 -t 3 127.0.0.1:1812 status "$env:DEFAULT_CLIENT_SECRET"
      "exit=$LASTEXITCODE"

  Salida esperada (PASS): el servidor responde con un paquete de estadísticas (contadores tipo
  `FreeRADIUS-Total-Access-Requests`, `FreeRADIUS-Total-Access-Accepts/Rejects`, uptime), sin la palabra
  `timeout`, código de salida 0. Prueba FR-002 por el lado de supervisión contra el puerto público real.

  Ejemplo de salida PASS (contadores ilustrativos, varían por host):

      Received response ID 1, code 2, length = 100
          FreeRADIUS-Total-Access-Requests = 3
          FreeRADIUS-Total-Access-Accepts = 2
          FreeRADIUS-Total-Access-Rejects = 0
      exit=0

  FAIL (ejemplos): `No reply from server: timeout` + código distinto de 0 en `1812` pero respuesta en
  `18121` con `adminsecret` (divergencia A-02 confirmada: registrar como prueba de que CT-02 sigue
  diferida, sin tocar el compose en el lift); timeout en AMBOS puertos (el demonio no escucha: devolver
  el diagnóstico a L-04, revisar `docker compose logs radius`); `Shared secret is incorrect` / silencio
  por secreto erróneo (el shell no cargó `.env` o el NAS registrado usa otro secreto: recargar `.env` y
  repetir, nunca igualar el secreto real a `adminsecret`).

---

## L-06 — `radtest` base + `Tunnel-Private-Group-Id` (gate autenticación)

Mapeo: FR-002 (lado autenticación), CA-04 (parcial en it.1: `Access-Accept` exigible; los 3 atributos
`Tunnel-*` completos son it.2 por CT-06), G-07 parcial, tasks T7, converge §3 L-06. Requisito del plan de
iteración: ejecutar el `radtest` base y ANOTAR el valor de `Tunnel-Private-Group-Id` observado.

- [ ] L-06.1 — `radtest` base con usuario de prueba del backend SQL.

  Prerrequisito: existe un usuario de prueba en `radcheck` (el lift no crea usuarios; si no hay ninguno,
  crearlo por SQL es trabajo de operador/devops, fuera de este plan; registrar usuario usado sin anotar
  su contraseña en la bitácora).

  Bash:

      set -a; . ./.env; set +a
      radtest <usuario-base> '<clave-base>' 127.0.0.1 0 "$DEFAULT_CLIENT_SECRET"

  PowerShell:

      radtest <usuario-base> '<clave-base>' 127.0.0.1 0 "$env:DEFAULT_CLIENT_SECRET"

  (Sustituir `<usuario-base>`/`<clave-base>` por el usuario real de prueba; guardar el comando exacto
  ejecutado en bitácora, redactando la clave.)

  Salida esperada (PASS it.1): línea `Received Access-Accept …` con código de salida 0, sin
  `Access-Reject` ni `no response`. Los tres atributos `Tunnel-Type=VLAN(13)`,
  `Tunnel-Medium-Type=IEEE-802(6)`, `Tunnel-Private-Group-Id=<vlan>` SE ANOTAN si aparecen (modo
  heredado con `use_tunneled_reply = yes` según `init-freeradius-ldap.sh:130`), pero su ausencia NO es
  FAIL en it.1: el bloque post-auth grupo→VLAN versionado con `DEFAULT_VLAN` pertenece a CT-06 (it.2) y
  converge §3 L-06 lo declara comportamiento esperado del lift, nunca fallo.

  Ejemplo PASS con VLAN heredada presente (vlan ilustrativa):

      Sent Access-Request Id 1 from 0.0.0.0:xxxxx to 127.0.0.1:1812 length 74
      Received Access-Accept Id 1 from 127.0.0.1:1812 to 127.0.0.1:xxxxx length 56
          Tunnel-Type:0 = VLAN(13)
          Tunnel-Medium-Type:0 = IEEE-802(6)
          Tunnel-Private-Group-Id:0 = "10"

  Ejemplo PASS sin VLAN (válido en it.1, anotar `Tunnel-* ausentes, esperado en lift`):

      Sent Access-Request Id 2 from 0.0.0.0:xxxxx to 127.0.0.1:1812 length 74
      Received Access-Accept Id 2 from 127.0.0.1:1812 to 127.0.0.1:xxxxx length 20

  FAIL (ejemplos, sí bloquean): `Received Access-Reject` sistemático (secreto de cliente erróneo o
  usuario ausente en backend SQL: diagnosticar con `docker compose logs radius` y con `auth=yes`,
  líneas 133-138 del script, que registran usuario/NAS/resultado sin contraseñas); `radclient: no
  response` (volver a L-04/L-05); `Shared secret is incorrect`. Un `Access-Reject` NO se maquilla
  reintentando con otro secreto al azar: se registra causa y se repite tras corregir.

- [ ] L-06.2 — Registrar `Tunnel-Private-Group-Id` observado (trazabilidad a CA-04/it.2).

  Anotar en bitácora junto a la salida de L-06.1: valor observado de `Tunnel-Private-Group-Id`
  (p. ej. `"10"`, `"20"`, o `ausente-en-lift`), usuario usado, hora, y secreto empleado solo como
  referencia (`DEFAULT_CLIENT_SECRET` de `.env`, sin copiar su valor). Este registro es la línea base
  contra la que la it.2 verificará CA-04 completo (`Tunnel-Private-Group-Id` igual a la VLAN esperada
  por grupo + caída a `DEFAULT_VLAN`). PASS: anotación completa. FAIL: L-06.1 en PASS pero sin
  anotación (el lift no es verde sin trazabilidad).

---

## L-07 — Fila en `radacct` tras el `radtest` (gate accounting)

Mapeo: FR-003 (accounting SQL en MariaDB `mariadb:11.8`), CA-05 (persiste), tasks T7, converge §3 L-07.
Cierra el lift demostrando persistencia; sin esta fila el lift NO es verde.

- [ ] L-07 — Consultar `radacct` y confirmar la fila del L-06.

  Comando (desde `src/freeRadius_LDAP/`; Bash y PowerShell idénticos porque corre dentro del contenedor):

      docker compose exec radius-mysql mariadb -u radius -p"$MYSQL_PASSWORD" -e "SELECT UserName, NASIPAddress, AcctStartTime, AcctStatusType FROM radius.radacct ORDER BY RadAcctId DESC LIMIT 3;"

  Con `.env` cargado en el shell antes (Bash: `set -a; . ./.env; set +a`. PowerShell: importar como en
  L-05). Alternativa sin exponer la clave en el historial: `docker compose exec radius-mysql mariadb -u
  radius -p -e "..."` e introducir `MYSQL_PASSWORD` por teclado.

  Salida esperada (PASS): al menos una fila con `UserName` igual al `<usuario-base>` de L-06,
  `NASIPAddress` `127.0.0.1` en prueba local, `AcctStartTime` coincidente con la hora del `radtest`
  (± minutos), y `AcctStatusType` coherente. Esquema creado por `init-freeradius-ldap.sh:279-315`
  (`init_database`, `ensure_daloradius_schema`, `ensure_docker_client`); conexión con
  `MYSQL_HOST/PORT/USER/PASSWORD/DATABASE` según `docker-compose.yml:43-49`.

  Ejemplo de salida PASS (valores ilustrativos):

      +----------+----------------+---------------------+----------------+
      | UserName | NASIPAddress   | AcctStartTime       | AcctStatusType |
      +----------+----------------+---------------------+----------------+
      | testuser | 127.0.0.1      | 2026-10-09 12:34:56 | Start          |
      +----------+----------------+---------------------+----------------+

  FAIL (ejemplos): `Empty set` tras un `Access-Accept` (causa en el cableado SQL del script, líneas
  143-155 y 279-315: investigar con `docker compose logs radius`; en ningún caso declarar verde sin la
  fila); `Access denied for user 'radius'@'…'` (clave `MYSQL_PASSWORD` errónea o `.env` no cargado);
  `Table 'radius.radacct' doesn't exist` (inicialización de esquema incompleta: revisar logs del primer
  arranque y `DB_LOCK` en `/data/.db_init_done`). Si FAIL: no cerrar el lift; registrar y diagnosticar.

---

## NR — No-regresión del lift (obligatoria para cerrar)

Mapeo: FR-001 (sin UI), §5 fuera de alcance del spec (sin `radius-web`, sin `MAIL_*`, sin backend propio),
NFR-03 (superficie mínima: solo `1812/udp`+`1813/udp`, `no-new-privileges`, `cap_drop NET_RAW`), converge
§1.1 (tercer servicio eliminado con su volumen), tasks T1.

- [ ] NR-01 — `radius-web` ausente e imagen propia (sin daloRADIUS).

  Comandos (desde `src/freeRadius_LDAP/`):

      docker compose config | grep -ci 'radius-web' || true
      docker compose config | grep -c 'lirantal' || true
      docker compose config | grep -E 'MAIL_' || echo NO_MAIL_VARS
      docker images freeradius-ldap --format '{{.Repository}}:{{.Tag}}'

  Salida esperada (PASS): primer conteo `0` (cero menciones a `radius-web`); segundo conteo `0` (cero
  restos de `lirantal` tras CT-01); `NO_MAIL_VARS` (ninguna variable `MAIL_*` heredada de la UI);
  `docker images` lista `freeradius-ldap:3.2.10-local` (o `:3.2.8-local` si se aplicó el fallback D-03,
  anotado). FAIL (ejemplos): cualquier conteo ≥1 (regresión: servicio web resucitado o imagen antigua);
  `MAIL_HOST`/`MAIL_PORT` presentes (herencia de UI no purgada); `docker images` vacío (L-02.1 sin hacer).

- [ ] NR-02 — Superficie mínima y secretos (NFR-03 + FR-007/CA-06, cierre).

  Comandos:

      docker compose config | grep -E 'published|no-new-privileges|NET_RAW|3306:3306|MYSQL_HOST_PORT' || true
      git status --porcelain -- src/freeRadius_LDAP/.env src/freeRadius_LDAP/data/ src/freeRadius_LDAP/var/ ; echo "git-exit=$?"
      docker compose exec radius-mysql ss -ltn 2>/dev/null || docker compose exec radius-mysql cat /proc/net/tcp 2>/dev/null || echo INSPECT_MANUAL

  Salida esperada (PASS): solo `1812/udp` y `1813/udp` publicados en `radius`
  (`docker-compose.yml:40-42`); `no-new-privileges:true` y `cap_drop: NET_RAW` en ambos servicios
  (`docker-compose.yml:7-10`, `33-36`); `radius-mysql` sin puertos publicados hacia el host (ninguna
  línea `3306:3306`; `MYSQL_HOST_PORT` de `.env.example:11` es documentación sin efecto en el compose
  actual, ver defecto D-04); `git status --porcelain` vacío para `.env`/`data/`/`var/`; MySQL solo
  alcanzable desde la red interna del compose. FAIL (ejemplos): `3306:3306` publicado (SR-06 roto);
  `cap_drop` ausente (NFR-03 roto); `.env` listado por git (CA-06 roto). Registrar valores efectivos.

---

## Apéndice A — Matriz de trazabilidad gate ↔ CA/spec (it.1)

| Gate | Cubre | Spec/plan |
|---|---|---|
| P-00 | CA-06, FR-007 | `spec.md §3 FR-007`, `§6 CA-06`, `converge.md §4`, tasks T4 |
| L-01 | CA-01, FR-001 | `spec.md §3 FR-001`, `§6 CA-01`, tasks T1/T5, converge L-01 (G-01/G-02/G-03) |
| L-02 | CA-01 indirecto | tasks T2, converge L-02, decisión D-03 fallback 3.2.8 |
| L-03 | FR-001, FR-003 (existencia) | tasks T6, converge L-03 |
| L-04 | CA-02, FR-006 (temporal), NFR-01 | `spec.md §3 FR-006`, `§4 NFR-01`, `§6 CA-02`, tasks T6, converge L-04 (G-04) |
| L-05 | CA-03, FR-002 (supervisión), FR-006 | `spec.md §3 FR-002/FR-006`, `§6 CA-03`, tasks T7, converge L-05 (G-05) |
| L-06 | FR-002 (autenticación); CA-04 parcial (`Access-Accept` sí, `Tunnel-*` informativos) | `spec.md §3 FR-002/FR-005`, `§6 CA-04`, tasks T7, converge L-06 (CT-06 diferida) |
| L-07 | CA-05, FR-003 | `spec.md §3 FR-003`, `§6 CA-05`, tasks T7, converge L-07 |
| NR-01/NR-02 | FR-001, NFR-03, FR-007/CA-06 | `spec.md §3 FR-001/FR-007`, `§4 NFR-03`, `§5 fuera de alcance`, tasks T1 |

CA-07 (`radtest` con usuario solo-LDAP y VLAN por grupo) NO se ejecuta en it.1: requiere CT-03…CT-08 y
P-04 authentik (Provider + Outpost + bind de servicio con `ldapsearch` que responda `ou=users`/`ou=groups`)
según `converge.md §2 CT-08` y `§5 criterio segundo`. Intentar CA-07 en el lift es FAIL de proceso aunque
el comando salga 0 contra un mock (prohibido por D-05).

## Apéndice B — Orden de ejecución y bitácora mínima por gate

Orden: P-00 → L-01 → L-02.1 → L-02.2 → L-03 → L-04 (cronometrado) → L-05 → L-06.1 → L-06.2 → L-07 →
NR-01 → NR-02. Cada gate guarda en bitácora: comando exacto ejecutado, código de salida, salida completa
o filtrada según el gate, hora, valor de `MYSQL_HEALTH_START_PERIOD` efectivo, tag de imagen usado
(`3.2.10` o fallback `3.2.8`), usuario de L-06 (sin clave) y `Tunnel-Private-Group-Id` observado. Sin
Docker en este entorno, este plan queda pendiente de ejecución en host: ningún gate se marca `[x]` aquí.
