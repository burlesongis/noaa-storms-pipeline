#!/usr/bin/env bash
#
# pipeline.sh — Discover, download, and convert one or more years of NOAA
# Storm Events "details" data to GeoParquet.
#
# Usage:   ./pipeline.sh [YEAR ...]
# Example: ./pipeline.sh 2023
#          ./pipeline.sh 2021 2022 2023
#
# If no YEAR is given, the script uses the most recent year present in
# NOAA's live file index.
#
# Requires: bash, curl, gunzip, ogr2ogr (GDAL >= 3.5)
#
# NOAA's file index (INDEX_URL below) lists "details" files named like:
#   StormEvents_details-ftp_v1.0_d{YEAR}_c{CREATEDDATE}.csv.gz
# The d{YEAR} segment is the data year and is what we match against each
# requested year. The c{CREATEDDATE} segment is just NOAA's publish/compile
# date for that file and changes unpredictably whenever NOAA reprocesses a
# year — it is never hardcoded here. Instead we fetch the live index once
# and read the real filenames off of it. If more than one file matches a
# year (e.g. mid-reprocessing), we take the one with the latest c-date and
# say so. Each requested year is downloaded and converted independently, so
# one bad year doesn't stop the others from finishing.

set -uo pipefail

INDEX_URL="https://www.ncei.noaa.gov/pub/data/swdi/stormevents/csvfiles/"

RAW_DIR="data/raw"
PROCESSED_DIR="data/processed"

mkdir -p "${RAW_DIR}" "${PROCESSED_DIR}"

# -----------------------------------------------------------------------------
# Fetch the file index once and pull out every "details" filename
# (Apache-style autoindex — each filename appears in an <a href="...">
# anchor; sort -u because it also appears once as the link text).
# -----------------------------------------------------------------------------

echo "Fetching file index from ${INDEX_URL}"
INDEX_HTML="$(curl -sL --fail "${INDEX_URL}")"
if [[ $? -ne 0 || -z "${INDEX_HTML}" ]]; then
  echo "ERROR: could not reach ${INDEX_URL}" >&2
  exit 1
fi

DETAILS_FILES=()
while IFS= read -r line; do
  [[ -n "$line" ]] && DETAILS_FILES+=("$line")
done < <(grep -oE 'StormEvents_details-ftp_v1\.0_d[0-9]{4}_c[0-9]{8}\.csv\.gz' <<< "${INDEX_HTML}" | sort -u)

if [[ ${#DETAILS_FILES[@]} -eq 0 ]]; then
  echo "ERROR: could not find any StormEvents_details files at ${INDEX_URL}" >&2
  echo "NOAA may have changed their file naming or page structure — check the URL by hand." >&2
  exit 1
fi

# -----------------------------------------------------------------------------
# Build the list of years to process: every argument passed in, or (if none)
# just the most recent year available in the index.
# -----------------------------------------------------------------------------

if [[ $# -gt 0 ]]; then
  YEARS=("$@")
else
  LATEST_YEAR="$(printf '%s\n' "${DETAILS_FILES[@]}" | grep -oE '_d[0-9]{4}_' | grep -oE '[0-9]{4}' | sort -n | tail -1)"
  YEARS=("${LATEST_YEAR}")
  echo "No year given — using most recent available year: ${LATEST_YEAR}"
fi

echo "Years requested: ${YEARS[*]}"

# -----------------------------------------------------------------------------
# Draw a simple overall progress bar across however many years were
# requested, e.g.: Overall progress: [########------------] 40% (2/5 years)
# -----------------------------------------------------------------------------

draw_progress_bar() {
  local current="$1"
  local total="$2"
  local width=30
  local filled=$(( current * width / total ))
  local empty=$(( width - filled ))
  local bar=""
  local i
  for (( i = 0; i < filled; i++ )); do bar+="#"; done
  for (( i = 0; i < empty; i++ )); do bar+="-"; done
  local pct=$(( current * 100 / total ))
  printf 'Overall progress: [%s] %3d%% (%d/%d years)\n' "$bar" "$pct" "$current" "$total"
}

# -----------------------------------------------------------------------------
# Process one year: find its file in the index, download, decompress,
# convert to GeoParquet. Returns non-zero (instead of exiting the whole
# script) if this particular year can't be completed, so a bad year in a
# multi-year request doesn't stop the rest.
# -----------------------------------------------------------------------------

process_year() {
  local YEAR="$1"

  local MATCHES=()
  local f
  for f in "${DETAILS_FILES[@]}"; do
    if [[ "$f" == *"_d${YEAR}_"* ]]; then
      MATCHES+=("$f")
    fi
  done

  if [[ ${#MATCHES[@]} -eq 0 ]]; then
    echo "  [${YEAR}] ERROR: no StormEvents_details file found for this year" >&2
    return 1
  fi

  # For a single year, every match shares the identical prefix through
  # "_c", so a plain lexicographic sort of the full filename also sorts by
  # creation date — the last one is the most recently created.
  local FILE_NAME
  FILE_NAME="$(printf '%s\n' "${MATCHES[@]}" | sort | tail -1)"
  if [[ ${#MATCHES[@]} -gt 1 ]]; then
    echo "  [${YEAR}] multiple files found; using the most recently created: ${FILE_NAME}"
  else
    echo "  [${YEAR}] found: ${FILE_NAME}"
  fi

  local URL="${INDEX_URL}${FILE_NAME}"
  local RAW_GZ="${RAW_DIR}/${FILE_NAME}"
  local RAW_CSV="${RAW_DIR}/${FILE_NAME%.gz}"
  local OUT_PARQUET="${PROCESSED_DIR}/storms_${YEAR}.parquet"

  echo "  [${YEAR}] downloading ${FILE_NAME}"
  if [[ -f "${RAW_GZ}" ]]; then
    echo "  [${YEAR}] ${RAW_GZ} already exists, skipping download"
  else
    # --progress-bar draws a clean "######--- " bar instead of curl's
    # default stats table.
    if ! curl -L --fail --progress-bar -o "${RAW_GZ}" "${URL}"; then
      echo "  [${YEAR}] ERROR: download failed" >&2
      return 1
    fi
  fi

  echo "  [${YEAR}] decompressing"
  if [[ -f "${RAW_CSV}" ]]; then
    echo "  [${YEAR}] ${RAW_CSV} already exists, skipping decompression"
  else
    if ! gunzip -k "${RAW_GZ}"; then
      echo "  [${YEAR}] ERROR: decompression failed" >&2
      return 1
    fi
  fi

  echo "  [${YEAR}] converting to GeoParquet"
  if ! ogr2ogr \
    -overwrite \
    -f Parquet \
    "${OUT_PARQUET}" \
    "${RAW_CSV}" \
    -oo X_POSSIBLE_NAMES=BEGIN_LON \
    -oo Y_POSSIBLE_NAMES=BEGIN_LAT \
    -a_srs EPSG:4326; then
    echo "  [${YEAR}] ERROR: GeoParquet conversion failed" >&2
    return 1
  fi

  # Cleanup: the decompressed CSV is only an intermediate step (and is
  # typically much larger than either the .gz or the final .parquet), so
  # once the conversion has succeeded it's safe to remove. The compressed
  # .gz is kept so a re-run for this year skips the network download.
  echo "  [${YEAR}] cleaning up intermediate CSV"
  rm -f "${RAW_CSV}"

  echo "  [${YEAR}] done -> ${OUT_PARQUET}"
  return 0
}

# -----------------------------------------------------------------------------
# Run every requested year, tracking which ones failed.
# -----------------------------------------------------------------------------

FAILED_YEARS=()
TOTAL_YEARS=${#YEARS[@]}
COMPLETED=0
for YEAR in "${YEARS[@]}"; do
  echo ""
  echo "=== Processing ${YEAR} ==="
  if ! process_year "${YEAR}"; then
    FAILED_YEARS+=("${YEAR}")
  fi
  COMPLETED=$(( COMPLETED + 1 ))
  draw_progress_bar "${COMPLETED}" "${TOTAL_YEARS}"
done

echo ""
if [[ ${#FAILED_YEARS[@]} -eq 0 ]]; then
  echo "All requested years completed successfully."
  echo "Open the results in DuckDB, e.g.:"
  echo "  duckdb -c \"INSTALL spatial; LOAD spatial; SELECT COUNT(*) FROM read_parquet('${PROCESSED_DIR}/storms_*.parquet');\""
  exit 0
else
  echo "Completed with errors. Failed years: ${FAILED_YEARS[*]}" >&2
  exit 1
fi
