#!/usr/bin/env bash
# Pruebas de humo contra un despliegue real del microservicio.
#   sin flags : solo lecturas (health, home, listado, OpenAPI) -> se usa en produccion
#   --crud    : ademas crea, consulta, actualiza y elimina un vehiculo de prueba -> staging
#
# Uso: scripts/smoke-test.sh <BASE_URL> [--crud]
set -euo pipefail

BASE_URL="${1:?Uso: smoke-test.sh <BASE_URL> [--crud]}"
BASE_URL="${BASE_URL%/}"
MODO="${2:-}"
API="$BASE_URL/api/v1/vehiculos"
CUERPO="$(mktemp)"
trap 'rm -f "$CUERPO"' EXIT

fallar() { echo "❌ $*" >&2; exit 1; }

# verificar <descripcion> <codigo HTTP esperado> <argumentos de curl...>
verificar() {
  local descripcion="$1" esperado="$2"
  shift 2
  local codigo
  codigo="$(curl -sS -o "$CUERPO" -w '%{http_code}' --max-time 15 "$@" || true)"
  if [[ "$codigo" != "$esperado" ]]; then
    echo "Respuesta recibida:" >&2
    cat "$CUERPO" >&2 || true
    echo >&2
    fallar "$descripcion: se esperaba HTTP $esperado y se obtuvo ${codigo:-sin respuesta}"
  fi
  echo "✅ $descripcion (HTTP $codigo)"
}

echo "Esperando a que $BASE_URL responda..."
for intento in $(seq 1 30); do
  if curl -fsS --max-time 5 "$BASE_URL/actuator/health/readiness" >/dev/null 2>&1; then
    break
  fi
  if [[ "$intento" -eq 30 ]]; then
    fallar "La aplicacion no respondio despues de ${SECONDS} s"
  fi
  sleep 5
done

verificar "Health readiness (app + base de datos)" 200 "$BASE_URL/actuator/health/readiness"
verificar "Health liveness" 200 "$BASE_URL/actuator/health/liveness"
verificar "Home de la API" 200 "$BASE_URL/"
verificar "Listar vehiculos" 200 "$API"
verificar "Documentacion OpenAPI" 200 "$BASE_URL/v3/api-docs"

if [[ "$MODO" == "--crud" ]]; then
  PATENTE="SMK$((RANDOM % 900 + 100))"
  JSON="{\"patente\":\"$PATENTE\",\"marca\":\"Toyota\",\"modelo\":\"Yaris\",\"anio\":2022,\"color\":\"Rojo\",\"tipo\":\"Sedan\",\"disponible\":true}"
  CT="Content-Type: application/json"

  verificar "Crear vehiculo $PATENTE" 201 -X POST -H "$CT" -d "$JSON" "$API"
  ID="$(grep -oE '"id":[0-9]+' "$CUERPO" | head -1 | cut -d: -f2 || true)"
  [[ -n "$ID" ]] || fallar "La respuesta de creacion no trae el id"

  verificar "Buscar vehiculo por id" 200 "$API/$ID"
  verificar "Rechazar patente duplicada" 409 -X POST -H "$CT" -d "$JSON" "$API"
  verificar "Rechazar datos invalidos" 400 -X POST -H "$CT" -d '{"patente":""}' "$API"
  verificar "Actualizar vehiculo" 200 -X PUT -H "$CT" -d "${JSON/Rojo/Azul}" "$API/$ID"
  grep -q '"color":"Azul"' "$CUERPO" || fallar "La actualizacion no se reflejo en la respuesta"
  verificar "Eliminar vehiculo" 204 -X DELETE "$API/$ID"
  verificar "El vehiculo eliminado ya no existe" 404 "$API/$ID"
fi

echo "🎉 Pruebas de humo OK contra $BASE_URL"
