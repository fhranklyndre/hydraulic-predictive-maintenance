--PREDICTIVE MAINTENANCE FOR HYDRAULIC SYSTEM

--1. CREATE TABLE STRUCTURE BEFORE IMPORTING TABLES

CREATE TABLE sensor_telemetry (
    timestamp TEXT,
    machine_id VARCHAR(50),
    pressure_bar DOUBLE PRECISION,
    temp_celsius DOUBLE PRECISION,
    flow_lpm DOUBLE PRECISION,
    vibration_x_g DOUBLE PRECISION,
    vibration_y_g DOUBLE PRECISION,
    pump_rpm DOUBLE PRECISION,
    is_anomaly INTEGER,
    failure_mode VARCHAR(100),
    rul_hours DOUBLE PRECISION,
    is_sensor_dropout INTEGER,
    shift VARCHAR(20),
    day_of_week INTEGER
);

CREATE TABLE maintenance_log (
    maintenance_id VARCHAR(20),
    machine_id VARCHAR(50),
    action_timestamp TEXT,
    action_type VARCHAR(50),
    component_replaced VARCHAR(100),
    technician_id VARCHAR(20),
    cost_usd NUMERIC(12,2)
);

CREATE TABLE failure_labels (
    failure_event_id VARCHAR(20),
    machine_id VARCHAR(50),
    failure_timestamp TEXT,
    failure_mode VARCHAR(100),
    degradation_start_timestamp TEXT,
    repair_cost_usd NUMERIC(12,2),
    downtime_hours DOUBLE PRECISION
);

CREATE TABLE equipment_master (
    machine_id VARCHAR(50),
    installation_date TEXT,
    total_operating_hours DOUBLE PRECISION,
    fluid_type VARCHAR(100),
    last_filter_change_date TEXT,
    maintenance_priority VARCHAR(20)
);
-- we used DOUBLE PRECISION because it is more standard PostgreSQL for decimal sensor measurements.
-- and NUMERIC(12,2) is better for money-related fields like (12 stands for total number of digits allowed & 2 represents number of digits after the decimal point)

--Datasets Preview
SELECT * FROM sensor_telemetry LIMIT 10;
SELECT * FROM maintenance_log LIMIT 10;
SELECT * FROM failure_labels LIMIT 10;
SELECT * FROM equipment_master LIMIT 10;

--check row counts
SELECT COUNT(*) FROM sensor_telemetry;
SELECT COUNT(*) FROM maintenance_log;
SELECT COUNT(*) FROM failure_labels;
SELECT COUNT(*) FROM equipment_master;


--2. DATA CLEANING & QUALITY CHECKS
--missing values
--blank strings
--duplicate rows
--duplicate machine/timestamp combinations
--invalid numeric ranges
--sensor dropout rate
--machines in telemetry but missing in equipment master

--Fix Data Types
-- For sensor_telemetry
ALTER TABLE sensor_telemetry
ADD COLUMN timestamp_clean TIMESTAMP;

UPDATE sensor_telemetry
SET timestamp_clean = TO_TIMESTAMP(timestamp, 'DD/MM/YYYY HH24:MI');

--For maintenance_log
-- Create new timestamp column in the right data format
ALTER TABLE maintenance_log
ADD COLUMN action_timestamp_clean TIMESTAMP;
UPDATE maintenance_log
SET action_timestamp_clean = action_timestamp::timestamp;

--Replace old action_timestamp with cleaned action timestamp
ALTER TABLE maintenance_log
DROP COLUMN action_timestamp;
ALTER TABLE maintenance_log
RENAME COLUMN action_timestamp_clean TO action_timestamp;

--For failure_labels
-- Create new timestamp column in the right data format
ALTER TABLE failure_labels
ADD COLUMN failure_timestamp_clean DATE,
ADD COLUMN degradation_start_date DATE;

UPDATE failure_labels
SET
    failure_timestamp_clean = TO_DATE(failure_timestamp, 'YYYY/MM/DD'),
    degradation_start_date = TO_DATE(degradation_start_timestamp, 'YYYY/MM/DD');
--Replace old action_timestamp with cleaned action timestamp
ALTER TABLE failure_labels
DROP COLUMN failure_timestamp,
DROP COLUMN degradation_start_timestamp;

ALTER TABLE failure_labels
RENAME COLUMN failure_timestamp_clean TO failure_timestamp;

ALTER TABLE failure_labels
RENAME COLUMN degradation_start_date TO degradation_start_timestamp;


--For equipment_master
-- Create new timestamp column in the right data format
ALTER TABLE equipment_master
ADD COLUMN installation_date_clean DATE,
ADD COLUMN last_filter_change_date_clean DATE;

UPDATE equipment_master
SET
    installation_date_clean = TO_DATE(installation_date, 'YYYY/MM/DD'),
    last_filter_change_date_clean = TO_DATE(last_filter_change_date, 'YYYY/MM/DD');
--Replace old action_timestamp with cleaned action timestamp
ALTER TABLE equipment_master
DROP COLUMN installation_date,
DROP COLUMN last_filter_change_date;

ALTER TABLE equipment_master
RENAME COLUMN installation_date_clean TO installation_date;
ALTER TABLE equipment_master
RENAME COLUMN last_filter_change_date_clean TO last_filter_change_date;


--Check for missing values
-- For sensor_telemetry
SELECT
    COUNT(*) AS total_rows,
    COUNT(*) - COUNT(timestamp) AS missing_timestamp,
    COUNT(*) - COUNT(machine_id) AS missing_machine_id,
    COUNT(*) - COUNT(pressure_bar) AS missing_pressure
FROM sensor_telemetry;
--Observation : total_rows are 864000, missing_pressure is 2590
--It is as a result of sensor dropout rather than random data corruption from our 
--Check "if missing values match is_sensor_dropout"
SELECT
    is_sensor_dropout,
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (
        WHERE pressure_bar IS NULL
           OR temp_celsius IS NULL
           OR flow_lpm IS NULL
           OR vibration_x_g IS NULL
           OR vibration_y_g IS NULL
           OR pump_rpm IS NULL
    ) AS rows_with_missing_sensor_values
FROM sensor_telemetry
GROUP BY is_sensor_dropout
ORDER BY is_sensor_dropout;

--for EDA and Power BI purposes, this is clean and safe
CREATE OR REPLACE VIEW sensor_telemetry_clean AS
SELECT *
FROM sensor_telemetry
WHERE pressure_bar IS NOT NULL
  AND temp_celsius IS NOT NULL
  AND flow_lpm IS NOT NULL
  AND vibration_x_g IS NOT NULL
  AND vibration_y_g IS NOT NULL
  AND pump_rpm IS NOT NULL;

--for documenting data quality
--The raw telemetry was preserved, and missing sensor rows were flagged for data-quality monitoring.
CREATE OR REPLACE VIEW sensor_telemetry_quality_flag AS
SELECT
    *,
    CASE
        WHEN pressure_bar IS NULL
          OR temp_celsius IS NULL
          OR flow_lpm IS NULL
          OR vibration_x_g IS NULL
          OR vibration_y_g IS NULL
          OR pump_rpm IS NULL
        THEN 1 ELSE 0
    END AS has_missing_sensor_value
FROM sensor_telemetry;
SELECT * FROM sensor_telemetry_quality_flag;

--So for text-based imported columns, you should also check blanks.
SELECT
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE machine_id IS NULL OR TRIM(machine_id) = '') AS missing_machine_id,
    COUNT(*) FILTER (WHERE failure_mode IS NULL OR TRIM(failure_mode) = '') AS blank_failure_mode
FROM sensor_telemetry;
--Observation : total_rows are 864000, blank_failure_mode is 737280

-- For maintenance_log
SELECT
    COUNT(*) AS total_rows,
    COUNT(*) - COUNT(maintenance_id) AS missing_maintenance_id,
    COUNT(*) - COUNT(machine_id) AS missing_machine_id,
    COUNT(*) - COUNT(action_timestamp) AS missing_action_timestamp,
    COUNT(*) - COUNT(action_type) AS missing_action_type,
    COUNT(*) - COUNT(component_replaced) AS missing_component_replaced,
    COUNT(*) - COUNT(technician_id) AS missing_technician_id,
    COUNT(*) - COUNT(cost_usd) AS missing_cost_usd
FROM maintenance_log;
--for text-based imported columns, you should also check blanks.
SELECT
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE maintenance_id IS NULL OR TRIM(maintenance_id) = '') AS blank_maintenance_id,
    COUNT(*) FILTER (WHERE machine_id IS NULL OR TRIM(machine_id) = '') AS blank_machine_id,
    COUNT(*) FILTER (WHERE action_type IS NULL OR TRIM(action_type) = '') AS blank_action_type,
    COUNT(*) FILTER (WHERE component_replaced IS NULL OR TRIM(component_replaced) = '') AS blank_component_replaced,
    COUNT(*) FILTER (WHERE technician_id IS NULL OR TRIM(technician_id) = '') AS blank_technician_id
FROM maintenance_log;
--Observation : No missing records

--For failure_labels
SELECT
    COUNT(*) AS total_rows,
    COUNT(*) - COUNT(failure_event_id) AS missing_failure_event_id,
    COUNT(*) - COUNT(machine_id) AS missing_machine_id,
    COUNT(*) - COUNT(failure_timestamp) AS missing_failure_timestamp,
    COUNT(*) - COUNT(failure_mode) AS missing_failure_mode,
    COUNT(*) - COUNT(degradation_start_timestamp) AS missing_degradation_start_timestamp,
    COUNT(*) - COUNT(repair_cost_usd) AS missing_repair_cost_usd,
    COUNT(*) - COUNT(downtime_hours) AS missing_downtime_hours
FROM failure_labels;
--for text-based imported columns, you should also check blanks.
SELECT
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE failure_event_id IS NULL OR TRIM(failure_event_id) = '') AS blank_failure_event_id,
    COUNT(*) FILTER (WHERE machine_id IS NULL OR TRIM(machine_id) = '') AS blank_machine_id,
    COUNT(*) FILTER (WHERE failure_mode IS NULL OR TRIM(failure_mode) = '') AS blank_failure_mode
FROM failure_labels;
--Observation : No missing records

--For equipment_master
SELECT
    COUNT(*) AS total_rows,
    COUNT(*) - COUNT(machine_id) AS missing_machine_id,
    COUNT(*) - COUNT(installation_date) AS missing_installation_date,
    COUNT(*) - COUNT(total_operating_hours) AS missing_total_operating_hours,
    COUNT(*) - COUNT(fluid_type) AS missing_fluid_type,
    COUNT(*) - COUNT(last_filter_change_date) AS missing_last_filter_change_date,
    COUNT(*) - COUNT(maintenance_priority) AS missing_maintenance_priority
FROM equipment_master;
--for text-based imported columns, you should also check blanks.
SELECT
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE machine_id IS NULL OR TRIM(machine_id) = '') AS blank_machine_id,
    COUNT(*) FILTER (WHERE fluid_type IS NULL OR TRIM(fluid_type) = '') AS blank_fluid_type,
    COUNT(*) FILTER (WHERE maintenance_priority IS NULL OR TRIM(maintenance_priority) = '') AS blank_maintenance_priority
FROM equipment_master;
--Observation : No missing records


--Check for Duplicates
-- Why? Because in time-series data, each machine should usually have one row per timestamp.
--For sensor_telemetry
SELECT
    machine_id,
    timestamp,
    COUNT(*) AS duplicate_count
FROM sensor_telemetry
GROUP BY machine_id, timestamp
HAVING COUNT(*) > 1;
--Observation: No duplicate records

--For equipment_master
SELECT
    machine_id,
    COUNT(*) AS duplicate_count
FROM equipment_master
GROUP BY machine_id
HAVING COUNT(*) > 1;
--Observation: No duplicate records

-- For maintenance_log
SELECT
    maintenance_id,
    COUNT(*) AS duplicate_count
FROM maintenance_log
GROUP BY maintenance_id
HAVING COUNT(*) > 1;
--Observation: No duplicate records

-- For failure_labels
SELECT
    failure_event_id,
    COUNT(*) AS duplicate_count
FROM failure_labels
GROUP BY failure_event_id
HAVING COUNT(*) > 1;
--Observation: No duplicate records

--Check machine ID consistency across tables
--check if any telemetry machine does not exist in the equipment master.
SELECT DISTINCT s.machine_id
FROM sensor_telemetry s
LEFT JOIN equipment_master e
    ON s.machine_id = e.machine_id
WHERE e.machine_id IS NULL;
--Observation: No records detected so we are on track

-- Check Machines in maintenance log but missing from equipment master
SELECT DISTINCT m.machine_id
FROM maintenance_log m
LEFT JOIN equipment_master e
    ON m.machine_id = e.machine_id
WHERE e.machine_id IS NULL;

--Check Machines in failure labels but missing from equipment master
SELECT DISTINCT f.machine_id
FROM failure_labels f
LEFT JOIN equipment_master e
    ON f.machine_id = e.machine_id
WHERE e.machine_id IS NULL;
--Observation: No records detected so we are on track

--Check invalid or suspicious sensor ranges
--Can this value exist physically?
--Negative pressure, negative flow, negative vibration, or negative RUL would usually be suspicious.
SELECT *
FROM sensor_telemetry
WHERE pressure_bar < 0
   OR temp_celsius < 0
   OR flow_lpm < 0
   OR vibration_x_g < 0
   OR vibration_y_g < 0
   OR pump_rpm < 0
   OR rul_hours < 0;

--Check for extreme values
SELECT
    MIN(pressure_bar) AS min_pressure,
    MAX(pressure_bar) AS max_pressure,
    MIN(temp_celsius) AS min_temp,
    MAX(temp_celsius) AS max_temp,
    MIN(flow_lpm) AS min_flow,
    MAX(flow_lpm) AS max_flow,
    MIN(vibration_x_g) AS min_vibration,
    MAX(vibration_x_g) AS max_vibration,
    MIN(pump_rpm) AS min_rpm,
    MAX(pump_rpm) AS max_rpm,
    MIN(rul_hours) AS min_rul,
    MAX(rul_hours) AS max_rul
FROM sensor_telemetry;

-- Which machines have the most unreliable sensors, and how often are they dropping out?
SELECT
    machine_id,
    COUNT(*) AS total_readings,
    SUM(is_sensor_dropout) AS dropout_count,
    ROUND(100.0 * SUM(is_sensor_dropout) / COUNT(*), 2) AS dropout_rate_pct
FROM sensor_telemetry
GROUP BY machine_id
ORDER BY dropout_rate_pct DESC;
--Sensor dropout was low at 0.30% per machine, indicating strong data completeness and reliable telemetry capture for downstream EDA and modelling.

--When a sensor dropout is flagged, are the actual sensor readings also missing and does the data back that up?
SELECT
    is_sensor_dropout,
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (
        WHERE pressure_bar IS NULL
           OR temp_celsius IS NULL
           OR flow_lpm IS NULL
           OR vibration_x_g IS NULL
           OR vibration_y_g IS NULL
           OR pump_rpm IS NULL
    ) AS rows_with_missing_sensor_values
FROM sensor_telemetry
GROUP BY is_sensor_dropout
ORDER BY is_sensor_dropout;

--Check timeline logic
SELECT *
FROM failure_labels
WHERE degradation_start_timestamp > failure_timestamp;
--The failure timeline was checked to confirm that degradation start timestamps occurred before failure timestamps. No invalid records 
--were found, indicating that the failure event chronology is consistent.

--OUTLIER CHECKS
--Method 1: Compare outliers with anomaly/dropout/failure flags
SELECT
    is_anomaly,
    is_sensor_dropout,
    COUNT(*) AS total_rows,
    MIN(pressure_bar) AS min_pressure,
    MAX(pressure_bar) AS max_pressure,
    MIN(temp_celsius) AS min_temp,
    MAX(temp_celsius) AS max_temp,
    MIN(vibration_x_g) AS min_vibration_x,
    MAX(vibration_x_g) AS max_vibration_x
FROM sensor_telemetry_clean
GROUP BY is_anomaly, is_sensor_dropout
ORDER BY is_anomaly, is_sensor_dropout;

--Method 2 : IQR 
--Q1 = lower quarter of values
--Q3 = upper quarter of values
--IQR = Q3 - Q1
--Outliers = values below Q1 - 1.5*IQR or above Q3 + 1.5*IQR
WITH pressure_stats AS (
    SELECT
        percentile_cont(0.25) WITHIN GROUP (ORDER BY pressure_bar) AS q1,
        percentile_cont(0.75) WITHIN GROUP (ORDER BY pressure_bar) AS q3
    FROM sensor_telemetry_clean
    WHERE pressure_bar IS NOT NULL
),
bounds AS (
    SELECT
        q1,
        q3,
        q3 - q1 AS iqr,
        q1 - 1.5 * (q3 - q1) AS lower_bound,
        q3 + 1.5 * (q3 - q1) AS upper_bound
    FROM pressure_stats
)
SELECT s.*
FROM sensor_telemetry_clean s
CROSS JOIN bounds b
WHERE s.pressure_bar < b.lower_bound
   OR s.pressure_bar > b.upper_bound;
--The IQR method was applied to pressure_bar to identify statistically unusual pressure readings. The results showed a small number of 
--extreme low and high pressure values. These were not removed automatically because pressure spikes or drops may represent meaningful 
--hydraulic instability or pre-failure behaviour. Instead, they were flagged as operational outliers for further analysis.

-- To classify outliers, we create a simple outlier flag query
SELECT
    *,
    CASE
        WHEN pressure_bar < 0
          OR temp_celsius < -20
          OR flow_lpm < 0
          OR vibration_x_g < 0
          OR vibration_y_g < 0
          OR pump_rpm < 0
          OR rul_hours < 0
        THEN 'INVALID_VALUE'

        WHEN pressure_bar > 140
          OR temp_celsius > 80
          OR vibration_x_g > 2
          OR vibration_y_g > 2
          OR flow_lpm < 50
          OR pump_rpm < 1300
        THEN 'OPERATIONAL_OUTLIER'

        ELSE 'NORMAL_RANGE'
    END AS outlier_status
FROM sensor_telemetry_clean;

--In summary
WITH flagged AS (
    SELECT
        *,
        CASE
            WHEN pressure_bar < 0
              OR temp_celsius < -20
              OR flow_lpm < 0
              OR vibration_x_g < 0
              OR vibration_y_g < 0
              OR pump_rpm < 0
              OR rul_hours < 0
            THEN 'INVALID_VALUE'

            WHEN pressure_bar > 140
              OR temp_celsius > 80
              OR vibration_x_g > 2
              OR vibration_y_g > 2
              OR flow_lpm < 50
              OR pump_rpm < 1300
            THEN 'OPERATIONAL_OUTLIER'

            ELSE 'NORMAL_RANGE'
        END AS outlier_status
    FROM sensor_telemetry_clean
)
SELECT
    outlier_status,
    COUNT(*) AS total_rows
FROM flagged
GROUP BY outlier_status
ORDER BY total_rows DESC;
-- Observation : Normal range was 805949 & operational outlier was 55461
-- In conclusion : Outliers were not automatically removed because extreme sensor behaviour may represent early failure signals. 
--Instead, impossible values were checked separately, while operational outliers were flagged for EDA and predictive modelling.


--3. BASIC EDA
--Max pressure, temperature, vibration, and flow checks
SELECT
    machine_id,
    timestamp,
    pressure_bar,
    temp_celsius,
    flow_lpm,
    vibration_x_g,
    vibration_y_g,
    pump_rpm,
    rul_hours,
    is_anomaly,
    is_sensor_dropout
FROM sensor_telemetry
WHERE pressure_bar IS NOT NULL
ORDER BY pressure_bar DESC
LIMIT 20;

--RUL comparison queries : Do machines with lower remaining useful life also show higher pressure, temperature, vibration, or flow instability?
-- We focused on the period when machines are closer to failure.
SELECT
    machine_id,
    timestamp,
    rul_hours,
    pressure_bar,
    temp_celsius,
    vibration_x_g,
    flow_lpm
FROM sensor_telemetry
WHERE rul_hours <= 100
ORDER BY machine_id, timestamp;
-- Note : A 100-hour RUL threshold was used as an exploratory pre-failure window to examine how pressure, temperature, vibration, 
--and flow behave as machines approach failure. This threshold is not a manufacturer-defined limit; it is an analytical cut-off
--used to study late-stage degradation patterns.
-- We can also compare multiple RUL bands
SELECT
    machine_id,
    timestamp,
    rul_hours,
    pressure_bar,
    temp_celsius,
    vibration_x_g,
    flow_lpm,
    CASE
        WHEN rul_hours <= 24 THEN 'Critical: <=24 hrs'
        WHEN rul_hours <= 48 THEN 'High Risk: 25-48 hrs'
        WHEN rul_hours <= 72 THEN 'Elevated: 49-72 hrs'
        WHEN rul_hours <= 100 THEN 'Watch Window: 73-100 hrs'
        ELSE 'Normal: >100 hrs'
    END AS rul_risk_band
FROM sensor_telemetry
ORDER BY machine_id, timestamp;

-- Checks for Average sensor metrics per machine
SELECT
    machine_id,
    ROUND(AVG(pressure_bar)::INTEGER, 2) AS avg_pressure,
    ROUND(AVG(temp_celsius)::INTEGER, 2) AS avg_temperature,
    ROUND(AVG(flow_lpm)::INTEGER, 2) AS avg_flow_rate,
    ROUND(AVG(vibration_x_g)::INTEGER, 4) AS avg_vibration_x,
    ROUND(AVG(vibration_y_g)::INTEGER, 4) AS avg_vibration_y,
    ROUND(AVG(pump_rpm)::INTEGER, 2) AS avg_pump_rpm,
    ROUND(AVG(rul_hours::INTEGER), 2) AS avg_rul
FROM sensor_telemetry_clean
GROUP BY machine_id
ORDER BY avg_rul ASC;


--Check sensor extremes per machine
SELECT
    machine_id,
    MAX(pressure_bar) AS max_pressure,
    MAX(temp_celsius) AS max_temperature,
    MIN(flow_lpm) AS min_flow_rate,
    MAX(flow_lpm) AS max_flow_rate,
    MAX(vibration_x_g) AS max_vibration_x,
    MAX(vibration_y_g) AS max_vibration_y,
    MIN(pump_rpm) AS min_pump_rpm,
    MAX(pump_rpm) AS max_pump_rpm
FROM sensor_telemetry_clean
GROUP BY machine_id
ORDER BY max_pressure DESC;

--Machines closest to failure
SELECT
    machine_id,
    MIN(rul_hours) AS lowest_remaining_life,
    AVG(rul_hours) AS avg_remaining_life
FROM sensor_telemetry
GROUP BY machine_id
ORDER BY lowest_remaining_life ASC;

--RUL compared with key sensor metrics
SELECT
    machine_id,
    ROUND(AVG(rul_hours)::INTEGER, 2) AS avg_remaining_life,
    ROUND(AVG(pressure_bar)::INTEGER, 2) AS avg_pressure,
    ROUND(AVG(temp_celsius)::INTEGER, 2) AS avg_temperature,
    ROUND(AVG(vibration_x_g)::INTEGER, 4) AS avg_vibration_x,
    ROUND(AVG(vibration_y_g)::INTEGER, 4) AS avg_vibration_y,
    ROUND(AVG(flow_lpm::INTEGER), 2) AS avg_flow_rate
FROM sensor_telemetry_clean
GROUP BY machine_id
ORDER BY avg_remaining_life ASC;

--Check for Abnormal machine behaviour
SELECT
    timestamp,
    machine_id,
    pressure_bar,
    temp_celsius,
    vibration_x_g,
    vibration_y_g,
    flow_lpm,
    pump_rpm,
    rul_hours,
    is_anomaly
FROM sensor_telemetry
WHERE
    pressure_bar > 140
    OR temp_celsius > 80
    OR vibration_x_g > 2
    OR vibration_y_g > 2
    OR flow_lpm < 50
    OR pump_rpm < 1300
ORDER BY timestamp;

--Sensor dropout count by machine
SELECT
    machine_id,
    COUNT(*) AS total_readings,
    COUNT(*) FILTER (WHERE is_sensor_dropout = 1) AS sensor_dropout_count,
    ROUND(
        COUNT(*) FILTER (WHERE is_sensor_dropout = 1) * 100.0 / COUNT(*),
        2
    ) AS dropout_rate_pct
FROM sensor_telemetry
GROUP BY machine_id
ORDER BY dropout_rate_pct DESC;

--Failure count by failure mode
SELECT
    failure_mode,
    COUNT(*) AS total_failures
FROM failure_labels
GROUP BY failure_mode
ORDER BY total_failures DESC;

--Failure cost and downtime by failure mode
SELECT
    failure_mode,
    COUNT(*) AS failure_count,
    SUM(repair_cost_usd) AS total_repair_cost,
    ROUND(AVG(repair_cost_usd), 2) AS avg_repair_cost,
    SUM(downtime_hours) AS total_downtime_hours,
    ROUND(AVG(downtime_hours)::INTEGER, 2) AS avg_downtime_hours
FROM failure_labels
GROUP BY failure_mode
ORDER BY total_downtime_hours DESC;

--Maintenance cost by machine
SELECT
    machine_id,
    COUNT(*) AS maintenance_actions,
    SUM(cost_usd) AS total_maintenance_cost,
    ROUND(AVG(cost_usd), 2) AS avg_maintenance_cost
FROM maintenance_log
GROUP BY machine_id
ORDER BY total_maintenance_cost DESC;


--Hours worked before failure
SELECT
    e.machine_id,
    e.total_operating_hours,
    f.failure_timestamp,
    f.failure_mode
FROM equipment_master e
JOIN failure_labels f
    ON e.machine_id = f.machine_id
ORDER BY e.total_operating_hours DESC;


--4. MAIN ANALYSIS
WITH latest_sensor AS (
    SELECT DISTINCT ON (machine_id)
        machine_id,
        timestamp,
        rul_hours,
        pressure_bar,
        temp_celsius,
        flow_lpm,
        vibration_x_g,
        vibration_y_g,
        pump_rpm,
        is_anomaly,
        is_sensor_dropout,
        shift,
        failure_mode
    FROM sensor_telemetry_clean
    ORDER BY machine_id, timestamp DESC
),

sensor_summary AS (
    SELECT
        machine_id,
        COUNT(*) FILTER (WHERE is_anomaly = 1) AS anomaly_count,
        COUNT(*) FILTER (WHERE is_sensor_dropout = 1) AS dropout_count,
        ROUND(AVG(pressure_bar)::NUMERIC, 2) AS avg_pressure,
        ROUND(AVG(temp_celsius)::NUMERIC, 2) AS avg_temp,
        ROUND(AVG(vibration_x_g)::NUMERIC, 4) AS avg_vibration_x,
        ROUND(AVG(vibration_y_g)::NUMERIC, 4) AS avg_vibration_y
    FROM sensor_telemetry
    GROUP BY machine_id
),

latest_failure AS (
    SELECT DISTINCT ON (machine_id)
        machine_id,
        failure_mode AS known_failure_mode,
        failure_timestamp
    FROM failure_labels
    ORDER BY machine_id, failure_timestamp DESC
)

SELECT
    l.machine_id,
    e.maintenance_priority,
    e.fluid_type,
    e.total_operating_hours,

    l.timestamp AS latest_reading_time,
    l.rul_hours AS current_rul_hours,
    l.pressure_bar AS current_pressure,
    l.temp_celsius AS current_temp,
    l.flow_lpm AS current_flow,
    l.vibration_x_g AS current_vibration_x,
    l.vibration_y_g AS current_vibration_y,
    l.pump_rpm AS current_pump_rpm,

    ss.anomaly_count,
    ss.dropout_count,
    ss.avg_pressure,
    ss.avg_temp,
    ss.avg_vibration_x,
    ss.avg_vibration_y,

    COALESCE(lf.known_failure_mode, 'No failure recorded') AS known_failure_mode,

    CASE
        WHEN l.rul_hours <= 24 THEN 'FAILURE IMMINENT'
        WHEN l.rul_hours <= 48 THEN 'HIGH FAILURE RISK'
        WHEN l.rul_hours <= 72 THEN 'ELEVATED FAILURE RISK'
        WHEN l.is_anomaly = 1 THEN 'CURRENT ANOMALY DETECTED'
        WHEN l.pressure_bar > 130
          OR l.temp_celsius > 80
          OR l.vibration_x_g > 0.8
          OR l.vibration_y_g > 0.8
          OR l.flow_lpm < 60
          OR l.pump_rpm < 1400
          OR l.pump_rpm > 1550
        THEN 'ABNORMAL OPERATING CONDITION'
        WHEN ss.anomaly_count > 100 THEN 'HISTORICAL ANOMALY PATTERN'
        ELSE 'STABLE'
    END AS failure_risk_class

FROM latest_sensor l
LEFT JOIN equipment_master e
    ON l.machine_id = e.machine_id
LEFT JOIN sensor_summary ss
    ON l.machine_id = ss.machine_id
LEFT JOIN latest_failure lf
    ON l.machine_id = lf.machine_id
ORDER BY l.rul_hours ASC;


--latest pre-failure reading
WITH latest_prefailure_sensor AS (
    SELECT DISTINCT ON (machine_id)
        machine_id,
        timestamp,
        rul_hours,
        pressure_bar,
        temp_celsius,
        flow_lpm,
        vibration_x_g,
        vibration_y_g,
        pump_rpm,
        is_anomaly,
        is_sensor_dropout,
        shift,
        failure_mode
    FROM sensor_telemetry
    WHERE rul_hours > 0
    ORDER BY machine_id, timestamp DESC
),

sensor_summary AS (
    SELECT
        machine_id,
        COUNT(*) FILTER (WHERE is_anomaly = 1) AS anomaly_count,
        COUNT(*) FILTER (WHERE is_sensor_dropout = 1) AS dropout_count,
        ROUND(AVG(pressure_bar)::NUMERIC, 2) AS avg_pressure,
        ROUND(AVG(temp_celsius)::NUMERIC, 2) AS avg_temp,
        ROUND(AVG(vibration_x_g)::NUMERIC, 4) AS avg_vibration_x,
        ROUND(AVG(vibration_y_g)::NUMERIC, 4) AS avg_vibration_y
    FROM sensor_telemetry
    GROUP BY machine_id
),

latest_failure AS (
    SELECT DISTINCT ON (machine_id)
        machine_id,
        failure_mode,
        failure_timestamp
    FROM failure_labels
    ORDER BY machine_id, failure_timestamp DESC
)

SELECT
    l.machine_id,
    e.maintenance_priority,
    e.fluid_type,
    e.total_operating_hours,

    l.timestamp AS latest_prefailure_reading_time,
    l.rul_hours AS latest_prefailure_rul_hours,

    l.pressure_bar AS pressure_before_failure,
    l.temp_celsius AS temp_before_failure,
    l.flow_lpm AS flow_before_failure,
    l.vibration_x_g AS vibration_x_before_failure,
    l.vibration_y_g AS vibration_y_before_failure,
    l.pump_rpm AS pump_rpm_before_failure,

    ss.anomaly_count,
    ss.dropout_count,
    ss.avg_pressure,
    ss.avg_temp,
    ss.avg_vibration_x,
    ss.avg_vibration_y,

    COALESCE(lf.failure_mode, 'No failure recorded') AS known_failure_mode,

    CASE
        WHEN l.rul_hours <= 24 THEN 'FAILURE IMMINENT'
        WHEN l.rul_hours <= 48 THEN 'HIGH FAILURE RISK'
        WHEN l.rul_hours <= 72 THEN 'ELEVATED FAILURE RISK'
        WHEN l.is_anomaly = 1 THEN 'CURRENT ANOMALY DETECTED'
        WHEN l.pressure_bar > 130
          OR l.temp_celsius > 80
          OR l.vibration_x_g > 0.8
          OR l.vibration_y_g > 0.8
          OR l.flow_lpm < 60
          OR l.pump_rpm < 1400
          OR l.pump_rpm > 1550
        THEN 'ABNORMAL OPERATING CONDITION'
        WHEN ss.anomaly_count > 100 THEN 'HISTORICAL ANOMALY PATTERN'
        ELSE 'STABLE'
    END AS failure_risk_classification

FROM latest_prefailure_sensor l
LEFT JOIN equipment_master e
    ON l.machine_id = e.machine_id
LEFT JOIN sensor_summary ss
    ON l.machine_id = ss.machine_id
LEFT JOIN latest_failure lf
    ON l.machine_id = lf.machine_id
ORDER BY l.rul_hours ASC;


--Sensor Quality View
--Preserve raw telemetry, flag missing sensor rows, flag pressure outliers, and keep dropout/anomaly indicators visible.
CREATE OR REPLACE VIEW vw_sensor_telemetry_quality AS
WITH pressure_stats AS (
    SELECT
        percentile_cont(0.25) WITHIN GROUP (ORDER BY pressure_bar) AS q1,
        percentile_cont(0.75) WITHIN GROUP (ORDER BY pressure_bar) AS q3
    FROM sensor_telemetry
    WHERE pressure_bar IS NOT NULL
),
pressure_bounds AS (
    SELECT
        q1,
        q3,
        q3 - q1 AS iqr,
        q1 - 1.5 * (q3 - q1) AS lower_bound,
        q3 + 1.5 * (q3 - q1) AS upper_bound
    FROM pressure_stats
)
SELECT
    s.*,

    CASE
        WHEN s.pressure_bar IS NULL
          OR s.temp_celsius IS NULL
          OR s.flow_lpm IS NULL
          OR s.vibration_x_g IS NULL
          OR s.vibration_y_g IS NULL
          OR s.pump_rpm IS NULL
        THEN 1 ELSE 0
    END AS has_missing_sensor_value,

    CASE
        WHEN s.pressure_bar IS NULL THEN 'MISSING_PRESSURE'
        WHEN s.pressure_bar < b.lower_bound THEN 'LOW_PRESSURE_OUTLIER'
        WHEN s.pressure_bar > b.upper_bound THEN 'HIGH_PRESSURE_OUTLIER'
        ELSE 'NORMAL_PRESSURE'
    END AS pressure_outlier_status,

    CASE
        WHEN s.rul_hours <= 24 THEN 'CRITICAL_0_24H'
        WHEN s.rul_hours <= 48 THEN 'HIGH_RISK_25_48H'
        WHEN s.rul_hours <= 72 THEN 'ELEVATED_49_72H'
        WHEN s.rul_hours <= 100 THEN 'WATCH_73_100H'
        WHEN s.rul_hours <= 168 THEN 'MODERATE_101_168H'
        ELSE 'HEALTHY_OVER_168H'
    END AS rul_risk_band

FROM sensor_telemetry s
CROSS JOIN pressure_bounds b;


SELECT * FROM vw_sensor_telemetry_quality;


--Clean Telemetry View
--Create a clean analysis version excluding rows with missing core sensor values, while keeping the raw table untouched.
CREATE OR REPLACE VIEW vw_sensor_telemetry_clean AS
SELECT *
FROM vw_sensor_telemetry_quality
WHERE has_missing_sensor_value = 0;

SELECT * FROM vw_sensor_telemetry_clean;


--Fleet Health Overview View
--Main executive dashboard page. One row per machine showing latest condition, health score, RUL status, anomaly/dropout totals, latest maintenance, and failure impact.
CREATE OR REPLACE VIEW vw_fleet_health_overview AS
WITH latest_sensor AS (
    SELECT DISTINCT ON (machine_id)
        machine_id,
        timestamp AS latest_reading_timestamp,
        rul_hours AS latest_rul_hours,
        pressure_bar AS latest_pressure_bar,
        temp_celsius AS latest_temp_celsius,
        flow_lpm AS latest_flow_lpm,
        vibration_x_g AS latest_vibration_x_g,
        vibration_y_g AS latest_vibration_y_g,
        pump_rpm AS latest_pump_rpm,
        is_anomaly AS latest_is_anomaly,
        is_sensor_dropout AS latest_is_sensor_dropout,
        shift AS latest_shift,
        failure_mode AS latest_sensor_failure_mode
    FROM vw_sensor_telemetry_clean
    ORDER BY machine_id, timestamp DESC
),

sensor_summary AS (
    SELECT
        machine_id,
        COUNT(*) AS clean_reading_count,
        COUNT(*) FILTER (WHERE is_anomaly = 1) AS total_anomalies,
        COUNT(*) FILTER (WHERE is_sensor_dropout = 1) AS total_dropouts,

        ROUND((COUNT(*) FILTER (WHERE is_anomaly = 1) * 100.0 / NULLIF(COUNT(*), 0))::NUMERIC, 2) AS anomaly_rate_pct,
        ROUND((COUNT(*) FILTER (WHERE is_sensor_dropout = 1) * 100.0 / NULLIF(COUNT(*), 0))::NUMERIC, 2) AS dropout_rate_pct,

        ROUND(MIN(rul_hours)::NUMERIC, 2) AS historical_min_rul_hours,
        ROUND(AVG(rul_hours)::NUMERIC, 2) AS avg_rul_hours,

        ROUND(AVG(pressure_bar)::NUMERIC, 2) AS avg_pressure_bar,
        ROUND(AVG(temp_celsius)::NUMERIC, 2) AS avg_temp_celsius,
        ROUND(AVG(flow_lpm)::NUMERIC, 2) AS avg_flow_lpm,
        ROUND(AVG(vibration_x_g)::NUMERIC, 4) AS avg_vibration_x_g,
        ROUND(AVG(vibration_y_g)::NUMERIC, 4) AS avg_vibration_y_g,
        ROUND(AVG(pump_rpm)::NUMERIC, 2) AS avg_pump_rpm
    FROM vw_sensor_telemetry_clean
    GROUP BY machine_id
),

failure_summary AS (
    SELECT
        machine_id,
        COUNT(*) AS total_failures,
        SUM(repair_cost_usd) AS total_repair_cost,
        SUM(downtime_hours) AS total_downtime_hours,
        ROUND(AVG(repair_cost_usd)::NUMERIC, 2) AS avg_repair_cost,
        ROUND(AVG(downtime_hours)::NUMERIC, 2) AS avg_downtime_hours
    FROM failure_labels
    GROUP BY machine_id
),

latest_failure AS (
    SELECT DISTINCT ON (machine_id)
        machine_id,
        failure_event_id AS latest_failure_event_id,
        failure_timestamp AS latest_failure_timestamp,
        failure_mode AS latest_failure_mode,
        repair_cost_usd AS latest_repair_cost,
        downtime_hours AS latest_downtime_hours
    FROM failure_labels
    ORDER BY machine_id, failure_timestamp DESC
),

latest_maintenance AS (
    SELECT DISTINCT ON (machine_id)
        machine_id,
        maintenance_id AS latest_maintenance_id,
        action_timestamp AS latest_maintenance_timestamp,
        action_type AS latest_maintenance_type,
        component_replaced AS latest_component_replaced,
        technician_id AS latest_technician_id,
        cost_usd AS latest_maintenance_cost
    FROM maintenance_log
    ORDER BY machine_id, action_timestamp DESC
)

SELECT
    ls.machine_id,
    e.maintenance_priority,
    e.fluid_type,
    e.total_operating_hours,
    e.installation_date,
    e.last_filter_change_date,

    ls.latest_reading_timestamp,
    ls.latest_rul_hours,
    ls.latest_reading_timestamp + (ls.latest_rul_hours * INTERVAL '1 hour') AS projected_failure_timestamp,

    ls.latest_pressure_bar,
    ls.latest_temp_celsius,
    ls.latest_flow_lpm,
    ls.latest_vibration_x_g,
    ls.latest_vibration_y_g,
    ls.latest_pump_rpm,
    ls.latest_shift,
    ls.latest_is_anomaly,
    ls.latest_is_sensor_dropout,
    COALESCE(ls.latest_sensor_failure_mode, 'None') AS latest_sensor_failure_mode,

    ss.clean_reading_count,
    ss.total_anomalies,
    ss.total_dropouts,
    ss.anomaly_rate_pct,
    ss.dropout_rate_pct,
    ss.historical_min_rul_hours,
    ss.avg_rul_hours,
    ss.avg_pressure_bar,
    ss.avg_temp_celsius,
    ss.avg_flow_lpm,
    ss.avg_vibration_x_g,
    ss.avg_vibration_y_g,
    ss.avg_pump_rpm,

    COALESCE(fs.total_failures, 0) AS total_failures,
    COALESCE(fs.total_repair_cost, 0) AS total_repair_cost,
    COALESCE(fs.total_downtime_hours, 0) AS total_downtime_hours,
    COALESCE(fs.avg_repair_cost, 0) AS avg_repair_cost,
    COALESCE(fs.avg_downtime_hours, 0) AS avg_downtime_hours,

    lf.latest_failure_event_id,
    lf.latest_failure_timestamp,
    COALESCE(lf.latest_failure_mode, 'No failure recorded') AS latest_failure_mode,
    COALESCE(lf.latest_repair_cost, 0) AS latest_repair_cost,
    COALESCE(lf.latest_downtime_hours, 0) AS latest_downtime_hours,

    lm.latest_maintenance_id,
    lm.latest_maintenance_timestamp,
    lm.latest_maintenance_type,
    lm.latest_component_replaced,
    lm.latest_technician_id,
    lm.latest_maintenance_cost,

    GREATEST(0,
        100
        - (CASE WHEN ls.latest_rul_hours <= 24 THEN 45 ELSE 0 END)
        - (CASE WHEN ls.latest_rul_hours > 24 AND ls.latest_rul_hours <= 48 THEN 35 ELSE 0 END)
        - (CASE WHEN ls.latest_rul_hours > 48 AND ls.latest_rul_hours <= 72 THEN 25 ELSE 0 END)
        - (CASE WHEN ls.latest_is_anomaly = 1 THEN 15 ELSE 0 END)
        - (CASE WHEN ls.latest_pressure_bar > 130 THEN 10 ELSE 0 END)
        - (CASE WHEN ls.latest_temp_celsius > 80 THEN 10 ELSE 0 END)
        - (CASE WHEN ls.latest_vibration_x_g > 0.8 OR ls.latest_vibration_y_g > 0.8 THEN 10 ELSE 0 END)
        - (CASE WHEN ls.latest_flow_lpm < 60 THEN 10 ELSE 0 END)
        - (CASE WHEN ls.latest_pump_rpm < 1400 OR ls.latest_pump_rpm > 1550 THEN 10 ELSE 0 END)
        - (CASE WHEN ls.latest_is_sensor_dropout = 1 THEN 5 ELSE 0 END)
    ) AS health_score,

    CASE
        WHEN ls.latest_rul_hours <= 24 THEN 'CRITICAL'
        WHEN ls.latest_rul_hours <= 48 THEN 'HIGH_RISK'
        WHEN ls.latest_rul_hours <= 72 THEN 'ELEVATED'
        WHEN ls.latest_rul_hours <= 168 THEN 'MODERATE'
        ELSE 'HEALTHY'
    END AS latest_condition_status,

    CASE
        WHEN ss.historical_min_rul_hours <= 0 THEN 'FAILED_DURING_OBSERVATION'
        WHEN ss.historical_min_rul_hours <= 24 THEN 'REACHED_CRITICAL_RUL'
        WHEN ss.historical_min_rul_hours <= 72 THEN 'REACHED_RISK_WINDOW'
        ELSE 'NO_CRITICAL_FAILURE_WINDOW'
    END AS historical_failure_status

FROM latest_sensor ls
LEFT JOIN equipment_master e
    ON ls.machine_id = e.machine_id
LEFT JOIN sensor_summary ss
    ON ls.machine_id = ss.machine_id
LEFT JOIN failure_summary fs
    ON ls.machine_id = fs.machine_id
LEFT JOIN latest_failure lf
    ON ls.machine_id = lf.machine_id
LEFT JOIN latest_maintenance lm
    ON ls.machine_id = lm.machine_id;


SELECT * FROM vw_fleet_health_overview;



--Pre-Failure Risk Profile View
--Avoid using only MIN(rul_hours) and instead shows the latest available warning state before failure.
CREATE OR REPLACE VIEW vw_prefailure_risk_profile AS
WITH latest_prefailure_sensor AS (
    SELECT DISTINCT ON (machine_id)
        machine_id,
        timestamp AS prefailure_reading_timestamp,
        rul_hours AS prefailure_rul_hours,
        pressure_bar AS prefailure_pressure_bar,
        temp_celsius AS prefailure_temp_celsius,
        flow_lpm AS prefailure_flow_lpm,
        vibration_x_g AS prefailure_vibration_x_g,
        vibration_y_g AS prefailure_vibration_y_g,
        pump_rpm AS prefailure_pump_rpm,
        is_anomaly AS prefailure_is_anomaly,
        is_sensor_dropout AS prefailure_is_sensor_dropout,
        shift AS prefailure_shift,
        failure_mode AS prefailure_sensor_failure_mode
    FROM vw_sensor_telemetry_clean
    WHERE rul_hours > 0
    ORDER BY machine_id, timestamp DESC
),

sensor_summary AS (
    SELECT
        machine_id,
        COUNT(*) FILTER (WHERE is_anomaly = 1) AS anomaly_count,
        COUNT(*) FILTER (WHERE is_sensor_dropout = 1) AS dropout_count,
        ROUND(AVG(pressure_bar)::NUMERIC, 2) AS avg_pressure_bar,
        ROUND(AVG(temp_celsius)::NUMERIC, 2) AS avg_temp_celsius,
        ROUND(AVG(flow_lpm)::NUMERIC, 2) AS avg_flow_lpm,
        ROUND(AVG(vibration_x_g)::NUMERIC, 4) AS avg_vibration_x_g,
        ROUND(AVG(vibration_y_g)::NUMERIC, 4) AS avg_vibration_y_g,
        ROUND(AVG(pump_rpm)::NUMERIC, 2) AS avg_pump_rpm
    FROM vw_sensor_telemetry_clean
    GROUP BY machine_id
),

latest_failure AS (
    SELECT DISTINCT ON (machine_id)
        machine_id,
        failure_timestamp,
        failure_mode
    FROM failure_labels
    ORDER BY machine_id, failure_timestamp DESC
)

SELECT
    p.machine_id,
    e.maintenance_priority,
    e.fluid_type,
    e.total_operating_hours,

    p.prefailure_reading_timestamp,
    p.prefailure_rul_hours,
    p.prefailure_reading_timestamp + (p.prefailure_rul_hours * INTERVAL '1 hour') AS projected_failure_timestamp,

    p.prefailure_pressure_bar,
    p.prefailure_temp_celsius,
    p.prefailure_flow_lpm,
    p.prefailure_vibration_x_g,
    p.prefailure_vibration_y_g,
    p.prefailure_pump_rpm,
    p.prefailure_shift,
    p.prefailure_is_anomaly,
    p.prefailure_is_sensor_dropout,

    ss.anomaly_count,
    ss.dropout_count,
    ss.avg_pressure_bar,
    ss.avg_temp_celsius,
    ss.avg_flow_lpm,
    ss.avg_vibration_x_g,
    ss.avg_vibration_y_g,
    ss.avg_pump_rpm,

    COALESCE(lf.failure_mode, 'No failure recorded') AS known_failure_mode,
    lf.failure_timestamp,

    CASE
        WHEN p.prefailure_rul_hours <= 24 THEN 'FAILURE_IMMINENT'
        WHEN p.prefailure_rul_hours <= 48 THEN 'HIGH_FAILURE_RISK'
        WHEN p.prefailure_rul_hours <= 72 THEN 'ELEVATED_FAILURE_RISK'
        WHEN p.prefailure_is_anomaly = 1 THEN 'CURRENT_ANOMALY_DETECTED'
        WHEN p.prefailure_pressure_bar > 130
          OR p.prefailure_temp_celsius > 80
          OR p.prefailure_vibration_x_g > 0.8
          OR p.prefailure_vibration_y_g > 0.8
          OR p.prefailure_flow_lpm < 60
          OR p.prefailure_pump_rpm < 1400
          OR p.prefailure_pump_rpm > 1550
        THEN 'ABNORMAL_OPERATING_CONDITION'
        WHEN ss.anomaly_count > 100 THEN 'HISTORICAL_ANOMALY_PATTERN'
        ELSE 'STABLE'
    END AS failure_risk_classification,

    CASE
        WHEN p.prefailure_rul_hours <= 24 THEN 'STOP_MACHINE_AND_REPAIR'
        WHEN p.prefailure_rul_hours <= 48 THEN 'URGENT_MAINTENANCE_PLANNING'
        WHEN p.prefailure_rul_hours <= 72 THEN 'SCHEDULE_INSPECTION'
        WHEN p.prefailure_is_anomaly = 1 THEN 'INVESTIGATE_ANOMALY'
        ELSE 'MONITOR'
    END AS recommended_maintenance_action

FROM latest_prefailure_sensor p
LEFT JOIN equipment_master e
    ON p.machine_id = e.machine_id
LEFT JOIN sensor_summary ss
    ON p.machine_id = ss.machine_id
LEFT JOIN latest_failure lf
    ON p.machine_id = lf.machine_id;

SELECT * FROM vw_prefailure_risk_profile;


--Hourly Sensor Trends View
CREATE OR REPLACE VIEW vw_hourly_sensor_trends AS
SELECT
    machine_id,
    DATE_TRUNC('hour', timestamp) AS hour_bucket,

    ROUND(AVG(pressure_bar)::NUMERIC, 2) AS avg_pressure_bar,
    ROUND(MIN(pressure_bar)::NUMERIC, 2) AS min_pressure_bar,
    ROUND(MAX(pressure_bar)::NUMERIC, 2) AS max_pressure_bar,

    ROUND(AVG(temp_celsius)::NUMERIC, 2) AS avg_temp_celsius,
    ROUND(MIN(temp_celsius)::NUMERIC, 2) AS min_temp_celsius,
    ROUND(MAX(temp_celsius)::NUMERIC, 2) AS max_temp_celsius,

    ROUND(AVG(flow_lpm)::NUMERIC, 2) AS avg_flow_lpm,
    ROUND(MIN(flow_lpm)::NUMERIC, 2) AS min_flow_lpm,
    ROUND(MAX(flow_lpm)::NUMERIC, 2) AS max_flow_lpm,

    ROUND(AVG(vibration_x_g)::NUMERIC, 4) AS avg_vibration_x_g,
    ROUND(MAX(vibration_x_g)::NUMERIC, 4) AS max_vibration_x_g,

    ROUND(AVG(vibration_y_g)::NUMERIC, 4) AS avg_vibration_y_g,
    ROUND(MAX(vibration_y_g)::NUMERIC, 4) AS max_vibration_y_g,

    ROUND(AVG(pump_rpm)::NUMERIC, 2) AS avg_pump_rpm,
    ROUND(MIN(pump_rpm)::NUMERIC, 2) AS min_pump_rpm,
    ROUND(MAX(pump_rpm)::NUMERIC, 2) AS max_pump_rpm,

    ROUND(AVG(rul_hours)::NUMERIC, 2) AS avg_rul_hours,
    ROUND(MIN(rul_hours)::NUMERIC, 2) AS min_rul_hours,

    COUNT(*) AS readings_in_hour,
    COUNT(*) FILTER (WHERE is_anomaly = 1) AS anomalies_in_hour,
    COUNT(*) FILTER (WHERE is_sensor_dropout = 1) AS dropouts_in_hour,

    CASE
        WHEN MIN(rul_hours) <= 24 THEN 'CRITICAL_0_24H'
        WHEN MIN(rul_hours) <= 48 THEN 'HIGH_RISK_25_48H'
        WHEN MIN(rul_hours) <= 72 THEN 'ELEVATED_49_72H'
        WHEN MIN(rul_hours) <= 100 THEN 'WATCH_73_100H'
        WHEN MIN(rul_hours) <= 168 THEN 'MODERATE_101_168H'
        ELSE 'HEALTHY_OVER_168H'
    END AS hourly_rul_risk_band

FROM vw_sensor_telemetry_clean
GROUP BY
    machine_id,
    DATE_TRUNC('hour', timestamp);

SELECT * FROM vw_hourly_sensor_trends;



--Alert Monitoring View
CREATE OR REPLACE VIEW vw_failure_degradation_impact AS
SELECT
    f.failure_event_id,
    f.machine_id,
    f.failure_mode,
    f.degradation_start_timestamp,
    f.failure_timestamp,
    f.repair_cost_usd,
    f.downtime_hours,

    (f.failure_timestamp::date - f.degradation_start_timestamp::date) AS degradation_days,

    e.maintenance_priority,
    e.fluid_type,
    e.total_operating_hours,
    e.last_filter_change_date,

    (f.failure_timestamp::date - e.last_filter_change_date::date) AS days_since_filter_change,

    COUNT(s.*) AS readings_during_degradation,
    COUNT(*) FILTER (WHERE s.is_anomaly = 1) AS anomalies_during_degradation,
    COUNT(*) FILTER (WHERE s.is_sensor_dropout = 1) AS dropouts_during_degradation,

    ROUND(AVG(s.pressure_bar)::NUMERIC, 2) AS avg_pressure_during_degradation,
    ROUND(MAX(s.pressure_bar)::NUMERIC, 2) AS max_pressure_during_degradation,

    ROUND(AVG(s.temp_celsius)::NUMERIC, 2) AS avg_temp_during_degradation,
    ROUND(MAX(s.temp_celsius)::NUMERIC, 2) AS max_temp_during_degradation,

    ROUND(AVG(s.flow_lpm)::NUMERIC, 2) AS avg_flow_during_degradation,
    ROUND(MIN(s.flow_lpm)::NUMERIC, 2) AS min_flow_during_degradation,

    ROUND(AVG(s.vibration_x_g)::NUMERIC, 4) AS avg_vibration_x_during_degradation,
    ROUND(MAX(s.vibration_x_g)::NUMERIC, 4) AS max_vibration_x_during_degradation,

    ROUND(AVG(s.vibration_y_g)::NUMERIC, 4) AS avg_vibration_y_during_degradation,
    ROUND(MAX(s.vibration_y_g)::NUMERIC, 4) AS max_vibration_y_during_degradation,

    ROUND(AVG(s.pump_rpm)::NUMERIC, 2) AS avg_pump_rpm_during_degradation,
    ROUND(MIN(s.rul_hours)::NUMERIC, 2) AS lowest_rul_before_failure,

    CASE
        WHEN (f.failure_timestamp::date - f.degradation_start_timestamp::date) <= 7
            THEN 'FAST_DEGRADATION_HIGH_PRIORITY'
        WHEN (f.failure_timestamp::date - f.degradation_start_timestamp::date) <= 14
            THEN 'MODERATE_DEGRADATION_WINDOW'
        ELSE 'SLOW_DEGRADATION_PREDICTABLE_PATTERN'
    END AS degradation_insight,

    CASE
        WHEN f.repair_cost_usd >= 25000 OR f.downtime_hours >= 15
            THEN 'HIGH_BUSINESS_IMPACT'
        WHEN f.repair_cost_usd >= 15000 OR f.downtime_hours >= 10
            THEN 'MEDIUM_BUSINESS_IMPACT'
        ELSE 'LOW_BUSINESS_IMPACT'
    END AS failure_business_impact_band

FROM failure_labels f
LEFT JOIN equipment_master e
    ON f.machine_id = e.machine_id
LEFT JOIN sensor_telemetry_clean s
    ON f.machine_id = s.machine_id
   AND s.timestamp BETWEEN f.degradation_start_timestamp AND f.failure_timestamp
GROUP BY
    f.failure_event_id,
    f.machine_id,
    f.failure_mode,
    f.degradation_start_timestamp,
    f.failure_timestamp,
    f.repair_cost_usd,
    f.downtime_hours,
    e.maintenance_priority,
    e.fluid_type,
    e.total_operating_hours,
    e.last_filter_change_date;

SELECT * FROM vw_failure_degradation_impact;


--Maintenance Actions Enriched View
CREATE OR REPLACE VIEW vw_maintenance_actions_enriched AS
SELECT
    ml.maintenance_id,
    ml.machine_id,
    ml.action_timestamp,
    ml.action_type,
    ml.component_replaced,
    ml.technician_id,
    ml.cost_usd,

    e.maintenance_priority,
    e.fluid_type,
    e.total_operating_hours,

    CASE
        WHEN ml.action_type = 'Reactive' THEN 'REACTIVE_UNPLANNED'
        WHEN ml.action_type = 'Preventive' THEN 'PREVENTIVE_PLANNED'
        WHEN ml.action_type = 'Inspection' THEN 'INSPECTION'
        ELSE 'OTHER'
    END AS maintenance_classification,

    CASE
        WHEN ml.cost_usd >= 5000 THEN 'HIGH_COST'
        WHEN ml.cost_usd >= 2000 THEN 'MEDIUM_COST'
        ELSE 'LOW_COST'
    END AS action_cost_band,

    CASE
        WHEN ml.component_replaced IS NULL OR TRIM(ml.component_replaced) = '' OR ml.component_replaced = 'None'
            THEN 'NO_COMPONENT_REPLACED'
        ELSE 'COMPONENT_REPLACED'
    END AS replacement_status,

    EXTRACT(DAY FROM ml.action_timestamp - e.installation_date) AS days_since_installation_at_action,

    LAG(ml.action_timestamp) OVER (
        PARTITION BY ml.machine_id, ml.component_replaced
        ORDER BY ml.action_timestamp
    ) AS previous_same_component_action_date,

    EXTRACT(DAY FROM ml.action_timestamp - LAG(ml.action_timestamp) OVER (
        PARTITION BY ml.machine_id, ml.component_replaced
        ORDER BY ml.action_timestamp
    )) AS days_since_previous_same_component_action

FROM maintenance_log ml
LEFT JOIN equipment_master e
    ON ml.machine_id = e.machine_id;

SELECT * FROM vw_maintenance_actions_enriched;


--Operator Action List View
CREATE OR REPLACE VIEW vw_operator_action_list AS
WITH alert_summary AS (
    SELECT
        machine_id,
        COUNT(*) AS total_alert_events,
        COUNT(*) FILTER (WHERE alert_severity = 'CRITICAL') AS critical_alert_events,
        COUNT(*) FILTER (WHERE alert_severity = 'HIGH') AS high_alert_events,
        COUNT(*) FILTER (WHERE alert_severity = 'MEDIUM') AS medium_alert_events,
        MAX(alert_timestamp) AS latest_alert_timestamp
    FROM vw_alert_monitoring
    GROUP BY machine_id
)
SELECT
    f.machine_id,
    f.maintenance_priority,
    f.fluid_type,
    f.latest_reading_timestamp,
    f.latest_rul_hours,
    f.latest_condition_status,
    f.historical_failure_status,
    f.health_score,

    f.latest_pressure_bar,
    f.latest_temp_celsius,
    f.latest_flow_lpm,
    f.latest_vibration_x_g,
    f.latest_vibration_y_g,
    f.latest_pump_rpm,
    f.latest_shift,

    COALESCE(a.total_alert_events, 0) AS total_alert_events,
    COALESCE(a.critical_alert_events, 0) AS critical_alert_events,
    COALESCE(a.high_alert_events, 0) AS high_alert_events,
    COALESCE(a.medium_alert_events, 0) AS medium_alert_events,
    a.latest_alert_timestamp,

    f.latest_maintenance_timestamp,
    f.latest_maintenance_type,
    f.latest_component_replaced,

    f.latest_failure_mode,
    f.latest_failure_timestamp,

    CASE
        WHEN f.latest_condition_status = 'CRITICAL' THEN 'STOP_MACHINE_AND_CALL_SUPERVISOR'
        WHEN f.latest_condition_status = 'HIGH_RISK' THEN 'URGENT_MAINTENANCE_REVIEW'
        WHEN COALESCE(a.critical_alert_events, 0) > 0 THEN 'INVESTIGATE_CRITICAL_ALERTS'
        WHEN COALESCE(a.high_alert_events, 0) > 0 THEN 'CHECK_MACHINE_WITHIN_SHIFT'
        WHEN f.latest_condition_status = 'ELEVATED' THEN 'SCHEDULE_INSPECTION'
        ELSE 'CONTINUE_MONITORING'
    END AS operator_recommended_action

FROM vw_fleet_health_overview f
LEFT JOIN alert_summary a
    ON f.machine_id = a.machine_id;

SELECT * FROM vw_operator_action_list;


--Business KPI Summary View
CREATE OR REPLACE VIEW vw_business_kpi_summary AS
WITH fleet AS (
    SELECT * FROM vw_fleet_health_overview
),
maintenance AS (
    SELECT
        SUM(cost_usd) AS total_maintenance_cost,
        SUM(CASE WHEN action_type = 'Reactive' THEN cost_usd ELSE 0 END) AS reactive_cost,
        SUM(CASE WHEN action_type = 'Preventive' THEN cost_usd ELSE 0 END) AS preventive_cost,
        SUM(CASE WHEN action_type = 'Inspection' THEN cost_usd ELSE 0 END) AS inspection_cost,
        COUNT(*) AS maintenance_action_count
    FROM maintenance_log
),
failure AS (
    SELECT
        COUNT(*) AS total_failure_events,
        SUM(repair_cost_usd) AS total_repair_cost,
        SUM(downtime_hours) AS total_downtime_hours
    FROM failure_labels
),
telemetry AS (
    SELECT
        COUNT(*) AS total_raw_readings,
        COUNT(*) FILTER (WHERE is_anomaly = 1) AS total_anomaly_readings,
        COUNT(*) FILTER (WHERE is_sensor_dropout = 1) AS total_dropout_readings,
        COUNT(*) FILTER (
            WHERE pressure_bar IS NULL
               OR temp_celsius IS NULL
               OR flow_lpm IS NULL
               OR vibration_x_g IS NULL
               OR vibration_y_g IS NULL
               OR pump_rpm IS NULL
        ) AS total_missing_sensor_rows
    FROM sensor_telemetry
)

SELECT
    'TOTAL_MACHINES' AS metric_name,
    COUNT(*)::NUMERIC AS metric_value,
    'machines' AS metric_unit
FROM fleet

UNION ALL
SELECT
    'CURRENT_CRITICAL_MACHINES',
    COUNT(*) FILTER (WHERE latest_condition_status = 'CRITICAL')::NUMERIC,
    'machines'
FROM fleet

UNION ALL
SELECT
    'MACHINES_WITH_RECORDED_FAILURE',
    COUNT(*) FILTER (WHERE total_failures > 0)::NUMERIC,
    'machines'
FROM fleet

UNION ALL
SELECT
    'TOTAL_REPAIR_COST',
    COALESCE(MAX(total_repair_cost), 0)::NUMERIC,
    'USD'
FROM failure

UNION ALL
SELECT
    'TOTAL_DOWNTIME_HOURS',
    COALESCE(MAX(total_downtime_hours), 0)::NUMERIC,
    'hours'
FROM failure

UNION ALL
SELECT
    'TOTAL_MAINTENANCE_COST',
    COALESCE(MAX(total_maintenance_cost), 0)::NUMERIC,
    'USD'
FROM maintenance

UNION ALL
SELECT
    'REACTIVE_COST_RATIO_PCT',
    ROUND((MAX(reactive_cost) * 100.0 / NULLIF(MAX(total_maintenance_cost), 0))::NUMERIC, 2),
    'percent'
FROM maintenance

UNION ALL
SELECT
    'ANOMALY_RATE_PCT',
    ROUND((MAX(total_anomaly_readings) * 100.0 / NULLIF(MAX(total_raw_readings), 0))::NUMERIC, 2),
    'percent'
FROM telemetry

UNION ALL
SELECT
    'DROPOUT_RATE_PCT',
    ROUND((MAX(total_dropout_readings) * 100.0 / NULLIF(MAX(total_raw_readings), 0))::NUMERIC, 2),
    'percent'
FROM telemetry

UNION ALL
SELECT
    'MISSING_SENSOR_ROW_RATE_PCT',
    ROUND((MAX(total_missing_sensor_rows) * 100.0 / NULLIF(MAX(total_raw_readings), 0))::NUMERIC, 2),
    'percent'
FROM telemetry;

SELECT * FROM vw_business_kpi_summary;


--Confirm all views exist before moving to powerbi
SELECT table_name
FROM information_schema.views
WHERE table_schema = 'public'
ORDER BY table_name;

--Preview each view
SELECT * FROM vw_fleet_health_overview;
SELECT * FROM vw_prefailure_risk_profile;
SELECT * FROM vw_hourly_sensor_trends LIMIT 20;
SELECT * FROM vw_alert_monitoring LIMIT 20;
SELECT * FROM vw_failure_degradation_impact;
SELECT * FROM vw_maintenance_actions_enriched LIMIT 20;
SELECT * FROM vw_operator_action_list;
SELECT * FROM vw_business_kpi_summary;

--Check row counts
SELECT 'vw_fleet_health_overview' AS view_name, COUNT(*) FROM vw_fleet_health_overview
UNION ALL
SELECT 'vw_prefailure_risk_profile', COUNT(*) FROM vw_prefailure_risk_profile
UNION ALL
SELECT 'vw_hourly_sensor_trends', COUNT(*) FROM vw_hourly_sensor_trends
UNION ALL
SELECT 'vw_alert_monitoring', COUNT(*) FROM vw_alert_monitoring
UNION ALL
SELECT 'vw_failure_degradation_impact', COUNT(*) FROM vw_failure_degradation_impact
UNION ALL
SELECT 'vw_maintenance_actions_enriched', COUNT(*) FROM vw_maintenance_actions_enriched
UNION ALL
SELECT 'vw_operator_action_list', COUNT(*) FROM vw_operator_action_list
UNION ALL
SELECT 'vw_business_kpi_summary', COUNT(*) FROM vw_business_kpi_summary;



CREATE OR REPLACE VIEW vw_machine_sensor_quality_summary AS
SELECT
    machine_id,

    COUNT(*) AS total_raw_readings,

    COUNT(*) FILTER (WHERE is_anomaly = 1) AS total_anomaly_readings,

    COUNT(*) FILTER (WHERE is_sensor_dropout = 1) AS total_dropout_readings,

    COUNT(*) FILTER (
        WHERE pressure_bar IS NULL
           OR temp_celsius IS NULL
           OR flow_lpm IS NULL
           OR vibration_x_g IS NULL
           OR vibration_y_g IS NULL
           OR pump_rpm IS NULL
    ) AS total_missing_sensor_rows,

    ROUND(
        (COUNT(*) FILTER (WHERE is_anomaly = 1) * 100.0 / NULLIF(COUNT(*), 0))::NUMERIC,
        2
    ) AS anomaly_rate_pct,

    ROUND(
        (COUNT(*) FILTER (WHERE is_sensor_dropout = 1) * 100.0 / NULLIF(COUNT(*), 0))::NUMERIC,
        2
    ) AS dropout_rate_pct,

    ROUND(
        (
            COUNT(*) FILTER (
                WHERE pressure_bar IS NULL
                   OR temp_celsius IS NULL
                   OR flow_lpm IS NULL
                   OR vibration_x_g IS NULL
                   OR vibration_y_g IS NULL
                   OR pump_rpm IS NULL
            ) * 100.0 / NULLIF(COUNT(*), 0)
        )::NUMERIC,
        2
    ) AS missing_sensor_row_rate_pct

FROM sensor_telemetry
GROUP BY machine_id;


SELECT *
FROM vw_machine_sensor_quality_summary
ORDER BY machine_id;



CREATE OR REPLACE VIEW vw_daily_sensor_quality_summary AS
SELECT
    machine_id,
    timestamp::date AS reading_date,

    COUNT(*) AS total_raw_readings,

    COUNT(*) FILTER (WHERE is_anomaly = 1) AS total_anomaly_readings,

    COUNT(*) FILTER (WHERE is_sensor_dropout = 1) AS total_dropout_readings,

    COUNT(*) FILTER (
        WHERE pressure_bar IS NULL
           OR temp_celsius IS NULL
           OR flow_lpm IS NULL
           OR vibration_x_g IS NULL
           OR vibration_y_g IS NULL
           OR pump_rpm IS NULL
    ) AS total_missing_sensor_rows

FROM sensor_telemetry
GROUP BY
    machine_id,
    timestamp::date;

SELECT * FROM vw_daily_sensor_quality_summary


SELECT * FROM sensor_telemetry
LIMIT 10;