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


The pipeline logic itself wasn't the hardest part — once written, it ran cleanly on the first real attempt against live NOAA data. The bigger challenge was environment setup: getting Miniconda configured to run GDAL with Parquet/Arrow support inside VS Code, and making sure conda was properly initialized for the actual shell I was using (Git Bash), not just any shell.

Beyond that, this project was my first time doing several things from scratch:

Building an automated data pipeline that discovers, downloads, and reprocesses files linked from a live web page — rather than pointing at a fixed, hardcoded URL.
Using regex and shell pattern matching inside a bash script to parse a directory listing and identify the correct file for a given year.
Converting a raw CSV into GeoParquet — a modern, cloud-native spatial format — so the data is ready to use directly in GIS and web-mapping tools like QGIS, DuckDB, or GeoPandas.
Cleaning up the folder so that it deletes the uncompressed file, leaving only compressed data to save storage and prevent the need for re-downloading in the future

Next time, I'd verify a GDAL build actually includes the driver I need before writing code that depends on it, rather than discovering gaps at the very last step.


## Stack

- bash
- curl
- GDAL / ogr2ogr
- GeoParquet
