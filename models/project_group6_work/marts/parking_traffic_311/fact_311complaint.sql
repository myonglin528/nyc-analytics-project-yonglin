
-- Group 6 - Corrected Fact 311 Complaint
-- Grain: one row per unique 311 service request
-- Dimension keys come from upstream dimension tables

WITH stg AS (

    SELECT *
    FROM {{ ref('stg_311_requests') }}

),

complaints AS (

    SELECT *
    FROM {{ ref('dim_complaint_types') }}

),

locations AS (

    SELECT *
    FROM {{ ref('dim_locations') }}

),

agencies AS (

    SELECT *
    FROM {{ ref('dim_agency') }}

),

precincts AS (

    SELECT *
    FROM {{ ref('dim_precinct') }}

),

dates AS (

    SELECT *
    FROM {{ ref('dim_dates') }}

),

times AS (

    SELECT *
    FROM {{ ref('dim_time') }}

),

prepped AS (

    SELECT
        s.*,

        -- Standardize precinct number
        SAFE_CAST(
            TRIM(REPLACE(s.police_precinct, 'Precinct', ''))
            AS INT64
        ) AS precinct_number,

        -- Standardize agency name
        CASE
            WHEN TRIM(s.agency_name) =
                 'New York City Police Department'
                THEN 'POLICE DEPARTMENT'
            ELSE TRIM(s.agency_name)
        END AS standardized_agency_name

    FROM stg s

),

fact_311 AS (

    SELECT

        -- Surrogate primary key
        {{ dbt_utils.generate_surrogate_key([
            's.unique_key'
        ]) }} AS complaint_fact_key,

        -- Request attributes
        s.unique_key,
        s.channel_type,
        s.status AS request_status,
        s.vehicle_type,

        -- Measure: number of days to close a request
        CASE
            WHEN s.closed_date IS NOT NULL
             AND s.closed_date >= s.created_date
            THEN DATE_DIFF(
                DATE(s.closed_date),
                DATE(s.created_date),
                DAY
            )
            ELSE NULL
        END AS days_to_close,

        -- Foreign keys obtained from dimension tables
        COALESCE(c.complaint_type_key, '-1')
            AS complaint_type_key,

        COALESCE(l.location_key, '-1')
            AS location_key,

        COALESCE(a.agency_key, '-1')
            AS agency_key,

        COALESCE(p.precinct_key, '-1')
            AS precinct_key,

        COALESCE(cd.date_key, '-1')
            AS created_date_key,

        COALESCE(cld.date_key, '-1')
            AS closed_date_key,

        COALESCE(t.time_key, '-1')
            AS created_time_key

    FROM prepped s

    -- Complaint type dimension
    LEFT JOIN complaints c
        ON s.complaint_type = c.complaint_type
       AND s.descriptor IS NOT DISTINCT FROM c.descriptor

    -- Location dimension: single equality comparison
    LEFT JOIN locations l
        ON TO_JSON_STRING(STRUCT(
            s.location_type,
            s.incident_address,
            s.incident_zip,
            s.street_name,
            s.city,
            s.borough
        )) = TO_JSON_STRING(STRUCT(
            l.location_type,
            l.incident_address,
            l.incident_zip,
            l.street_name,
            l.city,
            l.borough
        ))

    -- Agency dimension
    LEFT JOIN agencies a
        ON s.standardized_agency_name = a.agency_name

    -- Precinct dimension
    LEFT JOIN precincts p
        ON s.borough = p.borough
       AND s.precinct_number = p.police_precinct

    -- Date dimension: created date
    LEFT JOIN dates cd
        ON DATE(s.created_date) = cd.full_date

    -- Date dimension: closed date
    LEFT JOIN dates cld
        ON DATE(s.closed_date) = cld.full_date

    -- Time dimension
    LEFT JOIN times t
        ON EXTRACT(HOUR FROM s.created_date) = t.hour

)

SELECT *
FROM fact_311
