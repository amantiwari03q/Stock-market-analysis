# Stock Market Analysis in SQL

Moving averages, golden-cross trading signals, and a data-quality trap, on five NSE stocks (January 2015 to July 2018), built entirely in SQL.

**Stocks:** Eicher Motors, Hero MotoCorp, Infosys, TCS, TVS Motors
**Period:** 1 Jan 2015 to 31 Jul 2018 (889 trading days per stock)
**Tools:** MySQL 8 (SQLite-compatible version included), window functions, CTEs

---

## Dataset

The raw CSV files are available here:

**[Download the data (Google Drive)](https://drive.google.com/drive/folders/1spSKaZPvXVNjcC7MCSrJ3jMGwHR7gpQo)**

Each file has one row per trading day with the same 13 columns:

| Column | Meaning |
|---|---|
| `date` | Trading day |
| `open_price`, `high_price`, `low_price`, `close_price` | Prices in rupees (this project uses `close_price`) |
| `wap` | Weighted average price for the day |
| `no_of_shares`, `no_of_trades` | Volume and number of trades |
| `total_turnover` | Value traded in rupees |
| `deliverable_qty`, `pct_deli_qty` | Delivered shares, and as % of shares traded |
| `spread_high_low`, `spread_close_open` | High minus low, close minus open |

---

## Repository contents

| File | Description |
|---|---|
| `stock_analysis_mysql.sql` | Full analysis for MySQL 8.0+, including database setup, CSV loading and a reusable function |
| `stock_analysis_sqlite.sql` | Same analysis for SQLite 3.25+ (for online playgrounds) |
| `Stock_Analysis_Insights_Report.pdf` | Insights report: claims, evidence and caveats |
| `README.md` | This file |

---

## How to run

### MySQL
1. Download the CSVs from the Drive link above.
2. Enable local file loading: `SET GLOBAL local_infile = 1;` (and `OPT_LOCAL_INFILE=1` in the Workbench connection settings).
3. Open `stock_analysis_mysql.sql`. In the setup block, replace `/path/to/TVS_Motors.csv` with your real path, and repeat the `CREATE TABLE` + `LOAD DATA` block for the other four CSVs (`eicher_motors`, `hero_motocorp`, `infosys`, `tcs`).
4. Run the file top to bottom. Every `CREATE TABLE` is preceded by `DROP TABLE IF EXISTS`, so it can be re-run safely.

The loader converts dates such as `31-July-2018` into real `DATE` values and turns empty cells into `NULL`.

### SQLite
Load each CSV into a table with the same names, with dates stored as `YYYY-MM-DD`, then run `stock_analysis_sqlite.sql`.

---

## What the SQL does

| Part | Task | Technique |
|---|---|---|
| 1. Explore | History range, top closes, yearly averages, NULL check | `COUNT`, `MIN/MAX`, `GROUP BY`, `UNION ALL`, `IS NULL` |
| 2. Build | 20-day and 50-day moving averages (`tvs1`) | `AVG() OVER`, `ROWS BETWEEN`, `ROW_NUMBER`, `CASE` |
| | Master table of all closing prices | multi-table `JOIN` |
| | Golden-cross Buy/Sell/Hold signals (`tvs2`) | `LAG`, CTE, multi-condition `CASE` |
| | Signal on a given date | `WHERE`, MySQL `CREATE FUNCTION` |
| | All five stocks in one query | `PARTITION BY`, chained CTEs, latest-row-per-group |
| 3. Question | Who went up? | self-join, arithmetic |
| | Find each stock's worst day (the data trap) | `LAG` with `PARTITION BY`, ranking |
| | Adjust prices for bonus issues | `CASE` in a CTE, conditional aggregation |
| Bonus | Corrected league table, raw vs adjusted signals, whipsaw check, follow-the-signals result | window functions, `LEAD`, `EXP/LN` |

**Signal rule:** Buy on the day the 20-day average crosses above the 50-day average; Sell on the day it crosses below; Hold otherwise (including days with NULL averages).

---

## Key findings

- **Two raw price series were wrong.** TCS (31 May 2018) and Infosys (15 Jun 2015) each show a fall of about 50% in one day. These are 1:1 bonus issues, not crashes.
- **Adjusted returns:** TVS +86.9%, Eicher +82.6%, TCS +52.4%, Infosys +38.2%, Hero +6.0%. On raw prices TCS and Infosys looked like losers (-23.8% and -30.9%).
- **The bonus-issue cliff creates false signals.** TCS's raw-data Sell on 5 Jun 2018 does not exist on adjusted prices; its real latest signal is a Buy (20 Apr 2018).
- **The golden-cross rule did not beat buy-and-hold on four of five stocks.** Following the signals lost money on Hero (-16.3%) and TCS (-22.4%).
- **Signals whipsaw.** 36 of 91 signals came within 30 trading days of the previous opposite signal; following the first of each pair lost about 5 to 7% on average.

See the PDF report for the full evidence and caveats behind each claim.

---

## Limitations

- Prices only: no dividends, brokerage, taxes or slippage.
- No market index or news data, so stock-specific and market-wide moves cannot be separated.
- Only about 3.5 years of data and 13 to 24 signals per stock, so averages are fragile.
- Bonus-issue dates were identified from the size of the price jump (a 1:1 ratio is assumed) and should be verified against company announcements.
- Volatility, drawdown and 12-month return in the report were cross-checked in Python rather than SQL.

> This is a coursework project, not investment advice.

---

## Author

**Aman Tiwari**
Video walkthrough: _add link here_
