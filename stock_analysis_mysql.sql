/* ==========================================================================
   STOCK MARKET ANALYSIS IN SQL  -  Eicher, Hero, Infosys, TCS, TVS
   Period : 2015-01-01 to 2018-07-31 (889 trading days per stock)
   Dialect: MySQL 8.0+
   Every CREATE TABLE is preceded by DROP TABLE IF EXISTS -> file is re-runnable.
   ========================================================================== */

/* ---- SETUP (MySQL): create DB and load the 6 CSVs (Appendix A of the guide) ----
   SET GLOBAL local_infile = 1;   -- and OPT_LOCAL_INFILE=1 in Workbench > Advanced
   Run the block below for tvs_motors, then repeat it for eicher_motors,
   hero_motocorp, infosys, tcs (change table name + file path). */
CREATE DATABASE IF NOT EXISTS stock_analysis;
USE stock_analysis;

DROP TABLE IF EXISTS tvs_motors;
CREATE TABLE tvs_motors (
  `date` DATE PRIMARY KEY,
  open_price DECIMAL(12,2), high_price DECIMAL(12,2), low_price DECIMAL(12,2),
  close_price DECIMAL(12,2), wap DECIMAL(16,4),
  no_of_shares BIGINT, no_of_trades BIGINT, total_turnover DECIMAL(20,2),
  deliverable_qty BIGINT, pct_deli_qty DECIMAL(6,2),
  spread_high_low DECIMAL(12,2), spread_close_open DECIMAL(12,2)
);
LOAD DATA LOCAL INFILE '/path/to/TVS_Motors.csv' INTO TABLE tvs_motors
FIELDS TERMINATED BY ',' LINES TERMINATED BY '\n' IGNORE 1 LINES
(@d,@o,@h,@l,@c,@w,@s,@tr,@to,@dq,@pd,@shl,@sco)
SET `date` = STR_TO_DATE(@d, '%d-%M-%Y'),
    open_price = NULLIF(@o,''), high_price = NULLIF(@h,''), low_price = NULLIF(@l,''),
    close_price = NULLIF(@c,''), wap = NULLIF(@w,''), no_of_shares = NULLIF(@s,''),
    no_of_trades = NULLIF(@tr,''), total_turnover = NULLIF(@to,''),
    deliverable_qty = NULLIF(@dq,''), pct_deli_qty = NULLIF(@pd,''),
    spread_high_low = NULLIF(@shl,''), spread_close_open = NULLIF(TRIM(@sco),'');
SELECT COUNT(*), MIN(`date`), MAX(`date`) FROM tvs_motors;  -- check: 889 rows


/* ==========================================================================
   PART 1 : GET TO KNOW THE DATA
   ========================================================================== */

-- Task 1 : history available in tvs_motors (TVS Motors is used as the single-stock case study) (889 days, 2015-01-01 -> 2018-07-31)
SELECT COUNT(*)  AS trading_days,
       MIN(date) AS first_day,
       MAX(date) AS last_day
FROM tvs_motors;

-- Task 2 : Eicher Motors' five best closing prices (all fall in Sept 2017)
SELECT date, close_price
FROM eicher_motors
ORDER BY close_price DESC
LIMIT 5;

-- Task 3 : TCS average close by year (NB: 2018 has only 7 months of data)
SELECT YEAR(date) AS year,
       ROUND(AVG(close_price), 2) AS avg_close
FROM tcs
GROUP BY YEAR(date)
ORDER BY year;

-- Task 4 : rows where deliverable_qty is NULL, across all six tables
SELECT 'eicher_motors' AS stock, date FROM eicher_motors WHERE deliverable_qty IS NULL
UNION ALL
SELECT 'hero_motocorp' AS stock, date FROM hero_motocorp WHERE deliverable_qty IS NULL
UNION ALL
SELECT 'infosys'       AS stock, date FROM infosys       WHERE deliverable_qty IS NULL
UNION ALL
SELECT 'tcs'           AS stock, date FROM tcs           WHERE deliverable_qty IS NULL
UNION ALL
SELECT 'tvs_motors'    AS stock, date FROM tvs_motors    WHERE deliverable_qty IS NULL;

/* ==========================================================================
   PART 2 : THE ASSIGNMENT
   ========================================================================== */

-- Task 5 : tvs1 = close + 20-day and 50-day simple moving averages
-- Frame "19 PRECEDING AND CURRENT ROW" = 20 rows (49 + 1 = 50 for ma50).
-- CASE blanks the first 19 / 49 rows: they do not have a full window yet.
DROP TABLE IF EXISTS tvs1;
CREATE TABLE tvs1 AS
SELECT
  date,
  close_price,
  CASE WHEN ROW_NUMBER() OVER (ORDER BY date) >= 20
       THEN ROUND(AVG(close_price) OVER (ORDER BY date ROWS BETWEEN 19 PRECEDING AND CURRENT ROW), 2)
  END AS ma20,
  CASE WHEN ROW_NUMBER() OVER (ORDER BY date) >= 50
       THEN ROUND(AVG(close_price) OVER (ORDER BY date ROWS BETWEEN 49 PRECEDING AND CURRENT ROW), 2)
  END AS ma50
FROM tvs_motors;

-- Task 6 : master_table = one row per date, closing price of each stock
DROP TABLE IF EXISTS master_table;
CREATE TABLE master_table AS
SELECT v.date,
       t.close_price AS tcs,
       v.close_price AS tvs,
       i.close_price AS infosys,
       e.close_price AS eicher,
       h.close_price AS hero
FROM tvs_motors v
JOIN tcs           t ON t.date = v.date
JOIN infosys       i ON i.date = v.date
JOIN eicher_motors e ON e.date = v.date
JOIN hero_motocorp h ON h.date = v.date;

-- Task 7 : tvs2 = golden-cross signals
--   Buy  : ma20 crosses ABOVE ma50 today (yesterday ma20 <= ma50)
--   Sell : ma20 crosses BELOW ma50 today (yesterday ma20 >= ma50)
--   Hold : every other day, incl. days where an average is NULL
-- (ma20 is non-NULL before ma50 is, so guarding ma50/prev_ma50 covers both.)
DROP TABLE IF EXISTS tvs2;
CREATE TABLE tvs2 AS
WITH t AS (
  SELECT date, close_price, ma20, ma50,
         LAG(ma20) OVER (ORDER BY date) AS prev_ma20,
         LAG(ma50) OVER (ORDER BY date) AS prev_ma50
  FROM tvs1
)
SELECT date, close_price,
  CASE
    WHEN ma50 IS NULL OR prev_ma50 IS NULL               THEN 'Hold'
    WHEN ma20 > ma50 AND prev_ma20 <= prev_ma50          THEN 'Buy'
    WHEN ma20 < ma50 AND prev_ma20 >= prev_ma50          THEN 'Sell'
    ELSE 'Hold'
  END AS `signal`
FROM t;

-- Task 8 : how often did each signal trigger? (Buy and Sell differ by at most 1)
SELECT `signal`, COUNT(*) AS days
FROM tvs2
GROUP BY `signal`
ORDER BY `signal`;

-- Task 9 : signal on a given day (query version; MySQL function version below)
SELECT `signal`
FROM tvs2
WHERE date = '2018-06-21';

-- Task 9 (MySQL) : reusable function. Returns NULL for non-trading days
-- (weekends/holidays) - a deliberate choice: "no row" = "market closed".
DROP FUNCTION IF EXISTS tvs_signal;
DELIMITER $$
CREATE FUNCTION tvs_signal(d DATE)
RETURNS VARCHAR(4) DETERMINISTIC READS SQL DATA
BEGIN
  DECLARE s VARCHAR(4);
  SELECT `signal` INTO s FROM tvs2 WHERE date = d;
  RETURN s;
END $$
DELIMITER ;
SELECT tvs_signal('2018-06-21') AS signal_on_2018_06_21;
SELECT tvs_signal('2015-05-18') AS check_should_be_Buy;

-- Task 10 : all six stocks in ONE query (no twelve tables needed)
--   prices -> ma (partitioned) -> lagged (partitioned) -> sig -> latest non-Hold
--   Unrounded averages, as the task asks.
WITH prices AS (
  SELECT 'Eicher Motors' AS stock, date, close_price FROM eicher_motors
  UNION ALL SELECT 'Hero Motocorp', date, close_price FROM hero_motocorp
  UNION ALL SELECT 'Infosys',       date, close_price FROM infosys
  UNION ALL SELECT 'TCS',           date, close_price FROM tcs
  UNION ALL SELECT 'TVS Motors',    date, close_price FROM tvs_motors
),
ma AS (
  SELECT stock, date, close_price,
         CASE WHEN ROW_NUMBER() OVER (PARTITION BY stock ORDER BY date) >= 20
              THEN AVG(close_price) OVER (PARTITION BY stock ORDER BY date
                                          ROWS BETWEEN 19 PRECEDING AND CURRENT ROW) END AS ma20,
         CASE WHEN ROW_NUMBER() OVER (PARTITION BY stock ORDER BY date) >= 50
              THEN AVG(close_price) OVER (PARTITION BY stock ORDER BY date
                                          ROWS BETWEEN 49 PRECEDING AND CURRENT ROW) END AS ma50
  FROM prices
),
lagged AS (
  SELECT *,
         LAG(ma20) OVER (PARTITION BY stock ORDER BY date) AS prev_ma20,
         LAG(ma50) OVER (PARTITION BY stock ORDER BY date) AS prev_ma50
  FROM ma
),
sig AS (
  SELECT stock, date, close_price,
    CASE
      WHEN ma50 IS NULL OR prev_ma50 IS NULL      THEN 'Hold'
      WHEN ma20 > ma50 AND prev_ma20 <= prev_ma50 THEN 'Buy'
      WHEN ma20 < ma50 AND prev_ma20 >= prev_ma50 THEN 'Sell'
      ELSE 'Hold'
    END AS `signal`
  FROM lagged
),
latest AS (
  SELECT stock, date, `signal`,
         ROW_NUMBER() OVER (PARTITION BY stock ORDER BY date DESC) AS rn
  FROM sig
  WHERE `signal` <> 'Hold'
)
SELECT s.stock,
       SUM(s.`signal` = 'Buy')  AS buys,
       SUM(s.`signal` = 'Sell') AS sells,
       l.date    AS last_signal_date,
       l.`signal`   AS last_signal
FROM sig s
JOIN latest l ON l.stock = s.stock AND l.rn = 1
GROUP BY s.stock, l.date, l.`signal`
ORDER BY s.stock;

/* ==========================================================================
   PART 3 : QUESTION THE RESULT
   ========================================================================== */

-- Task 11 : who went up? First vs last close (RAW prices - not yet adjusted)
WITH prices AS (
  SELECT 'Eicher Motors' AS stock, date, close_price FROM eicher_motors
  UNION ALL SELECT 'Hero Motocorp', date, close_price FROM hero_motocorp
  UNION ALL SELECT 'Infosys',       date, close_price FROM infosys
  UNION ALL SELECT 'TCS',           date, close_price FROM tcs
  UNION ALL SELECT 'TVS Motors',    date, close_price FROM tvs_motors
),
ends AS (
  SELECT stock, MIN(date) AS first_day, MAX(date) AS last_day
  FROM prices
  GROUP BY stock
)
SELECT e.stock,
       f.close_price AS first_close,
       l.close_price AS last_close,
       ROUND(100.0 * (l.close_price - f.close_price) / f.close_price, 1) AS pct_change
FROM ends e
JOIN prices f ON f.stock = e.stock AND f.date = e.first_day
JOIN prices l ON l.stock = e.stock AND l.date = e.last_day
ORDER BY pct_change DESC;

-- Task 12 : the data trap - each stock's single worst day (day-over-day % move)
-- TCS (2018-05-31) and Infosys (2015-06-15) show ~ -50%: that is NOT a crash,
-- it is a 1:1 BONUS ISSUE (shares double, price halves). Prices are unadjusted.
WITH prices AS (
  SELECT 'Eicher Motors' AS stock, date, close_price FROM eicher_motors
  UNION ALL SELECT 'Hero Motocorp', date, close_price FROM hero_motocorp
  UNION ALL SELECT 'Infosys',       date, close_price FROM infosys
  UNION ALL SELECT 'TCS',           date, close_price FROM tcs
  UNION ALL SELECT 'TVS Motors',    date, close_price FROM tvs_motors
),
moves AS (
  SELECT stock, date, close_price,
         100.0 * (close_price / LAG(close_price) OVER (PARTITION BY stock ORDER BY date) - 1) AS pct_move
  FROM prices
),
ranked AS (
  SELECT stock, date, close_price, pct_move,
         ROW_NUMBER() OVER (PARTITION BY stock ORDER BY pct_move ASC) AS rn
  FROM moves
  WHERE pct_move IS NOT NULL
)
SELECT stock, date, close_price, ROUND(pct_move, 1) AS pct_move
FROM ranked
WHERE rn = 1
ORDER BY pct_move;

-- Task 13 : fix it - adjust TCS and Infosys for the 1:1 bonus issues
--   TCS     : first day at the new price level = 2018-05-31
--   Infosys : first day at the new price level = 2015-06-15
-- Every price BEFORE the event date is divided by 2; on/after stays as is.
WITH adjusted AS (
  SELECT 'TCS' AS stock, date,
         CASE WHEN date < '2018-05-31' THEN close_price / 2 ELSE close_price END AS adj_close
  FROM tcs
  UNION ALL
  SELECT 'Infosys' AS stock, date,
         CASE WHEN date < '2015-06-15' THEN close_price / 2 ELSE close_price END AS adj_close
  FROM infosys
)
SELECT stock,
       ROUND(100.0 * (MAX(CASE WHEN date = '2018-07-31' THEN adj_close END)
                    / MAX(CASE WHEN date = '2015-01-01' THEN adj_close END) - 1), 1) AS adjusted_pct_change
FROM adjusted
WHERE date BETWEEN '2015-01-01' AND '2018-07-31'
GROUP BY stock
ORDER BY stock;

/* ==========================================================================
   BONUS (for the insights PDF)
   ========================================================================== */

-- B1 : corrected performance league table for ALL stocks (TCS & Infosys adjusted)
WITH prices AS (
  SELECT 'Eicher Motors' AS stock, date, close_price FROM eicher_motors
  UNION ALL SELECT 'Hero Motocorp', date, close_price FROM hero_motocorp
  UNION ALL SELECT 'Infosys',       date,
         CASE WHEN date < '2015-06-15' THEN close_price / 2 ELSE close_price END FROM infosys
  UNION ALL SELECT 'TCS',           date,
         CASE WHEN date < '2018-05-31' THEN close_price / 2 ELSE close_price END FROM tcs
  UNION ALL SELECT 'TVS Motors',    date, close_price FROM tvs_motors
),
ends AS (
  SELECT stock, MIN(date) AS first_day, MAX(date) AS last_day FROM prices GROUP BY stock
)
SELECT e.stock,
       ROUND(f.close_price, 2) AS first_close_adj,
       ROUND(l.close_price, 2) AS last_close_adj,
       ROUND(100.0 * (l.close_price - f.close_price) / f.close_price, 1) AS pct_change_adj
FROM ends e
JOIN prices f ON f.stock = e.stock AND f.date = e.first_day
JOIN prices l ON l.stock = e.stock AND l.date = e.last_day
ORDER BY pct_change_adj DESC;

-- B2 : stretch challenge - TCS signals on ADJUSTED prices vs ORIGINAL prices
--      'both' = signal exists in both runs, 'only_original' = created purely by
--      the price cliff (fake), 'only_adjusted' = only visible after correction.
WITH base AS (
  SELECT date, close_price AS raw_close,
         CASE WHEN date < '2018-05-31' THEN close_price / 2 ELSE close_price END AS adj_close
  FROM tcs
),
ma AS (
  SELECT date,
         CASE WHEN ROW_NUMBER() OVER (ORDER BY date) >= 20
              THEN AVG(raw_close) OVER (ORDER BY date ROWS BETWEEN 19 PRECEDING AND CURRENT ROW) END AS r20,
         CASE WHEN ROW_NUMBER() OVER (ORDER BY date) >= 50
              THEN AVG(raw_close) OVER (ORDER BY date ROWS BETWEEN 49 PRECEDING AND CURRENT ROW) END AS r50,
         CASE WHEN ROW_NUMBER() OVER (ORDER BY date) >= 20
              THEN AVG(adj_close) OVER (ORDER BY date ROWS BETWEEN 19 PRECEDING AND CURRENT ROW) END AS a20,
         CASE WHEN ROW_NUMBER() OVER (ORDER BY date) >= 50
              THEN AVG(adj_close) OVER (ORDER BY date ROWS BETWEEN 49 PRECEDING AND CURRENT ROW) END AS a50
  FROM base
),
lg AS (
  SELECT *,
         LAG(r20) OVER (ORDER BY date) AS pr20, LAG(r50) OVER (ORDER BY date) AS pr50,
         LAG(a20) OVER (ORDER BY date) AS pa20, LAG(a50) OVER (ORDER BY date) AS pa50
  FROM ma
),
s AS (
  SELECT date,
    CASE WHEN r50 IS NULL OR pr50 IS NULL THEN 'Hold'
         WHEN r20 > r50 AND pr20 <= pr50  THEN 'Buy'
         WHEN r20 < r50 AND pr20 >= pr50  THEN 'Sell' ELSE 'Hold' END AS raw_sig,
    CASE WHEN a50 IS NULL OR pa50 IS NULL THEN 'Hold'
         WHEN a20 > a50 AND pa20 <= pa50  THEN 'Buy'
         WHEN a20 < a50 AND pa20 >= pa50  THEN 'Sell' ELSE 'Hold' END AS adj_sig
  FROM lg
)
SELECT date, raw_sig AS original_signal, adj_sig AS adjusted_signal,
       CASE WHEN raw_sig = adj_sig THEN 'both'
            WHEN raw_sig <> 'Hold' AND adj_sig = 'Hold' THEN 'only_original (fake)'
            WHEN raw_sig = 'Hold' AND adj_sig <> 'Hold' THEN 'only_adjusted'
            ELSE 'conflict' END AS comparison
FROM s
WHERE raw_sig <> 'Hold' OR adj_sig <> 'Hold'
ORDER BY date;

-- B3 : whipsaw check - consecutive signals (Buy->Sell or Sell->Buy) within
--      30 trading days of each other, per stock (raw prices, unrounded MAs).
WITH prices AS (
  SELECT 'Eicher Motors' AS stock, date, close_price FROM eicher_motors
  UNION ALL SELECT 'Hero Motocorp', date, close_price FROM hero_motocorp
  UNION ALL SELECT 'Infosys',       date, close_price FROM infosys
  UNION ALL SELECT 'TCS',           date, close_price FROM tcs
  UNION ALL SELECT 'TVS Motors',    date, close_price FROM tvs_motors
),
ma AS (
  SELECT stock, date, close_price,
         ROW_NUMBER() OVER (PARTITION BY stock ORDER BY date) AS idx,
         CASE WHEN ROW_NUMBER() OVER (PARTITION BY stock ORDER BY date) >= 20
              THEN AVG(close_price) OVER (PARTITION BY stock ORDER BY date ROWS BETWEEN 19 PRECEDING AND CURRENT ROW) END AS ma20,
         CASE WHEN ROW_NUMBER() OVER (PARTITION BY stock ORDER BY date) >= 50
              THEN AVG(close_price) OVER (PARTITION BY stock ORDER BY date ROWS BETWEEN 49 PRECEDING AND CURRENT ROW) END AS ma50
  FROM prices
),
lagged AS (
  SELECT *, LAG(ma20) OVER (PARTITION BY stock ORDER BY date) AS prev_ma20,
            LAG(ma50) OVER (PARTITION BY stock ORDER BY date) AS prev_ma50
  FROM ma
),
sig AS (
  SELECT stock, date, idx, close_price,
    CASE WHEN ma50 IS NULL OR prev_ma50 IS NULL THEN 'Hold'
         WHEN ma20 > ma50 AND prev_ma20 <= prev_ma50 THEN 'Buy'
         WHEN ma20 < ma50 AND prev_ma20 >= prev_ma50 THEN 'Sell' ELSE 'Hold' END AS `signal`
  FROM lagged
),
trades AS (
  SELECT stock, date, idx, close_price, `signal`,
         LAG(`signal`)       OVER (PARTITION BY stock ORDER BY date) AS prev_sig,
         LAG(idx)         OVER (PARTITION BY stock ORDER BY date) AS prev_idx,
         LAG(close_price) OVER (PARTITION BY stock ORDER BY date) AS prev_close
  FROM sig
  WHERE `signal` <> 'Hold'
)
SELECT stock,
       COUNT(*) AS quick_reversals,
       ROUND(AVG(CASE WHEN prev_sig = 'Buy' THEN 100.0 * (close_price - prev_close) / prev_close
                      ELSE 100.0 * (prev_close - close_price) / prev_close END), 2) AS avg_pct_result_of_following_first_signal
FROM trades
WHERE prev_sig IS NOT NULL AND prev_sig <> `signal` AND idx - prev_idx <= 30
GROUP BY stock
ORDER BY stock;
