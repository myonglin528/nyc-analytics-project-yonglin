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

        SAFE_CAST(
            REGEXP_EXTRACT(
                CAST(s.police_precinct AS STRING),
                r'(\d+)'
            ) AS INT64
        ) AS precinct_number,

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

        {{ dbt_utils.generate_surrogate_key([
            's.unique_key'
        ]) }} AS complaint_fact_key,

        s.unique_key,
        s.channel_type,
        s.status AS request_status,
        s.vehicle_type,

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

        -- Keys obtained from dimensions
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

    LEFT JOIN complaints c
        ON s.complaint_type = c.complaint_type
       AND s.descriptor IS NOT DISTINCT FROM c.descriptor

    LEFT JOIN locations l
        ON s.location_type IS NOT DISTINCT FROM l.location_type
       AND s.incident_address IS NOT DISTINCT FROM l.incident_address
       AND s.incident_zip IS NOT DISTINCT FROM l.incident_zip
       AND s.street_name IS NOT DISTINCT FROM l.street_name
       AND s.city IS NOT DISTINCT FROM l.city
       AND s.borough IS NOT DISTINCT FROM l.borough

    LEFT JOIN agencies a
        ON s.standardized_agency_name = a.agency_name

    LEFT JOIN precincts p
        ON s.borough = p.borough
       AND s.precinct_number = p.police_precinct

    LEFT JOIN dates cd
        ON DATE(s.created_date) = cd.full_date

    LEFT JOIN dates cld
        ON DATE(s.closed_date) = cld.full_date

    LEFT JOIN times t
        ON EXTRACT(HOUR FROM s.created_date) = t.hour

)

SELECT *
FROM fact_311