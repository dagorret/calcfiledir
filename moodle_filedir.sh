#!/usr/bin/env bash


# Protejer lo pipes, |, o en castellano las canalizaciones para detectar errores fanstasmas
# Mejor dicho para no producir errores fanstasmas
set -euo pipefail

# Uso: ./analyze_moodle_filedir.sh /ruta/a/moodledata/filedir
# Si no pasás ruta, usa el directorio actual.
DIR="${1:-.}"

if [[ ! -d "$DIR" ]]; then
  echo "ERROR: '$DIR' no es un directorio" >&2
  exit 1
fi

# Dependencias
if ! command -v file >/dev/null 2>&1; then
  echo "ERROR: falta 'file'. Instalalo (Debian/Ubuntu): sudo apt-get install -y file" >&2
  exit 1
fi
if ! command -v stat >/dev/null 2>&1; then
  echo "ERROR: falta 'stat' en PATH." >&2
  exit 1
fi

TS="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$(pwd)"
CSV_SUM="${OUT_DIR}/moodle_filedir_summary_${TS}.csv"
CSV_FULL="${OUT_DIR}/moodle_filedir_full_${TS}.csv"

echo "Analizando: $DIR"
echo "Generando:"
echo " - Resumen por MIME: $CSV_SUM"
echo " - Listado completo: $CSV_FULL"
echo

# Arrays asociativos para conteo y tamaño por MIME
declare -A COUNT_BY_MIME
declare -A SIZE_BY_MIME

TOTAL_FILES=0
TOTAL_BYTES=0

# CSV encabezados
echo "mime_type,count,bytes" > "$CSV_SUM"
echo "path,mime_type,bytes" > "$CSV_FULL"

# Recorre archivos (rapidez + robustez con NUL-terminado)
while IFS= read -r -d '' f; do
  # MIME real por contenido
  mime=$(file --mime-type -b "$f" || echo "application/octet-stream")
  # Tamaño en bytes
  size=$(stat -c %s "$f" 2>/dev/null || echo 0)

  # Acumular
  (( TOTAL_FILES++ )) || true
  (( TOTAL_BYTES+=size )) || true

  # Guardar por MIME
  COUNT_BY_MIME["$mime"]=$(( ${COUNT_BY_MIME["$mime"]:-0} + 1 ))
  SIZE_BY_MIME["$mime"]=$(( ${SIZE_BY_MIME["$mime"]:-0} + size ))

  # CSV de detalle
  # Nota: escapamos comas en la ruta reemplazándolas por '\,'
  safe_path="${f//,/\\,}"
  echo "${safe_path},${mime},${size}" >> "$CSV_FULL"

done < <(find "$DIR" -type f -print0)

# Escribir resumen por MIME
for k in "${!COUNT_BY_MIME[@]}"; do
  echo "${k},${COUNT_BY_MIME[$k]},${SIZE_BY_MIME[$k]}" >> "$CSV_SUM"
done

# Totales (también por du para comparación)
DU_BYTES=$(du -sb "$DIR" | awk '{print $1}')

# Función human-readable
hr() {
  local b=$1 d='' s=0 S=(B KB MB GB TB PB)
  while (( b > 1024 && s < ${#S[@]}-1 )); do
    d="$(printf ".%02d" $(( (b%1024)*100/1024 )) )"
    b=$(( b/1024 ))
    (( s++ ))
  done
  printf "%s%s %s\n" "$b" "${d}" "${S[$s]}"
}

echo "==== RESULTADOS ===="
echo "Directorio analizado : $DIR"
echo "Total de archivos    : $TOTAL_FILES"
echo "Tamaño total (suma)  : $TOTAL_BYTES bytes ($(hr $TOTAL_BYTES))"
echo "Tamaño por 'du -sb'  : $DU_BYTES bytes ($(hr $DU_BYTES))"
echo
echo "Top 10 tipos (por tamaño):"
# Ordenar por tamaño descendente y mostrar top 10
awk -F, 'NR>1{print $1","$2}' "$CSV_SUM" \
| sort -t, -k3,3nr \
| head -n 10 \
| awk -F, '{printf "  - %-30s  archivos:%8d  tamaño:%12d bytes\n",$1,$2,$3}'
echo
echo "Archivos de salida:"
echo "  - $CSV_SUM"
echo "  - $CSV_FULL"
echo "Listo."

