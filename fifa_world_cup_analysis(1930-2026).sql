-- =====================================================================
-- PROJECT: FIFA World Cup All Matches Analysis (1930-2026)
-- AUTHOR:  [Kunal]
-- GOAL:    Analyze 90+ years of World Cup match data to uncover trends
--          in scoring, team performance, and tournament history.
-- TOOLS:   MySQL, (later) Tableau/Power BI for dashboarding
-- =====================================================================
-- TABLE: fifa_table
-- Columns: match_id, world_cup_year, host_country, date, stage,
--          round_raw, `group`, team1, team2, halftime_score_team1,
--          halftime_score_team2, fulltime_score_team1, fulltime_score_team2,
--          extra_time_score_team1, extra_time_score_team2,
--          penalty_score_team1, penalty_score_team2, winner, result_method,
--          stadium, city, total_goals_team1, total_goals_team2
--
-- NOTE: `group` is a reserved word in MySQL -- always wrap it in
-- backticks (`group`) when referencing it, or it will throw a syntax error.
-- =====================================================================


-- =====================================================================
-- SECTION 1: SETUP
-- =====================================================================

USE fifa_world;


-- =====================================================================
-- SECTION 2: DATA EXPLORATION
-- Understand the raw data before touching anything.
-- =====================================================================

-- 2.1: Confirm table structure
DESCRIBE fifa_table;

-- 2.2: Preview first rows
SELECT *
FROM fifa_table
LIMIT 10;

-- 2.3: Total number of matches in the dataset
SELECT COUNT(*) AS total_matches
FROM fifa_table;

-- 2.4: Check for missing values in key columns
SELECT
    SUM(CASE WHEN team1 IS NULL THEN 1 ELSE 0 END)                AS missing_team1,
    SUM(CASE WHEN team2 IS NULL THEN 1 ELSE 0 END)                AS missing_team2,
    SUM(CASE WHEN fulltime_score_team1 IS NULL THEN 1 ELSE 0 END) AS missing_ft_score1,
    SUM(CASE WHEN fulltime_score_team2 IS NULL THEN 1 ELSE 0 END) AS missing_ft_score2,
    SUM(CASE WHEN winner IS NULL THEN 1 ELSE 0 END)               AS missing_winner
FROM fifa_table;

-- 2.5: Check for duplicate matches (same teams, same date)
SELECT team1, team2, date, COUNT(*) AS occurrences
FROM fifa_table
GROUP BY team1, team2, date
HAVING COUNT(*) > 1;

-- 2.6: Look at distinct team names to catch inconsistent naming
-- (e.g. "West Germany" vs "Germany", "USA" vs "United States")
SELECT DISTINCT team1
FROM fifa_table
ORDER BY team1;

-- 2.7: Check distinct values in `result_method` and `stage`
-- (helps understand penalty shootouts, extra time, group vs knockout stages)
SELECT DISTINCT result_method FROM fifa_table;
SELECT DISTINCT stage FROM fifa_table;


-- =====================================================================
-- SECTION 3: DATA CLEANING
-- =====================================================================

-- 3.1: Back up the table before making any changes
CREATE TABLE fifa_table_backup AS
SELECT * FROM fifa_table;

-- 3.2: Standardize historical team names into modern equivalents
-- (Only do this if your analysis treats them as the same nation --
-- otherwise skip, since "West Germany" is historically distinct)
UPDATE fifa_table
SET team1 = 'Germany'
WHERE team1 = 'West Germany';

UPDATE fifa_table
SET team2 = 'Germany'
WHERE team2 = 'West Germany';

-- 3.3: Trim stray whitespace from text columns (common CSV import issue)
UPDATE fifa_table
SET team1 = TRIM(team1),
    team2 = TRIM(team2),
    winner = TRIM(winner),
    host_country = TRIM(host_country);

-- 3.4: Standardize "Draw" / "Tie" labels in the winner column, if present
-- (adjust based on what SECTION 2.6/2.7 style checks reveal)
-- SELECT DISTINCT winner FROM fifa_table ORDER BY winner;


-- =====================================================================
-- SECTION 4: ANALYSIS QUERIES
-- Each query below answers a specific analyst-style business question.
-- =====================================================================

-- 4.1: Matches played per World Cup year
SELECT
    world_cup_year,
    COUNT(*) AS matches_played
FROM fifa_table
GROUP BY world_cup_year
ORDER BY world_cup_year;

-- 4.2: Average total goals per match, by year
-- Uses total_goals_team1 + total_goals_team2 (already provided in the table)
SELECT
    world_cup_year,
    ROUND(AVG(total_goals_team1 + total_goals_team2), 2) AS avg_goals_per_match
FROM fifa_table
GROUP BY world_cup_year
ORDER BY world_cup_year;

-- 4.3: Top 10 countries by total match wins (all-time)
-- Uses the "winner" column directly since the table already has it
SELECT
    winner,
    COUNT(*) AS total_wins
FROM fifa_table
WHERE winner IS NOT NULL
  AND winner NOT IN ('Draw', 'Tie')   -- adjust based on your actual draw label
GROUP BY winner
ORDER BY total_wins DESC
LIMIT 10;

-- 4.4: Best goal difference per tournament (window function)
-- Combines team1 and team2 rows into one "team perspective" table first
WITH team_goals AS (
    SELECT world_cup_year, team1 AS team,
           total_goals_team1 AS goals_for, total_goals_team2 AS goals_against
    FROM fifa_table
    UNION ALL
    SELECT world_cup_year, team2 AS team,
           total_goals_team2 AS goals_for, total_goals_team1 AS goals_against
    FROM fifa_table
),
team_totals AS (
    SELECT
        world_cup_year,
        team,
        SUM(goals_for - goals_against) AS goal_difference
    FROM team_goals
    GROUP BY world_cup_year, team
),
ranked AS (
    SELECT
        world_cup_year,
        team,
        goal_difference,
        RANK() OVER (PARTITION BY world_cup_year ORDER BY goal_difference DESC) AS rank_in_tournament
    FROM team_totals
)
SELECT world_cup_year, team, goal_difference
FROM ranked
WHERE rank_in_tournament = 1
ORDER BY world_cup_year;

-- 4.5: Host country advantage
-- Compares how often the host country wins matches they play in
SELECT
    host_country,
    COUNT(*) AS matches_as_host,
    SUM(CASE WHEN winner = host_country THEN 1 ELSE 0 END) AS wins_as_host,
    ROUND(SUM(CASE WHEN winner = host_country THEN 1 ELSE 0 END) / COUNT(*) * 100, 1) AS host_win_rate_pct
FROM fifa_table
WHERE team1 = host_country OR team2 = host_country
GROUP BY host_country
ORDER BY host_win_rate_pct DESC;

-- 4.6: Highest-scoring matches of all time
SELECT
    world_cup_year,
    team1,
    team2,
    fulltime_score_team1,
    fulltime_score_team2,
    (total_goals_team1 + total_goals_team2) AS total_goals
FROM fifa_table
ORDER BY total_goals DESC
LIMIT 10;

-- 4.7: Average goals per match, grouped by decade
-- Cleaner long-term trend line for a dashboard chart
SELECT
    FLOOR(world_cup_year / 10) * 10 AS decade,
    ROUND(AVG(total_goals_team1 + total_goals_team2), 2) AS avg_goals_per_match
FROM fifa_table
GROUP BY decade
ORDER BY decade;

-- 4.8: Matches decided by penalty shootout
-- Uses result_method to isolate the most dramatic games
SELECT
    world_cup_year,
    team1,
    team2,
    penalty_score_team1,
    penalty_score_team2,
    winner
FROM fifa_table
WHERE result_method = 'Penalties'   -- adjust to match actual value from 2.7
ORDER BY world_cup_year;

-- 4.9: Matches per stage (Group Stage, Round of 16, Quarter-final, etc.)
-- Useful for understanding tournament structure changes over the years
SELECT
    stage,
    COUNT(*) AS matches_played
FROM fifa_table
GROUP BY stage
ORDER BY matches_played DESC;

