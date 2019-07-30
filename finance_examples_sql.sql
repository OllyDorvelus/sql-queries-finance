-- OLIVIER DORVELUS
/*
1.	Current_Shareholder_Shares – Two queries are provided in QueriesProvided.sql.  Both of these queries list shareholder id, 
shareholder type, stock id, and the total shares currently held by the shareholder.  Create a view called CURRENT_SHAREHOLDER_SHARES
using the more efficient query and include the view in your script.  Please place a comment explaining why you chose the query.

*/

SELECT 
   nvl(buy.buyer_id, sell.seller_id) AS shareholder_id,
   sh.type,
   nvl(buy.stock_id, sell.stock_id) AS  stock_id, 
   CASE nvl(buy.buyer_id, sell.seller_id)
      WHEN c.company_id THEN NULL
      ELSE nvl(buy.shares,0) - nvl(sell.shares,0)
   END AS shares
FROM (SELECT 
        t_sell.seller_id,
        t_sell.stock_id,
      sum(t_sell.shares) AS shares
      FROM trade t_sell
      WHERE t_sell.seller_id IS NOT NULL
      GROUP BY t_sell.seller_id, t_sell.stock_id) sell
  FULL OUTER JOIN
     (SELECT 
        t_buy.buyer_id,  
        t_buy.stock_id,
        sum(t_buy.shares) AS shares
      FROM trade t_buy
      WHERE t_buy.buyer_id IS NOT NULL
      GROUP BY t_buy.buyer_id, t_buy.stock_id) buy
   ON sell.seller_id = buy.buyer_id
   AND sell.stock_id = buy.stock_id
  JOIN shareholder sh
    ON sh.shareholder_id = nvl(buy.buyer_id, sell.seller_id)
  JOIN company c
    ON c.stock_id = nvl(buy.stock_id, sell.stock_id)
WHERE nvl(buy.shares,0) - nvl(sell.shares,0) != 0
ORDER BY 1,3
;
--The # of consistent gets for the first query was significantly less than the second one
-- The first query has consitent gets of 20-24 and the second had 1156-1160 making the first a better performing query.
/*
2.	Current_Stock_Stats – These queries list each stock id, the number of shares currently authorized, and the total number of 
shares currently outstanding. Create a view called CURRENT_STOCK_STATS using the more efficient query and include it in your 
script.  Please place a comment explaining why you chose the query.
*/

CREATE OR REPLACE VIEW current_stock_stats AS
SELECT
  co.stock_id,
  si.authorized current_authorized,
  SUM(DECODE(t.seller_id,co.company_id,t.shares)) 
    -NVL(SUM(CASE WHEN t.buyer_id = co.company_id 
             THEN t.shares END),0) AS total_outstanding
FROM company co
  INNER JOIN shares_authorized si
     ON si.stock_id = co.stock_id
    AND si.time_end IS NULL
  LEFT OUTER JOIN trade t
      ON t.stock_id = co.stock_id
GROUP BY co.stock_id, si.authorized
ORDER BY stock_id
;

--The # of consistent gets for the first query was significantly more than the second one
-- The first query has consitent gets of 94 and the second had 16 making the second a better performing query.
/*

3
Write a query which lists the name of every company that has authorized stock, the number of shares currently authorized, 
the total shares currently outstanding, and % of authorized shares that are outstanding.
Shares outstanding is the number of shares owned by external share holders.  
Shares_Authorized = Shares_Outstanding + Shares_UnIssued
*/

SELECT
  comp.name,
  css.current_authorized,
  css.total_outstanding,
  ROUND( (css.total_outstanding / css.current_authorized) * 100, 2) AS "Shares Outstanding Percent"
FROM company comp
  JOIN current_stock_stats css
    ON css.stock_id = comp.stock_id
   
/*
4.	For every direct holder: list the name of the holder, the names of the companies invested in by this direct holder, 
number of shares currently held, % this holder has of the shares outstanding, and % this holder has of the 
total authorized shares.  Sort the output by direct holder last name, first name, and company name and display the percentages to 
two decimal places.
*/

SELECT
  dh.first_name,
  dh.last_name,
  comp.name,
  dh_shares.shares,
  ROUND( (dh_shares.shares / css.total_outstanding) * 100,  2) AS "Outstanding Percent",
  ROUND( (dh_shares.shares / css.current_authorized) * 100, 2) AS "Authroized Percent"
FROM shareholder sh
  JOIN direct_holder dh
    ON sh.shareholder_id = dh.direct_holder_id
  JOIN current_shareholder_shares dh_shares
    ON dh.direct_holder_id = dh_shares.shareholder_id
  JOIN company comp
    ON comp.stock_id = dh_shares.stock_id
  JOIN current_stock_stats css
    ON css.stock_id = dh_shares.stock_id
  ORDER BY dh.last_name, dh.first_name, comp.name
  
/*
5.	For every institutional holder (companies who hold stock): list the name of the holder, the names of the companies invested in 
by this holder, shares currently held, % this holder has of the total shares outstanding, and % this holder has of that total 
authorized shares.  For this report, include only the external holders (not treasury shares).  Sort the output by holder name, 
and company owned name and display the percentages to two decimal places.
*/  

SELECT
 comp_sh.name AS "Share Holder",
 comp_stock.name AS "Company Name",
 sh.shares,
 ROUND( (sh.shares / css.total_outstanding) * 100,  2) AS "Outstanding Percent",
 ROUND( (sh.shares / css.current_authorized) * 100, 2) AS "Authroized Percent" 
  from current_shareholder_shares sh
    JOIN current_stock_stats css
      ON css.stock_id = sh.stock_id
    JOIN company comp_sh
      ON comp_sh.company_id = sh.shareholder_id
    JOIN company comp_stock
      ON comp_stock.stock_id = sh.stock_id
    WHERE shares IS NOT NULL
    ORDER BY comp_sh.name, comp_stock.name  
/*
6.	Write a query which displays all trades where more than 50000 shares were traded on the secondary markets.  
Please include the trade id, stock symbol, name of the company being traded, stock exchange symbol, number of shares traded, 
price total (including broker fees) and currency symbol. 
*/

SELECT
  tr.trade_id,
  sl.stock_symbol,
  comp.name,
  se.symbol,
  tr.shares,
  tr.price_total,
  curr.symbol
FROM trade tr
  JOIN stock_exchange se
    ON se.stock_ex_id = tr.stock_ex_id
  JOIN company comp
    ON comp.stock_id = tr.stock_id
  JOIN stock_listing sl
    ON sl.stock_id = tr.stock_id
    AND sl.stock_ex_id = tr.stock_ex_id
  JOIN currency curr
    ON curr.currency_id = se.currency_id
  WHERE tr.shares > 50000
  
/*
7.	For each stock listed on each stock exchange, display the exchange name, stock symbol and the date and time when that 
the stock was last traded. Sort the output by stock exchange name, stock symbol.  If a stock has not been traded show the 
exchange name, stock symbol and null for the date and time.
*/
SELECT
  se.name,
  sl.stock_symbol,
  comp.name,
  MAX(tr.transaction_time) AS "Latest Trade Date"
FROM trade tr
  RIGHT JOIN stock_listing sl
    ON sl.stock_ex_id = tr.stock_ex_id
    AND sl.stock_id = tr.stock_id
  RIGHT JOIN stock_exchange se
    ON se.stock_ex_id = sl.stock_ex_id
  JOIN company comp
    ON comp.stock_id = tr.stock_id
  GROUP BY se.name, sl.stock_symbol, comp.name
  ORDER BY se.name, sl.stock_symbol
/*
8.	Display the trade_id, name of the company and number of shares for the single largest trade made on any secondary market 
(in terms of the number of shares traded).  Unless there are multiple trades with the same number of shares traded, 
only one record should be returned.
*/
SELECT
  tr.trade_id,
  comp.name,
  tr.shares
FROM trade tr
  JOIN company comp
    ON comp.stock_id = tr.stock_id
  JOIN stock_exchange se
    ON se.stock_ex_id = tr.stock_ex_id
  WHERE tr.shares = (SELECT
      MAX(shares)
      FROM trade WHERE stock_ex_id IS NOT NULL --or you can join on stock_exchange
  )  
  /*
9.	Add “Jeff Adams” as a new direct holder.  You will have to insert a record into the shareholder table and make a 
separate statement to insert into the direct_holder table.
*/
INSERT INTO shareholder (shareholder_id, type)
  VALUES (26, 'Direct_Holder')
  
INSERT INTO direct_holder (direct_holder_id, first_name, last_name)
  VALUES (26, 'Jeff', 'Adams')
  /*
10.	Add “Makoto Investing” as a new institutional holder that has its head office in Tokyo, Japan.  Makoto does not currently 
have a stock id.  A record must be inserted into the shareholder table and a corresponding record must be inserted into the 
company table.
*/
INSERT INTO shareholder (shareholder_id, type)
  VALUES (27, 'Company')
 
INSERT INTO company (company_id, name, place_id)
  VALUES (27, 'Makoto Investing', 4)    
/*
11.	“Makoto Investing” would like to declare stock.  As of today’s date, they are authorizing 100,000 shares at a starting price of 
50 yen. To complete the work, you will need to update the company table to give Makoto its own stock id, and insert a new entry 
in the shares_authorized table.
*/
UPDATE company
  SET stock_id = 9,
      starting_price = 50,
      currency_id = 5
WHERE name = 'Makoto Investing'
INSERT INTO shares_authorized (stock_id, time_start, authorized)
  VALUES (9, sysdate, 100000)
  
/*
12. “Makoto Investing” would like to list on the Tokyo Stock Exchange under the stock symbol “Makoto”.  You will need to insert 
into the stock_listing table and the stock_price table.
*/

INSERT INTO stock_listing (stock_id, stock_ex_id, stock_symbol)
  VALUES (9, 4, 'Makoto')
  
INSERT INTO stock_price (stock_id, stock_ex_id, price, time_start)
  VALUES (9, 4, 50.00, sysdate)

/*
13.	Write a PL/SQL procedure called INSERT_DIRECT_HOLDER which will be used to insert new direct holders.  
Create a sequence object on the database to automatically generate shareholder_ids.  Use this sequence in your procedure.
-Input parameters: first_name, last_name

*/
DROP SEQUENCE shareholder_id_seq
CREATE SEQUENCE shareholder_id_seq
    START WITH 28
    INCREMENT BY 1
    
CREATE OR REPLACE PROCEDURE insert_direct_holder 
  (p_first_name IN DIRECT_HOLDER.FIRST_NAME%TYPE, 
   p_last_name IN DIRECT_HOLDER.LAST_NAME%TYPE)
  
IS
    v_shareholder_id Number(6);     
BEGIN
    v_shareholder_id := shareholder_id_seq.NEXTVAL;
    
    INSERT INTO shareholder (shareholder_id, type)
        VALUES(v_shareholder_id, 'Direct_Holder');
        
    INSERT INTO direct_holder (direct_holder_id, first_name, last_name)
        VALUES (v_shareholder_id, p_first_name, p_last_name);
    
END insert_direct_holder; 
/

exec insert_direct_holder('Olivier', 'Dorvelddddus')

/*
14.	Write a PL/SQL procedure called INSERT_COMPANY which will be used to insert new companies. The stock_id for new companies will be null.  
Use the sequence object that you created in problem 13 to get new shareholder_ids. 
-Input parameters: company_name, city, country
*/

CREATE OR REPLACE PROCEDURE insert_company
    (p_name IN COMPANY.NAME%TYPE,
     p_city IN PLACE.CITY%TYPE,
     p_country IN  PLACE.COUNTRY%TYPE)
IS
    v_place_id NUMBER(6);
    v_shareholder_id NUMBER(6);
BEGIN
   
    
    SELECT place_id INTO v_place_id 
        FROM place WHERE city = p_city AND country = p_country;
        
    v_shareholder_id := shareholder_id_seq.NEXTVAL; 
    
    INSERT INTO shareholder (shareholder_id, type)
        VALUES(v_shareholder_id, 'Company');
        
    INSERT INTO company (company_id, name, place_id)
        VALUES (v_shareholder_id, p_name, v_place_id);
        
EXCEPTION 
    WHEN NO_DATA_FOUND THEN RAISE_APPLICATION_ERROR(-20101, 'No matching city/country found');
    
END insert_company;
/

exec insert_company('Visumic', 'New York', 'USA')

/*
15.	Write a PL/SQL procedure called DECLARE_STOCK which will be used when a company declares it is issuing shares.
-Input parameters: company name, number of shares authorized, starting price (in the designated currency), and currency name. 
-Check to ensure the company has not already been given a stock id.
-If the company already has a stock id then do not perform any data changes.
-Otherwise, the company must be assigned a stock id (create a sequence object to generate new stock_ids) and the date of issue (current system date), number of shares authorized, the starting price and currency id must be recorded.
*/

CREATE SEQUENCE stock_id_seq
    START WITH 10
    INCREMENT BY 1
 DROP SEQUENCE stock_id_seq
 
CREATE OR REPLACE PROCEDURE declare_stock(
    p_company_name IN COMPANY.NAME%TYPE,
    p_shares_authorized IN SHARES_AUTHORIZED.AUTHORIZED%TYPE,
    p_starting_price IN COMPANY.STARTING_PRICE%TYPE,
    p_currency_name IN CURRENCY.NAME%TYPE)
IS
    v_stock_id NUMBER(6);
    v_company_id NUMBER(6);
    v_currency_id NUMBER(6);
    v_row_count NUMBER(6);
BEGIN

    SELECT count(*) INTO v_row_count
      FROM company WHERE name = p_company_name;
    
    IF v_row_count = 0 THEN
      RAISE_APPLICATION_ERROR(-20101, 'There is no matching company');
    END IF;
    
    SELECT company_id INTO v_company_id
        FROM company WHERE name = p_company_name;          
        
    SELECT count(*) INTO v_row_count
      FROM currency WHERE name = p_currency_name;  
      
    IF v_row_count = 0 THEN
        RAISE_APPLICATION_ERROR(-20101, 'There is no matching currency');
    END IF;    
    
    SELECT currency_id INTO v_currency_id
        FROM currency WHERE name = p_currency_name;
              
    SELECT stock_id INTO v_stock_id 
        FROM company WHERE company_id = v_company_id;
    
    IF v_stock_id IS NOT NULL THEN
        RAISE_APPLICATION_ERROR(-20101, 'Company already has a stock id');
    END IF;    
    
    v_stock_id := stock_id_seq.NEXTVAL;
    
    UPDATE company
        SET stock_id = v_stock_id,
            starting_price = p_starting_price,
            currency_id = v_currency_id
            WHERE company_id = v_company_id;

    INSERT INTO shares_authorized (stock_id, time_start, authorized)
        VALUES (v_stock_id, sysdate, p_shares_authorized);
 
END declare_stock;
/

exec declare_stock('Google', 5000, 50, 'Yen')
exec declare_stock('RBSsssss', 5000, 29.99, 'Yen')
exec declare_stock('RBS', 5000, 29.99, 'Yennnnn')
exec declare_stock('RBS', 5000, 29.99, 'Yen')

/*
16.	Write a PL/SQL procedure called LIST_STOCK which will be used when stock is listed on a stock exchange.
-Input parameters: stock_id, stock_ex_id, stock_symbol.
-The stock_id, stock_ex_id and stock_symbol must be recorded in the stock_listing table.
-The starting price from company must be copied to the stock price list for the stock exchange.  The current system time will be used for the time_start and the time_end will be null.  
The procedure must be able to convert currencies as needed.
*/

CREATE OR REPLACE PROCEDURE list_stock (
    p_stock_id IN COMPANY.STOCK_ID%TYPE,
    p_stock_ex_id IN STOCK_EXCHANGE.STOCK_EX_ID%TYPE,
    p_stock_symbol IN STOCK_LISTING.STOCK_SYMBOL%TYPE)
    
IS
     
BEGIN

    INSERT INTO stock_listing (stock_id, stock_ex_id, stock_symbol)
        VALUES (p_stock_id, p_stock_ex_id, p_stock_symbol);
         
    INSERT INTO stock_price (stock_id, stock_ex_id, price, time_start)
         SELECT
                 co.stock_id,
                 se.stock_ex_id,
                 ROUND(co.starting_price * conv.exchange_rate, 2) AS price,
                 sysdate
                FROM stock_listing sl
                    JOIN company co
                        ON sl.stock_id = co.stock_id
                    JOIN stock_exchange se
                        ON se.stock_ex_id = sl.stock_ex_id
                    JOIN conversion conv
                        ON conv.from_currency_id = co.currency_id AND conv.to_currency_id = se.currency_id
                    WHERE co.stock_id = p_stock_id AND se.stock_ex_id = p_stock_ex_id;
END list_stock;    
/   
rollback
exec list_stock(4, 1, 'TYO:LON')

/*
17.	Write a PL/SQL procedure called SPLIT_STOCK. 
-input parameters:  stock id, split_factor
-The split_factor must be greater than 1 and can be fractional.  (The number of shares will be multiplied by the split_factor.)
-The total shares outstanding cannot exceed the authorized amount.  Your procedure should raise an application error if 
the split would cause the shares outstanding to exceed the shares authorized.
-Every shareholder must receive (is buyer of) an additional "trade" equal to the additional shares to which they are entitled.  
For example, if the split_factor is 2 then each shareholder will be entitled to an additional “trade” that is equal to the number 
of shares that they owned before the split.  (Use the Current_Shareholder_Shares view to determine the number of shares owned).  
These "trades" will not take place at a stock exchange, the price total will be null, and there will be no brokers involved.
*/

CREATE SEQUENCE trade_id_seq
    START WITH 60
    INCREMENT BY 1
    
CREATE OR REPLACE PROCEDURE split_stock(
    p_stock_id IN COMPANY.STOCK_ID%TYPE,
    p_split_factor IN NUMBER)
    
IS    
  v_new_total_outstanding CURRENT_STOCK_STATS.TOTAL_OUTSTANDING%TYPE;
BEGIN
-- checks split factor
    IF p_split_factor <= 1 THEN
        RAISE_APPLICATION_ERROR(-20101, 'Split factor must be greater than 1');
    END IF;
 -- checks if total_oustanding will be less than after calculting the stocks on the split factor   
    SELECT (total_outstanding * p_split_factor) - total_outstanding INTO v_new_total_outstanding
    FROM current_stock_stats
    WHERE current_stock_stats.stock_id = p_stock_id
      AND current_authorized > ( SELECT
      SUM( (shares * p_split_factor) - shares) + total_outstanding
    FROM current_shareholder_shares cur_shares
    --  JOIN company comp
    --    ON cur_shares.stock_id = comp.stock_id 
      JOIN current_stock_stats css
        ON css.stock_id = cur_shares.stock_id
    WHERE cur_shares.stock_id = p_stock_id
      GROUP BY total_outstanding, css.stock_id
    );
      
  -- insert the trades for the new transactions
  INSERT INTO trade (trade_id, stock_id, transaction_time, shares, buyer_id, seller_id)
    SELECT
      trade_id_seq.NEXTVAL,
      css.stock_id,
      sysdate AS transaction_time,
      (cur_shares.shares * p_split_factor) - cur_shares.shares AS shares,
      cur_shares.shareholder_id AS buyer_id,
      comp.company_id AS seller_id
    FROM current_shareholder_shares cur_shares
      JOIN current_stock_stats css
        ON css.stock_id = cur_shares.stock_id
      JOIN company comp
        ON css.stock_id = comp.stock_id
      WHERE css.stock_id = p_stock_id AND cur_shares.shares IS NOT NULL;
    
EXCEPTION
  WHEN NO_DATA_FOUND THEN RAISE_APPLICATION_ERROR(-20101, 'The split factor caused the number of shares to be higher than the numbers authorized or the place_id does not exist.');       
END split_stock;
/

rollback;
exec split_stock(6, 1.5)

/*
18.	Write a PL/SQL procedure called REVERSE_SPLIT.-input parameters: stock id, merge_factor-The merge_factor must be greater
than 0 and less than 1.  (The number of shares will be multiplied by the merge_factor.)-Every shareholder must "sell" some of the 
stock it currently owns.  (Use the Current_Shareholder_Shares view to determine the number of shares owned).  
If the merge_factor is 1/3 then adjustments must be made to indicate the 2/3 of each shareholder’s stock has been removed. 
(The database can handle fractions of a share.)  These "trades" will not take place at a stock exchange, the price total will be null,
and there will be no brokers involved.
*/

CREATE OR REPLACE PROCEDURE reverse_split(
  p_stock_id IN COMPANY.STOCK_ID%TYPE,
  p_merge_factor IN NUMBER
)
IS

BEGIN
  IF p_merge_factor <= 0 OR p_merge_factor >= 1 THEN
    RAISE_APPLICATION_ERROR(-20101, 'merge factor must be in between 0 and 1, exclusive.');
  END IF;
  
  INSERT INTO trade (trade_id, stock_id, transaction_time, shares, buyer_id, seller_id)
    SELECT
      trade_id_seq.NEXTVAL,
      css.stock_id,
      sysdate AS transaction_time,
      ROUND(cur_shares.shares - (cur_shares.shares * p_merge_factor), 2) AS shares,
      comp.company_id AS buyer_id,
      cur_shares.shareholder_id AS seller_id
    FROM current_shareholder_shares cur_shares
      JOIN current_stock_stats css
        ON css.stock_id = cur_shares.stock_id
      JOIN company comp
        ON css.stock_id = comp.stock_id
      WHERE css.stock_id = p_stock_id AND cur_shares.shares IS NOT NULL;    
  
END reverse_split;
/

exec reverse_split(6, 1/3)

/*
19.	Display the trade id, the stock id and the total price (in US dollars) for the secondary market trade with the highest 
total price.  Convert all prices to US dollars.
*/

WITH trades_in_us_dollars AS (
SELECT 
  tr.trade_id,
  comp.stock_id,
  tr.price_total * conv.exchange_rate AS total_price
FROM trade tr
    JOIN stock_exchange se
        ON se.stock_ex_id = tr.stock_ex_id
    JOIN company comp
        ON comp.stock_id = tr.stock_id
    JOIN conversion conv
        ON conv.from_currency_id = comp.currency_id AND conv.to_currency_id = 1
    WHERE tr.stock_ex_id IS NOT NULL
)
SELECT
        tr_us.trade_id,
        tr_us.stock_id,
        MAX(tr_us.total_price)
    FROM 
    trades_in_us_dollars tr_us
    WHERE tr_us.total_price = (SELECT
            MAX(sub_tr_us.total_price)
          FROM trades_in_us_dollars sub_tr_us    
    )
    GROUP BY tr_us.trade_id, tr_us.stock_id
    
/*
  20.	Display the name of the company and trade volume for the company whose stock has the largest total volume of shareholder trades 
  worldwide. [Example calculation: A company declares 20000 shares, and issues 10000 on the new issue market (primary market), 
  and 1000 shares is sold to a stockholder on the secondary market. Later that stockholder sells 500 shares to another 
  stockholder (or back to the company itself).  The number of shareholder trades is 2 and the total volume of shareholder trades is 
  1500.]
*/

WITH trades_and_shares_per_stock AS (
  SELECT
    tr.stock_id,
    comp.name,
    SUM(tr.shares) AS total_shares
  FROM trade tr
    JOIN company comp
      ON comp.stock_id = tr.stock_id
    JOIN stock_exchange se
      ON se.stock_ex_id = tr.stock_ex_id
    GROUP BY tr.stock_id, comp.name
    )
    
SELECT
  tpps.name,
  tpps.total_shares
FROM trades_and_shares_per_stock tpps
    WHERE tpps.total_shares IN (
        SELECT
            MAX(total_shares)
        FROM trades_and_shares_per_stock   
    )
    
/* 21.	For each stock exchange, display the symbol of the stock with the highest total trade volume. Show the stock exchange name, 
        stock symbol and total trade volume.  Sort the output by the name of the stock exchange and stock symbol. */
    
WITH trades_and_shares_per_exchange AS (
    SELECT
        se.name,
        sl.stock_symbol,
        SUM(tr.shares) AS total_shares
    FROM trade tr
        JOIN stock_exchange se
            ON se.stock_ex_id = tr.stock_ex_id
        JOIN stock_listing sl
            ON sl.stock_ex_id = se.stock_ex_id
                AND tr.stock_id = sl.stock_id
    GROUP BY tr.stock_ex_id, se.name, tr.stock_id, sl.stock_symbol            
)

SELECT
    tspe.name,
    tspe.stock_symbol,
    total_shares
FROM trades_and_shares_per_exchange tspe
    WHERE total_shares IN (
        SELECT 
            MAX(total_shares)
        FROM trades_and_shares_per_exchange
        GROUP BY name
    ) ORDER BY tspe.name, tspe.stock_symbol
    
/*
22.	List the top 5 companies (in terms of shareholder trade volume) on the New York Stock Exchange.  Display the company name, 
shareholder trade volume, the current price and the percentage change for the last price change, and sort the output in descending 
order of shareholder trade volume.  The sample data in the database contains information for only 3 companies but your query 
must continue to list only the top 5 companies even when there is data for more companies.
*/

WITH shares_ny AS (
  SELECT
    tr.stock_id,
    tr.stock_ex_id,
    comp.name,
    SUM(shares) AS total_shares
  FROM trade tr
    JOIN company comp
      ON tr.stock_id = comp.stock_id AND tr.stock_ex_id = 3
    GROUP BY tr.stock_id, tr.stock_ex_id, comp.name  
),

cur_price AS (
  SELECT
    stock_id,
    stock_ex_id,
    price
  FROM stock_price
  WHERE time_end IS NULL
),

prev_price AS (
  SELECT
    stock_id,
    stock_ex_id,
    price
  FROM stock_price WHERE (stock_id, stock_ex_id, time_end) IN (
    SELECT
      stock_id,
      stock_ex_id,
      MAX(time_end)
    FROM stock_price sub_sp
    GROUP BY stock_id, stock_ex_id
  )
)

SELECT
  *
FROM (SELECT
       shny.name,
       shny.total_shares,
       cp.price,
       ROUND( ( (cp.price - pp.price) / pp.price ) * 100, 2) AS percent_change
      FROM  
      shares_ny shny
      JOIN prev_price pp
        ON shny.stock_id = pp.stock_id
        AND shny.stock_ex_id = pp.stock_ex_id
      JOIN cur_price cp
        ON cp.stock_id = pp.stock_id
        AND cp.stock_ex_id = pp.stock_ex_id
      ORDER BY shny.total_shares DESC) WHERE rownum <= 5
  

