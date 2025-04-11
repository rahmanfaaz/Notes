WITH plan_metrics AS (
    SELECT 
        ss.sql_id,
        ss.plan_hash_value,
        SUM(ss.executions_delta) AS total_execs,
        ROUND(SUM(ss.elapsed_time_delta)/1e6, 2) AS total_elapsed_secs,
        ROUND(SUM(ss.cpu_time_delta)/1e6, 2) AS total_cpu_secs,
        ROUND(SUM(ss.buffer_gets_delta)) AS total_buffer_gets,
        ROUND(SUM(ss.disk_reads_delta)) AS total_disk_reads,
        ROUND(SUM(ss.elapsed_time_delta) / NULLIF(SUM(ss.executions_delta), 0) / 1e6, 2) AS avg_elapsed_secs,
        ROUND(SUM(ss.cpu_time_delta) / NULLIF(SUM(ss.executions_delta), 0) / 1e6, 2) AS avg_cpu_secs
    FROM 
        dba_hist_sqlstat ss
    WHERE 
        ss.sql_id = '9bpfqawb8kmj0n'  -- ← your SQL ID
    GROUP BY 
        ss.sql_id, ss.plan_hash_value
)
SELECT 
    sql_id,
    plan_hash_value,
    total_execs,
    total_elapsed_secs,
    total_cpu_secs,
    total_buffer_gets,
    total_disk_reads,
    avg_elapsed_secs,
    avg_cpu_secs,
    CASE 
        WHEN RANK() OVER (PARTITION BY sql_id ORDER BY avg_elapsed_secs ASC, total_cpu_secs ASC) = 1 
        THEN '✅ Preferred (Better Plan)'
        ELSE '⚠️ Worse Plan'
    END AS verdict
FROM plan_metrics
ORDER BY avg_elapsed_secs ASC;
