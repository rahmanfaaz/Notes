WITH env_info AS (
    SELECT 
        (SELECT name FROM v$database) AS db_name,
        (SELECT host_name FROM v$instance) AS server_name,
        (SELECT instance_name FROM v$instance) AS instance_name,
        (SELECT LISTAGG(name, ', ') WITHIN GROUP (ORDER BY name) FROM gv$active_services) AS service_name
    FROM dual
),
sql_text_info AS (
    SELECT 
        sql_id,
        -- extract table name after FROM/JOIN/UPDATE
        REGEXP_SUBSTR(LOWER(sql_text), '(from|join|update)\\s+([a-zA-Z0-9_$.]+)', 1, 1, NULL, 2) AS target_table
    FROM dba_hist_sqltext
    WHERE sql_id = '0y8mgj784n3zg'
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
    FROM dba_hist_sqlstat ss
    WHERE ss.sql_id = '0y8mgj784n3zg'
    GROUP BY ss.sql_id, ss.plan_hash_value
),
top_modules AS (
    SELECT 
        ash.sql_id,
        ash.plan_hash_value,
        ash.module,
        COUNT(*) AS usage_count,
        RANK() OVER (PARTITION BY ash.sql_id, ash.plan_hash_value ORDER BY COUNT(*) DESC) AS rnk
    FROM dba_hist_active_sess_history ash
    WHERE ash.sql_id = '0y8mgj784n3zg'
    AND ash.sample_time > SYSDATE - INTERVAL '6' HOUR
    GROUP BY ash.sql_id, ash.plan_hash_value, ash.module
),
ash_base AS (
    SELECT 
        ash.sql_id,
        ash.plan_hash_value,
        u.username,
        COUNT(*) AS ash_samples
    FROM dba_hist_active_sess_history ash
    JOIN dba_users u ON ash.user_id = u.user_id
    WHERE ash.sql_id = '0y8mgj784n3zg'
    AND ash.sample_time > SYSDATE - INTERVAL '6' HOUR
    AND ash.plan_hash_value NOT IN (
        SELECT DISTINCT plan_hash_value 
        FROM dba_hist_sqlstat 
        WHERE sql_id = '0y8mgj784n3zg'
    )
    GROUP BY ash.sql_id, ash.plan_hash_value, u.username
),
ash_metrics AS (
    SELECT 
        ab.sql_id,
        ab.plan_hash_value,
        'ASH_ONLY' AS source,
        tm.module,
        ab.username,
        NULL AS total_execs,
        NULL AS total_elapsed_secs,
        NULL AS total_cpu_secs,
        NULL AS total_buffer_gets,
        NULL AS total_disk_reads,
        NULL AS avg_elapsed_secs,
        NULL AS avg_cpu_secs,
        ab.ash_samples
    FROM ash_base ab
    LEFT JOIN top_modules tm 
      ON ab.sql_id = tm.sql_id AND ab.plan_hash_value = tm.plan_hash_value AND tm.rnk = 1
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
    END AS verdict,
    sti.target_table AS table_name
FROM scored s
CROSS JOIN env_info ei
LEFT JOIN sql_text_info sti ON s.sql_id = sti.sql_id
ORDER BY s.perf_score NULLS LAST, s.ash_samples DESC;
