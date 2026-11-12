-- Date dimension shared by DOT 311 service requests
-- and DOB NOW job filings

-- Build initial CTEs for staging model references
WITH stg_311 AS (
    SELECT *
    FROM {{ ref('stg_nyc_311_dot') }}
),

stg_dob AS (
    SELECT *
    FROM {{ ref('stg_nyc_dob_job_filings') }}
),

-- Collect dates from both staging tables
all_dates AS (

    -- NYC 311 service requests: created date
    SELECT DISTINCT
        DATE(created_date) AS full_date
    FROM stg_311
    WHERE created_date IS NOT NULL

    UNION DISTINCT

    -- NYC 311 service requests: closed date
    SELECT DISTINCT
        DATE(closed_date) AS full_date
    FROM stg_311
    WHERE closed_date IS NOT NULL

    UNION DISTINCT

    -- DOB NOW job filings: filing date
    SELECT DISTINCT
        DATE(filing_date) AS full_date
    FROM stg_dob
    WHERE filing_date IS NOT NULL

),

-- Date dimension with NYC fiscal year
-- NYC fiscal year runs from July 1 to June 30
date_dimension AS (

    SELECT
        {{ dbt_utils.generate_surrogate_key([
            'full_date'
        ]) }} AS date_key,

        full_date,

        EXTRACT(YEAR FROM full_date) AS year,
        EXTRACT(QUARTER FROM full_date) AS quarter,
        EXTRACT(MONTH FROM full_date) AS month,
        FORMAT_DATE('%B', full_date) AS month_name,
        EXTRACT(DAY FROM full_date) AS day_of_month,
        EXTRACT(DAYOFWEEK FROM full_date) AS day_of_week,
        FORMAT_DATE('%A', full_date) AS weekday_name,

        EXTRACT(DAYOFWEEK FROM full_date)
            IN (1, 7) AS is_weekend,

        CASE
            WHEN EXTRACT(MONTH FROM full_date) >= 7
                THEN EXTRACT(YEAR FROM full_date) + 1
            ELSE EXTRACT(YEAR FROM full_date)
        END AS fiscal_year

    FROM all_dates
    WHERE full_date IS NOT NULL

),

-- Null placeholder row to handle missing dates
-- Future fact tables can use this key for NULL dates
null_placeholder AS (

    SELECT
        '-1' AS date_key,
        CAST(NULL AS DATE) AS full_date,
        CAST(NULL AS INT64) AS year,
        CAST(NULL AS INT64) AS quarter,
        CAST(NULL AS INT64) AS month,
        CAST(NULL AS STRING) AS month_name,
        CAST(NULL AS INT64) AS day_of_month,
        CAST(NULL AS INT64) AS day_of_week,
        CAST(NULL AS STRING) AS weekday_name,
        CAST(NULL AS BOOLEAN) AS is_weekend,
        CAST(NULL AS INT64) AS fiscal_year

)

SELECT * FROM date_dimension

UNION ALL

SELECT * FROM null_placeholder

