WITH 
env_info AS (
    SELECT 
        (SELECT name FROM v$database) AS db_name,
        (SELECT host_name FROM v$instance) AS server_name,
        (SELECT instance_name FROM v$instance) AS instance_name,
        (SELECT LISTAGG(name, ', ') WITHIN GROUP (ORDER BY name) FROM gv$active_services) AS service_name
    FROM dual
),
sqlstat_metrics AS (
    SELECT 
        ss.sql_id,
        ss.plan_hash_value,
        'SQLSTAT' AS source,
        NULL AS module,
        NULL AS username,
        SUM(ss.executions_delta) AS total_execs,
        ROUND(SUM(ss.elapsed_time_delta)/1e6, 2) AS total_elapsed_secs,
        ROUND(SUM(ss.cpu_time_delta)/1e6, 2) AS total_cpu_secs,
        ROUND(SUM(ss.buffer_gets_delta)) AS total_buffer_gets,
        ROUND(SUM(ss.disk_reads_delta)) AS total_disk_reads,
        ROUND(SUM(ss.elapsed_time_delta) / NULLIF(SUM(ss.executions_delta), 0) / 1e6, 2) AS avg_elapsed_secs,
        ROUND(SUM(ss.cpu_time_delta) / NULLIF(SUM(ss.executions_delta), 0) / 1e6, 2) AS avg_cpu_secs,
        NULL AS ash_samples
    FROM 
        dba_hist_sqlstat ss
    WHERE 
        ss.sql_id = '0y8mgj784n3zg'
    GROUP BY 
        ss.sql_id, ss.plan_hash_value
),
ash_metrics AS (
    SELECT 
        ash.sql_id,
        ash.plan_hash_value,
        'ASH_ONLY' AS source,
        MAX(ash.module) KEEP (DENSE_RANK LAST ORDER BY COUNT(*) OVER (PARTITION BY ash.plan_hash_value)) AS module,
        MAX(u.username) AS username,
        NULL AS total_execs,
        NULL AS total_elapsed_secs,
        NULL AS total_cpu_secs,
        NULL AS total_buffer_gets,
        NULL AS total_disk_reads,
        NULL AS avg_elapsed_secs,
        NULL AS avg_cpu_secs,
        COUNT(*) AS ash_samples
    FROM 
        dba_hist_active_sess_history ash
        JOIN dba_users u ON ash.user_id = u.user_id
    WHERE 
        ash.sql_id = '0y8mgj784n3zg'
        AND ash.sample_time > SYSDATE - INTERVAL '6' HOUR
        AND ash.plan_hash_value NOT IN (
            SELECT DISTINCT plan_hash_value 
            FROM dba_hist_sqlstat 
            WHERE sql_id = '0y8mgj784n3zg'
        )
    GROUP BY 
        ash.sql_id, ash.plan_hash_value
),
combined AS (
    SELECT * FROM sqlstat_metrics
    UNION ALL
    SELECT * FROM ash_metrics
),
scored AS (
    SELECT *,
        RANK() OVER (ORDER BY avg_elapsed_secs NULLS LAST) * 0.4 +
        RANK() OVER (ORDER BY avg_cpu_secs NULLS LAST) * 0.3 +
        RANK() OVER (ORDER BY total_buffer_gets NULLS LAST) * 0.15 +
        RANK() OVER (ORDER BY total_disk_reads NULLS LAST) * 0.15 AS perf_score
    FROM combined
)
SELECT 
    ei.db_name,
    ei.server_name,
    ei.instance_name,
    ei.service_name,
    s.sql_id,
    s.plan_hash_value,
    s.source,
    s.username,
    s.module,
    s.total_execs,
    s.avg_elapsed_secs,
    s.avg_cpu_secs,
    s.total_buffer_gets,
    s.total_disk_reads,
    s.ash_samples,
    ROUND(s.perf_score, 2) AS score,
    CASE 
        WHEN s.source = 'ASH_ONLY' THEN 'ℹ️ Seen only in ASH - no execution stats'
        WHEN RANK() OVER (ORDER BY s.perf_score ASC NULLS LAST) = 1 THEN '✅ Best Plan'
        ELSE '⚠️ Slower Plan'
    END AS verdict
FROM scored s
CROSS JOIN env_info ei
ORDER BY s.perf_score NULLS LAST, s.ash_samples DESC;
