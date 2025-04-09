WITH 
  FUNCTION split_funds(p_clob CLOB) RETURN SYS.ODCIVARCHAR2LIST PIPELINED IS
    v_start   PLS_INTEGER := 1;
    v_end     PLS_INTEGER;
    v_token   VARCHAR2(4000);
  BEGIN
    LOOP
      v_end := INSTR(p_clob, ',', v_start);
      EXIT WHEN v_end = 0;
      v_token := SUBSTR(p_clob, v_start, v_end - v_start);
      PIPE ROW(TRIM(v_token));
      v_start := v_end + 1;
    END LOOP;
    -- Add last token
    IF v_start <= LENGTH(p_clob) THEN
      PIPE ROW(TRIM(SUBSTR(p_clob, v_start)));
    END IF;
    RETURN;
  END;
  -- Your list of funds as a CLOB (unlimited length)
  fund_data AS (
    SELECT TO_CLOB(
      'FUND1,FUND2,FUND3,...,FUND2000'  -- Put your full list here
    ) AS fund_clob
    FROM dual
  ),
  fund_list AS (
    SELECT COLUMN_VALUE AS fund_id
    FROM fund_data, TABLE(split_funds(fund_clob))
  )
SELECT *
FROM your_table
WHERE fund_id IN (SELECT fund_id FROM fund_list);
