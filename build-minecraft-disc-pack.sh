#!/usr/bin/env bash
# Interaktives Menü: CDs einem Pack zuordnen, bestehendes Pack erweitern.
set -euo pipefail

if [[ -z "${BASH_VERSINFO:-}" || "${BASH_VERSINFO[0]}" -lt 4 ]]; then
  echo "Bitte mit bash starten:  bash $0" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")" && pwd)"
PACK_FORMAT="${PACK_FORMAT:-34}"
PACK_DESC="${PACK_DESC:-Custom Jukebox Musik}"
PACK_NAME="${PACK_NAME:-custom-discs}"
OUT_DIR="${OUT_DIR:-$SCRIPT_DIR}"
MUSIC_DIR="${MUSIC_DIR:-$SCRIPT_DIR}"
LOADED_PACK=""

DISCS=(
  13 cat blocks chirp far mall mellohi stal strad ward 11 wait
  otherside pigstep 5 relic precipice creator creator_music_box
  tears lava_chicken
)

declare -A MAP=()
PICKED=""
PICKED_FILE=""
MUSIC_FILES=()
CACHE="$(mktemp -d)"
trap 'rm -rf "$CACHE"' EXIT

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Fehler: '$1' fehlt. Installieren, z. B.: sudo apt install $1" >&2
    exit 1
  }
}

pause() {
  echo
  read -r -p "Enter zum Fortfahren..." _
}

is_known_disc() {
  local x
  for x in "${DISCS[@]}"; do
    [[ "$x" == "$1" ]] && return 0
  done
  return 1
}

list_assignments() {
  if [[ ${#MAP[@]} -eq 0 ]]; then
    echo "  (noch keine CDs zugeordnet)"
    return
  fi
  local d
  for d in "${DISCS[@]}"; do
    if [[ -n "${MAP[$d]+x}" ]]; then
      echo "  [$d]  ->  ${MAP[$d]}"
    fi
  done
}

pick_disc() {
  PICKED=""
  echo
  echo "Welche CD ersetzen?"
  local i=1 d mark
  for d in "${DISCS[@]}"; do
    mark=" "
    [[ -n "${MAP[$d]+x}" ]] && mark="*"
    printf "  %2d) [%s] %s\n" "$i" "$mark" "$d"
    i=$((i + 1))
  done
  echo
  local choice
  read -r -p "Nummer oder Name: " choice
  [[ -n "${choice:-}" ]] || return 1

  if [[ "$choice" =~ ^[0-9]+$ ]]; then
    local idx=$((choice - 1))
    if (( idx < 0 || idx >= ${#DISCS[@]} )); then
      echo "Ungültige Nummer."
      return 1
    fi
    PICKED="${DISCS[$idx]}"
    return 0
  fi

  choice="$(echo "$choice" | tr '[:upper:]' '[:lower:]' | tr ' ' '_')"
  local x
  for x in "${DISCS[@]}"; do
    if [[ "$x" == "$choice" ]]; then
      PICKED="$x"
      return 0
    fi
  done
  echo "Unbekannte CD: $choice"
  return 1
}

clean_path() {
  local src="$1"
  src="${src#\'}"; src="${src%\'}"
  src="${src#\"}"; src="${src%\"}"
  src="${src#file://}"
  printf '%s' "$src"
}

abs_path() {
  readlink -f "$1" 2>/dev/null || realpath "$1" 2>/dev/null || printf '%s' "$1"
}

collect_music_files() {
  MUSIC_FILES=()
  local f
  while IFS= read -r -d '' f; do
    MUSIC_FILES+=("$f")
  done < <(find "$MUSIC_DIR" -maxdepth 1 -type f \( \
      -iname '*.mp3' -o -iname '*.ogg' -o -iname '*.wav' \
      -o -iname '*.flac' -o -iname '*.m4a' \
    \) -print0 | sort -z)
}

pick_music_file() {
  PICKED_FILE=""
  collect_music_files
  echo
  echo "Musik im Script-Ordner:"
  echo "  $MUSIC_DIR"
  echo

  if [[ ${#MUSIC_FILES[@]} -eq 0 ]]; then
    echo "Keine MP3/OGG/WAV/FLAC/M4A in diesem Ordner."
    echo "Datei hier ablegen oder Pfad eingeben."
  else
    local i=1 f
    for f in "${MUSIC_FILES[@]}"; do
      printf "  %2d) %s\n" "$i" "$(basename "$f")"
      i=$((i + 1))
    done
  fi

  echo
  echo "  0) Anderen Pfad eingeben"
  echo
  local choice
  read -r -p "Nummer oder Pfad: " choice
  [[ -n "${choice:-}" ]] || return 1

  if [[ "$choice" == "0" ]]; then
    local src
    read -r -e -p "Datei: " src
    src="$(clean_path "$src")"
    [[ -f "$src" ]] || { echo "Datei nicht gefunden: $src"; return 1; }
    PICKED_FILE="$(abs_path "$src")"
    return 0
  fi

  if [[ "$choice" =~ ^[0-9]+$ ]]; then
    local idx=$((choice - 1))
    if (( idx < 0 || idx >= ${#MUSIC_FILES[@]} )); then
      echo "Ungültige Nummer."
      return 1
    fi
    PICKED_FILE="${MUSIC_FILES[$idx]}"
    return 0
  fi

  choice="$(clean_path "$choice")"
  if [[ -f "$choice" ]]; then
    PICKED_FILE="$(abs_path "$choice")"
    return 0
  fi
  if [[ -f "$MUSIC_DIR/$choice" ]]; then
    PICKED_FILE="$(abs_path "$MUSIC_DIR/$choice")"
    return 0
  fi
  echo "Datei nicht gefunden: $choice"
  return 1
}

add_or_change() {
  pick_disc || { pause; return 0; }
  local disc="$PICKED"
  echo
  echo "Ausgewählte CD: $disc"
  [[ -n "${MAP[$disc]+x}" ]] && echo "Aktuell: ${MAP[$disc]}"
  pick_music_file || { pause; return 0; }

  MAP["$disc"]="$PICKED_FILE"
  echo "OK: $disc  <-  ${MAP[$disc]}"
  pause
}

remove_one() {
  if [[ ${#MAP[@]} -eq 0 ]]; then
    echo "Nichts zum Entfernen."
    pause
    return 0
  fi
  echo
  echo "Aktuelle Zuordnungen:"
  list_assignments
  pick_disc || { pause; return 0; }
  if [[ -n "${MAP[$PICKED]+x}" ]]; then
    unset "MAP[$PICKED]"
    echo "Entfernt: $PICKED"
  else
    echo "Für $PICKED war nichts gesetzt."
  fi
  pause
}

clear_all() {
  MAP=()
  LOADED_PACK=""
  rm -rf "$CACHE"
  CACHE="$(mktemp -d)"
  echo "Alle Zuordnungen gelöscht."
  pause
}

set_pack_options() {
  local v
  echo
  read -r -e -p "Pack-Name [${PACK_NAME}]: " v
  [[ -n "${v:-}" ]] && PACK_NAME="$v"
  read -r -e -p "Ausgabeordner [${OUT_DIR}]: " v
  [[ -n "${v:-}" ]] && OUT_DIR="$v"
  read -r -e -p "Musikordner [${MUSIC_DIR}]: " v
  [[ -n "${v:-}" ]] && MUSIC_DIR="$v"
  read -r -e -p "pack_format [${PACK_FORMAT}]: " v
  [[ -n "${v:-}" ]] && PACK_FORMAT="$v"
  read -r -e -p "Beschreibung [${PACK_DESC}]: " v
  [[ -n "${v:-}" ]] && PACK_DESC="$v"
  echo "Gespeichert."
  pause
}

import_ogg_file() {
  local file="$1"
  local base name disc dest
  base="$(basename "$file")"
  name="${base%.ogg}"
  name="${name%.OGG}"
  disc="$(echo "$name" | tr '[:upper:]' '[:lower:]')"

  if ! is_known_disc "$disc"; then
    echo "  übersprungen (unbekannter Name): $base"
    return 0
  fi

  mkdir -p "$CACHE/imported"
  dest="$CACHE/imported/${disc}.ogg"
  cp -f "$file" "$dest"
  MAP["$disc"]="$dest"
  echo "  geladen: $disc"
}

load_existing_pack() {
  need_cmd unzip
  echo
  echo "Packs im Script-Ordner:"
  echo "  $SCRIPT_DIR"
  echo
  local zips=() z i=1
  while IFS= read -r -d '' z; do
    zips+=("$z")
  done < <(find "$SCRIPT_DIR" -maxdepth 1 -type f -iname '*.zip' -print0 | sort -z)

  if [[ ${#zips[@]} -eq 0 ]]; then
    echo "  (keine ZIP gefunden)"
  else
    for z in "${zips[@]}"; do
      printf "  %2d) %s\n" "$i" "$(basename "$z")"
      i=$((i + 1))
    done
  fi
  echo
  echo "  0) Anderen Pfad eingeben"
  echo
  local choice src
  read -r -p "Nummer oder Pfad: " choice
  if [[ "$choice" == "0" || -z "${choice:-}" ]]; then
    read -r -e -p "Pack: " src
  elif [[ "$choice" =~ ^[0-9]+$ ]]; then
    local idx=$((choice - 1))
    if (( idx < 0 || idx >= ${#zips[@]} )); then
      echo "Ungültige Nummer."
      pause
      return 0
    fi
    src="${zips[$idx]}"
  else
    src="$choice"
  fi
  src="$(clean_path "$src")"
  if [[ -f "$SCRIPT_DIR/$src" && ! -e "$src" ]]; then
    src="$SCRIPT_DIR/$src"
  fi

  if [[ ! -e "$src" ]]; then
    echo "Nicht gefunden: $src"
    pause
    return 0
  fi

  src="$(abs_path "$src")"
  local tmp found=0
  tmp="$(mktemp -d)"

  if [[ -f "$src" ]]; then
    echo "Entpacke ZIP..."
    if ! unzip -q "$src" -d "$tmp"; then
      echo "ZIP konnte nicht gelesen werden."
      rm -rf "$tmp"
      pause
      return 0
    fi
    local base
    base="$(basename "$src")"
    PACK_NAME="${base%.zip}"
    LOADED_PACK="$src"
  elif [[ -d "$src" ]]; then
    cp -a "$src/." "$tmp/"
    LOADED_PACK="$src"
    PACK_NAME="$(basename "$src")"
  else
    echo "Weder Datei noch Ordner: $src"
    rm -rf "$tmp"
    pause
    return 0
  fi

  local meta
  meta="$(find "$tmp" -name pack.mcmeta -print -quit 2>/dev/null || true)"
  if [[ -n "$meta" && -f "$meta" ]]; then
    local fmt
    fmt="$(sed -n 's/.*"pack_format"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$meta" | head -n1)"
    [[ -n "$fmt" ]] && PACK_FORMAT="$fmt"
    local desc
    desc="$(sed -n 's/.*"description"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$meta" | head -n1)"
    [[ -n "$desc" ]] && PACK_DESC="$desc"
  fi

  echo "Gefundene CDs:"
  local f
  while IFS= read -r -d '' f; do
    import_ogg_file "$f"
    found=$((found + 1))
  done < <(find "$tmp" -type f -iname '*.ogg' -print0)

  rm -rf "$tmp"

  if [[ "$found" -eq 0 ]]; then
    echo "Keine .ogg-Dateien im Pack gefunden."
    echo "Erwarteter Pfad: assets/minecraft/sounds/records/<cd>.ogg"
  else
    echo
    echo "$found Datei(en) übernommen. Du kannst jetzt weitere CDs mit Punkt 1 hinzufügen."
    echo "Geladen aus: $LOADED_PACK"
  fi
  pause
}

hash_file() {
  local f="$1"
  if command -v sha1sum >/dev/null 2>&1; then
    sha1sum "$f" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 1 "$f" | awk '{print $1}'
  else
    echo ""
  fi
}

write_sounds_json() {
  local out="$1"
  local first=1 d
  {
    echo "{"
    for d in "${DISCS[@]}"; do
      [[ -n "${MAP[$d]+x}" ]] || continue
      if [[ $first -eq 0 ]]; then
        echo ","
      fi
      first=0
      cat <<EOF
  "music_disc.${d}": {
    "sounds": [
      { "name": "records/${d}", "stream": true }
    ]
  }
EOF
    done
    echo
    echo "}"
  } > "$out"
}

place_audio() {
  local src="$1"
  local dest="$2"
  local ext
  ext="$(echo "${src##*.}" | tr '[:upper:]' '[:lower:]')"

  if [[ "$ext" == "ogg" ]]; then
    cp -f "$src" "$dest"
    return 0
  fi

  ffmpeg -y -hide_banner -loglevel error \
    -i "$src" \
    -vn -c:a libvorbis -q:a 5 -ar 44100 \
    "$dest"
}

build_pack() {
  if [[ ${#MAP[@]} -eq 0 ]]; then
    echo "Keine CDs zugeordnet. Erst Punkt 1 oder 6 benutzen."
    pause
    return 0
  fi

  need_cmd ffmpeg
  need_cmd zip

  mkdir -p "$OUT_DIR"
  OUT_DIR="$(cd "$OUT_DIR" && pwd)"

  local work records zip_path dest src d count
  work="$(mktemp -d)"
  records="$work/assets/minecraft/sounds/records"
  mkdir -p "$records"

  cat > "$work/pack.mcmeta" <<EOF
{
  "pack": {
    "pack_format": ${PACK_FORMAT},
    "description": "${PACK_DESC}"
  }
}
EOF

  write_sounds_json "$work/assets/minecraft/sounds.json"

  echo
  echo "Bereite Audiodateien vor..."
  count=0
  for d in "${DISCS[@]}"; do
    [[ -n "${MAP[$d]+x}" ]] || continue
    src="${MAP[$d]}"
    dest="$records/${d}.ogg"

    if [[ ! -f "$src" ]]; then
      echo "FEHLER: Quelldatei fehlt: $src"
      rm -rf "$work"
      pause
      return 0
    fi

    echo "  $d  <=  $src"
    if ! place_audio "$src" "$dest"; then
      echo "FEHLER: konnte $src nicht übernehmen."
      rm -rf "$work"
      pause
      return 0
    fi

    if [[ ! -s "$dest" ]]; then
      echo "FEHLER: $dest ist leer."
      rm -rf "$work"
      pause
      return 0
    fi

    mkdir -p "$CACHE/imported"
    cp -f "$dest" "$CACHE/imported/${d}.ogg"
    MAP["$d"]="$CACHE/imported/${d}.ogg"

    echo "         $(du -h "$dest" | cut -f1)"
    count=$((count + 1))
  done

  if [[ "$count" -eq 0 ]]; then
    echo "FEHLER: Keine OGG-Dateien erzeugt."
    rm -rf "$work"
    pause
    return 0
  fi

  echo
  echo "Dateien im Pack vor dem Zippen:"
  find "$work" -type f -printf "  %P  (%s Bytes)\n"

  zip_path="$OUT_DIR/${PACK_NAME}.zip"
  rm -f "$zip_path"
  (
    cd "$work"
    zip -qr "$zip_path" pack.mcmeta assets
  )
  rm -rf "$work"

  LOADED_PACK="$zip_path"

  echo
  echo "Inhalt der ZIP:"
  unzip -l "$zip_path" || true

  local hash
  hash="$(hash_file "$zip_path")"

  echo
  echo "========================================"
  echo " Pack:  $zip_path"
  echo " Größe: $(du -h "$zip_path" | cut -f1)"
  echo " CDs:   $count"
  list_assignments
  if [[ -n "$hash" ]]; then
    echo
    echo " SHA1: $hash"
    echo
    echo " server.properties:"
    echo "   resource-pack=https://DEINE-URL/${PACK_NAME}.zip"
    echo "   resource-pack-sha1=$hash"
    echo "   require-resource-pack=true"
  fi
  echo "========================================"
  echo
  echo "Die CDs bleiben im Menü geladen."
  echo "Du kannst weitere mit Punkt 1 hinzufügen und erneut Punkt 5 drücken."
  pause
}

show_menu() {
  clear 2>/dev/null || true
  cat <<EOF
========================================
 Minecraft Jukebox-Pack Builder
========================================
 Script:   ${SCRIPT_DIR}
 Pack:     ${PACK_NAME}.zip
 Ziel:     ${OUT_DIR}
 Musik:    ${MUSIC_DIR}
 Format:   pack_format ${PACK_FORMAT}
 Geladen:  ${LOADED_PACK:-neu}
 Zugeordnete CDs: ${#MAP[@]}

EOF
  list_assignments
  cat <<EOF

  1) CD hinzufügen / ändern
  2) CD-Zuordnung entfernen
  3) Alle Zuordnungen löschen
  4) Pack-Name / Ordner / Format
  5) Resource-Pack bauen / speichern
  6) Bestehendes Pack öffnen und erweitern
  0) Beenden

EOF
  local choice
  read -r -p "Auswahl: " choice
  case "$choice" in
    1) add_or_change ;;
    2) remove_one ;;
    3) clear_all ;;
    4) set_pack_options ;;
    5) build_pack ;;
    6) load_existing_pack ;;
    0|q|Q) echo "Tschüss."; exit 0 ;;
    *) echo "Ungültige Auswahl."; pause ;;
  esac
}

if [[ $# -gt 0 ]]; then
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --open)
        LOADED_FROM_CLI="$2"
        shift 2
        ;;
      --disc)
        [[ $# -ge 3 ]] || { echo "--disc braucht NAME und DATEI"; exit 1; }
        MAP["$(echo "$2" | tr '[:upper:]' '[:lower:]')"]="$3"
        shift 3
        ;;
      --name) PACK_NAME="$2"; shift 2 ;;
      --out) OUT_DIR="$2"; shift 2 ;;
      --format) PACK_FORMAT="$2"; shift 2 ;;
      --desc) PACK_DESC="$2"; shift 2 ;;
      -h|--help)
        echo "Menü:  bash $0"
        echo "CLI:   bash $0 --open altes.zip --disc cat lied.mp3"
        exit 0
        ;;
      *)
        echo "Unbekannt: $1"
        exit 1
        ;;
    esac
  done

  if [[ -n "${LOADED_FROM_CLI:-}" ]]; then
    if [[ -f "$LOADED_FROM_CLI" ]]; then
      tmpcli="$(mktemp -d)"
      unzip -q "$LOADED_FROM_CLI" -d "$tmpcli"
      while IFS= read -r -d '' f; do
        import_ogg_file "$f"
      done < <(find "$tmpcli" -type f -iname '*.ogg' -print0)
      rm -rf "$tmpcli"
      PACK_NAME="$(basename "${LOADED_FROM_CLI%.zip}")"
      OUT_DIR="$(dirname "$(abs_path "$LOADED_FROM_CLI")")"
      LOADED_PACK="$(abs_path "$LOADED_FROM_CLI")"
    fi
  fi
  build_pack
  exit 0
fi

while true; do
  show_menu
done
