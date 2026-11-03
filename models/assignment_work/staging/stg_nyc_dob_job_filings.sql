-- Clean and standardize DOB NOW Job Application Filings data
-- One row per job filing number

WITH source AS (
    SELECT * FROM {{ source('raw', 'source_nyc_dob_job_apps') }}
), -- Easier to refer to the dbt source table this way

cleaned AS (
    SELECT
        -- Keep all columns except those transformed below
        * EXCEPT (
            job_filing_number,
            filing_date,
            filing_status,
            job_type,
            house_no,
            street_name,
            borough,
            postcode,
            zip,
            council_district,
            block,
            lot,
            bin,
            latitude,
            longitude
        ),

        -- Identifiers
        TRIM(CAST(job_filing_number AS STRING)) AS job_filing_number,

        -- Date/Time
        SAFE_CAST(filing_date AS TIMESTAMP) AS filing_date,

        -- Job details
        UPPER(TRIM(CAST(filing_status AS STRING))) AS filing_status,
        CAST(job_type AS STRING) AS job_type,

        -- Location - clean ZIP code
        CASE
            WHEN UPPER(TRIM(CAST(postcode AS STRING)))
                IN ('N/A', 'NA') THEN NULL
            WHEN UPPER(TRIM(CAST(postcode AS STRING)))
                = 'ANONYMOUS' THEN 'Anonymous'
            WHEN REGEXP_CONTAINS(
                TRIM(CAST(postcode AS STRING)),
                r'^\d{5}$'
            ) THEN TRIM(CAST(postcode AS STRING))
            WHEN REGEXP_CONTAINS(
                TRIM(CAST(postcode AS STRING)),
                r'^\d{9}$'
            ) THEN TRIM(CAST(postcode AS STRING))
            WHEN REGEXP_CONTAINS(
                TRIM(CAST(postcode AS STRING)),
                r'^\d{5}-\d{4}$'
            ) THEN TRIM(CAST(postcode AS STRING))
            ELSE NULL
        END AS zip,

        -- Location - standardized borough
        CASE
            WHEN UPPER(TRIM(CAST(borough AS STRING)))
                IN ('MANHATTAN', 'NEW YORK COUNTY')
                THEN 'Manhattan'
            WHEN UPPER(TRIM(CAST(borough AS STRING)))
                IN ('BRONX', 'THE BRONX')
                THEN 'Bronx'
            WHEN UPPER(TRIM(CAST(borough AS STRING)))
                IN ('BROOKLYN', 'KINGS COUNTY')
                THEN 'Brooklyn'
            WHEN UPPER(TRIM(CAST(borough AS STRING)))
                IN ('QUEENS', 'QUEEN', 'QUEENS COUNTY')
                THEN 'Queens'
            WHEN UPPER(TRIM(CAST(borough AS STRING)))
                IN ('STATEN ISLAND', 'RICHMOND COUNTY')
                THEN 'Staten Island'
            ELSE 'UNKNOWN or CITYWIDE'
        END AS borough,

        CAST(council_district AS STRING) AS council_district,

        -- Address
        CAST(house_no AS STRING) AS house_no,
        CAST(street_name AS STRING) AS street_name,

        -- Property details
        CAST(block AS STRING) AS block,
        CAST(lot AS STRING) AS lot,
        CAST(bin AS STRING) AS bin,

        -- Geographic coordinates
        SAFE_CAST(latitude AS FLOAT64) AS latitude,
        SAFE_CAST(longitude AS FLOAT64) AS longitude,

        -- Metadata
        CURRENT_TIMESTAMP() AS _stg_loaded_at

    FROM source

    -- Filters
    WHERE job_filing_number IS NOT NULL
      AND TRIM(CAST(job_filing_number AS STRING)) != ''
      AND filing_date IS NOT NULL

    -- Deduplicate
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY job_filing_number
        ORDER BY filing_date DESC
    ) = 1
)

SELECT * FROM cleaned
-- All should be part of this table after running:
-- stg_nyc_dob_job_filings