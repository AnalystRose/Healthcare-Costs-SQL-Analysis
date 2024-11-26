

-- ENRICHING THE DATA
-- creating secondary tables so original data isnt corrupted
SELECT *
INTO hospitalgeneralinfo_analysis 
FROM hospital_general_info;

EXEC sp_rename 'hospitalgeneralinfo_analysis.emergency_services_TRUE', 'provider_id', 'COLUMN'

SELECT *
INTO inpatient2011_analysis 
FROM dbo.inpatient_2011;

SELECT *
INTO inpatient2012_analysis 
FROM dbo.inpatient2012;

SELECT *
INTO inpatient2013_analysis 
FROM dbo.inpatient2013;

SELECT *
INTO outpatient2011_analysis 
FROM dbo.outpatient2011;

SELECT *
INTO outpatient2012_analysis 
FROM dbo.outpatient2012;

SELECT *
INTO outpatient2013_analysis 
FROM dbo.outpatient2013;



-- using VIEWS to consolidate outpatient and inpatient data into 2 single tables using VIEWS, and adding a distinctive YEAR column

GO
CREATE VIEW outpatient_data AS
SELECT *, '2011' AS year FROM outpatient2011_analysis
UNION ALL
SELECT *, '2012' FROM outpatient2012_analysis
UNION ALL
SELECT *, '2013' FROM outpatient2013_analysis;
GO


GO
CREATE VIEW inpatient_data AS
SELECT *, '2011' AS year FROM inpatient2011_analysis
UNION ALL
SELECT *, '2012' FROM inpatient2012_analysis
UNION ALL
SELECT *, '2013' FROM inpatient2013_analysis;
GO




--EXPLORATORY DATA ANALYSIS


-- 1. RANKING OUTPATIENT AND INPATIENT CHARGES PER PROVIDER OVER 2011,2012,2013
-- populating the average outpatient charges [plus copayments] ranked per provider for years 2011, 2012, 2013
SELECT 
    provider_id,
    provider_name,
	provider_state,
    year,
    RANK() OVER(PARTITION BY year ORDER BY AVG(average_total_payments) DESC) AS payment_rank,
    AVG(average_total_payments) AS avg_outpatient_charges
FROM outpatient_data
--WHERE provider_id = 670005 -- Allows for analysis for the same provider overtime
GROUP BY provider_id, provider_name, provider_state, year;

-- populating the average inpatient charges [medicare] ranked per provider for years 2011, 2012, 2013
SELECT 
    provider_id,
    provider_name,
	provider_state,
    year,
    RANK() OVER(PARTITION BY year ORDER BY AVG(average_medicare_payments) DESC) AS payment_rank,
    AVG(average_medicare_payments) AS avg_medicare_charges
FROM inpatient_data
--WHERE provider_id = 330009 -- Allows for analysis for the same provider overtime
GROUP BY provider_id, provider_name, provider_state, year;



-- 2. A TIME SERIES ANALYSIS ON AVG CHARGE ON APC SERVICES PER PROVIDER OVER 2011,2012,2013
SELECT provider_id, provider_name, provider_state,
    apc,
    year,
    SUM(average_estimated_submitted_charges) AS avg_apc_charge
FROM outpatient_data
-- WHERE apc = '0019 - Level I Excision/ Biopsy' AND provider_id = 10001 AND year = 2013 -- Allows for tracking of charges for particular apc services by same provider overtime
GROUP BY provider_id, provider_name, provider_state, apc, year
ORDER BY year



-- 3. GEOGRAPHICAL ANALYSIS OF PROVIDERS WHO OFFER AFFORDABLE EMERGENCY CHARGES
--  JOINING the 3 tables [general hospital info, inpatient, and outpatient] and creating a VIEW
GO
CREATE VIEW all_hospital_data AS
SELECT 
    h.provider_id,
    h.hospital_name,
    h.state AS provider_state,
    h.city AS provider_city,
	h.emergency_services_TRUE_2,
    i.total_discharges AS inpatient_discharges,
    i.average_total_payments AS inpatient_avg_payments,
    i.average_medicare_payments AS inpatient_medicare_payments,
    o.outpatient_services,
    o.average_total_payments AS outpatient_avg_payments,
    o.average_estimated_submitted_charges AS outpatient_estimated_charges
FROM 
    hospitalgeneralinfo_analysis h
LEFT JOIN 
    inpatient_data i ON h.provider_id = i.provider_id
LEFT JOIN 
    outpatient_data o ON h.provider_id = o.provider_id;
GO

SELECT *
FROM all_hospital_data



 -- Which provider offers Emergency Services, is AFFORDABLE?
SELECT
    provider_id, provider_state, hospital_name, emergency_services_TRUE_2, inpatient_avg_payments, outpatient_avg_payments,
	CASE
		WHEN inpatient_avg_payments < 5000.00 THEN 'Affordable'
		WHEN emergency_services_TRUE_2 = 'FALSE' THEN 'No Emergency Services'
		WHEN inpatient_avg_payments IS NULL THEN 'Charges Not Publicized'
		ELSE 'Costly'
	END AS inpatient_emergency_affordability,
	CASE
		WHEN outpatient_avg_payments < 300.00 THEN 'Affordable'
		WHEN emergency_services_TRUE_2 = 'FALSE' THEN 'No Emergency Services'
		WHEN outpatient_avg_payments IS NULL THEN 'Charges Not Publicized'
		ELSE 'Costly'
	END AS outpatient_emergency_affordability
FROM all_hospital_data
WHERE 
    (inpatient_avg_payments < 5000.00 OR outpatient_avg_payments < 300.00) -- Condition for either inpatient or outpatient being affordable

    OR
    (inpatient_avg_payments < 5000.00 AND outpatient_avg_payments < 300.00); -- Condition for both being affordable



-- 4. PROMINENCE OF INPATIENT ICD10 DIAGNOSES STATE_WISE
-- CODE 1
SELECT TOP 10 provider_state, icd_category, 
COUNT(icd_category) AS Number_of_icd_diagnoses
FROM inpatient_data
WHERE provider_state = 'UT' -- Allows selection fo different states
GROUP BY provider_state, icd_category
ORDER BY 3 DESC

-- CODE 2
WITH ranked_diagnoses AS (
    SELECT 
        provider_state,
        icd_category,
        COUNT(icd_category) AS diagnosis_count,
        ROW_NUMBER() OVER(PARTITION BY provider_state ORDER BY COUNT(icd_category) DESC) AS row_num
    FROM inpatient_data
    GROUP BY provider_state, icd_category
)
SELECT 
    provider_state,
    icd_category,
    diagnosis_count,
	row_num
FROM ranked_diagnoses
WHERE row_num <= 10 -- AND provider_state = 'UT' -- Limits output to 10 and allows selection of different states
ORDER BY provider_state, row_num


-- 6. OVERALL CHARGES 
-- Total Inpatient and Outpatient Charges over the 3 years
WITH inpatient_totals AS (
    SELECT
        year,
		SUM(total_discharges * (average_total_payments + average_medicare_payments)) AS total_inpatient_charges
    FROM inpatient_data
	GROUP BY year
),
outpatient_totals AS (
    SELECT 
        year,
		SUM(outpatient_services * (average_total_payments)) AS total_outpatient_charges
    FROM outpatient_data
	GROUP BY year
)
SELECT 
	i.year,
	i.total_inpatient_charges,
    o.total_outpatient_charges
FROM inpatient_totals i
JOIN outpatient_totals o ON i.year = o.year



-- 7. What is the most expensive/affordable state to be treated in?	
SELECT 
    TOP 1 provider_state,
    AVG(inpatient_avg_payments) AS avg_inpatient_cost,
    AVG(outpatient_avg_payments) AS avg_outpatient_cost,
    (AVG(inpatient_avg_payments) + AVG(outpatient_avg_payments)) / 2 AS avg_total_cost
FROM all_hospital_data
GROUP BY provider_state
ORDER BY avg_total_cost DESC
-- Returns the most expensive state

SELECT TOP 1 
    provider_state,
    AVG(inpatient_avg_payments) AS avg_inpatient_cost,
    AVG(outpatient_avg_payments) AS avg_outpatient_cost,
    (AVG(inpatient_avg_payments) + AVG(outpatient_avg_payments)) / 2 AS avg_total_cost
FROM all_hospital_data
WHERE inpatient_avg_payments IS NOT NULL AND outpatient_avg_payments IS NOT NULL
GROUP BY provider_state
ORDER BY avg_total_cost ASC
-- Returns the most affordable state

