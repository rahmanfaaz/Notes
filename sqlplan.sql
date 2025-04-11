WITH 
sqlstat_metrics AS (
    SELECT 
        sql_id,
        plan_hash_value,
        'SQLSTAT' AS source,
        SUM(executions_delta) AS total_execs,
        ROUND(SUM(elapsed_time_delta)/1e6, 2) AS total_elapsed_secs,
        ROUND(SUM(cpu_time_delta)/1e6, 2) AS total_cpu_secs,
        ROUND(SUM(buffer_gets_delta)) AS total_buffer_gets,
        ROUND(SUM(disk_reads_delta)) AS total_disk_reads,
        ROUND(SUM(elapsed_time_delta) / NULLIF(SUM(executions_delta), 0) / 1e6, 2) AS avg_elapsed_secs,
        ROUND(SUM(cpu_time_delta) / NULLIF(SUM(executions_delta), 0) / 1e6, 2) AS avg_cpu_secs,
        NULL AS ash_samples
    FROM 
        dba_hist_sqlstat
    WHERE 
        sql_id = '0y8mgj784n3zg'  -- ⬅️ Replace with your SQL ID
    GROUP BY 
        sql_id, plan_hash_value
),
ash_metrics AS (
    SELECT 
        sql_id,
        plan_hash_value,
        'ASH_ONLY' AS source,
        NULL AS total_execs,
        NULL AS total_elapsed_secs,
        NULL AS total_cpu_secs,
        NULL AS total_buffer_gets,
        NULL AS total_disk_reads,
        NULL AS avg_elapsed_secs,
        NULL AS avg_cpu_secs,
        COUNT(*) AS ash_samples
    FROM 
        dba_hist_active_sess_history
    WHERE 
        sql_id = '0y8mgj784n3zg'  -- ⬅️ Replace with your SQL ID
        AND sample_time > SYSDATE - INTERVAL '6' HOUR
        AND plan_hash_value NOT IN (
            SELECT DISTINCT plan_hash_value 
            FROM dba_hist_sqlstat 
            WHERE sql_id = '0y8mgj784n3zg'
        )
    GROUP BY 
        sql_id, plan_hash_value
),
combined AS (
    SELECT * FROM sqlstat_metrics
    UNION ALL
    SELECT * FROM ash_metrics
)
SELECT 
    sql_id,
    plan_hash_value,
    source,
    total_execs,
    avg_elapsed_secs,
    avg_cpu_secs,
    total_buffer_gets,
    total_disk_reads,
    ash_samples,
    CASE
        WHEN source = 'SQLSTAT' THEN 
            CASE 
                WHEN RANK() OVER (ORDER BY avg_elapsed_secs ASC NULLS LAST, avg_cpu_secs ASC NULLS LAST) = 1 
                THEN '✅ Preferred (Better Plan)'
                ELSE '⚠️ Worse Plan'
            END
        ELSE 
            'ℹ️ No executions captured (ASH only)'
    END AS verdict
FROM combined
ORDER BY avg_elapsed_secs NULLS LAST, ash_samples DESC;
