# NOAA Storms Pipeline

A one-command pipeline that downloads a year of NOAA Storm Events data, converts it to GeoParquet, and lands it ready for analysis in DuckDB, GeoPandas, or QGIS.

## What it does

`pipeline.sh` takes one or more years, finds the matching raw `details` file(s) in NOAA's public archive, downloads and decompresses them, and converts each to its own GeoParquet file at `data/processed/storms_{YEAR}.parquet`.

The script doesn't hardcode NOAA's file names. It fetches NOAA's live file index each run and reads the real filename off of it, since the "created date" portion of the name changes whenever NOAA reprocesses a year. If you ask for several years in one run, each one is downloaded and converted independently — one bad or missing year won't stop the others from finishing.

Progress is shown as it runs: a download progress bar for each file, and an overall progress bar (`[####------] 40% (2/5 years)`) when processing multiple years.

Re-running the script is safe and cheap. Each year's compressed download is kept in `data/raw/` so it's never fetched twice, while the much larger decompressed CSV is deleted right after a successful conversion — so a re-run skips the slow network step but still redoes the (fast, local) decompress and convert.

Total runtime: about 90 seconds per year on a home internet connection.

## The data

- **Source:** [NOAA Storm Events Database](https://www.ncei.noaa.gov/data/storm-events/)
- **License:** Public domain (US federal data)
- **What's in it:** every recorded storm event in the United States for the given year, including type, location, and damages

## How to run it

Requires GDAL (for `ogr2ogr`) and standard Unix utilities (`curl`, `gunzip`).

```bash
git clone https://github.com/burlesongis/noaa-storms-pipeline.git
cd noaa-storms-pipeline
chmod +x pipeline.sh
./pipeline.sh
```

With no arguments, it processes the most recent year available in NOAA's index.

To run for a specific year:

```bash
./pipeline.sh 2023
```

To run for several years at once:

```bash
./pipeline.sh 2021 2022 2023
```

## What I learned

[Two or three sentences. Be specific. What was harder than expected? What would you do differently? This is the part hiring managers actually read.]

## Stack

- bash
- curl
- GDAL / ogr2ogr
- GeoParquet
