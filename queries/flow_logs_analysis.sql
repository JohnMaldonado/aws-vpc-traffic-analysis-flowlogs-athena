-- =============================================================================
-- Assignment 15: VPC Flow Logs Analysis – SQL Query Reference
-- Student: Hector Jonathan Maldonado Vega | Batch 10.28
-- Engine: Amazon Athena (Athena engine version 3)
-- Table:  vpc_flow_logs  (Parquet, partition projection enabled)
-- =============================================================================

-- =============================================================================
-- STEP 0: Run once after Terraform apply to verify table exists
-- =============================================================================
SHOW TABLES IN jhon_a15_flowlogs_db;

-- =============================================================================
-- QUERY 1: Top 10 Source IPs by Traffic Volume
-- Purpose:  Identify the chattiest sources – useful for DDoS detection,
--           or spotting misconfigured services generating unexpected traffic.
-- =============================================================================
SELECT
    srcaddr                                         AS source_ip,
    COUNT(*)                                        AS flow_count,
    SUM(bytes)                                      AS total_bytes,
    SUM(packets)                                    AS total_packets,
    ROUND(SUM(bytes) / 1048576.0, 2)               AS total_mb,
    SUM(CASE WHEN action = 'ACCEPT' THEN 1 ELSE 0 END) AS accepted_flows,
    SUM(CASE WHEN action = 'REJECT' THEN 1 ELSE 0 END) AS rejected_flows
FROM vpc_flow_logs
WHERE action     IS NOT NULL
  AND srcaddr NOT IN ('-')
GROUP BY srcaddr
ORDER BY total_bytes DESC
LIMIT 10;

-- =============================================================================
-- QUERY 2: All REJECT Actions
-- Purpose:  Surface blocked connection attempts. High REJECT counts from a
--           single source may indicate scanning, brute-force, or misconfigured
--           application trying to reach a disallowed port.
-- =============================================================================
SELECT
    from_unixtime(start)                    AS event_time_utc,
    srcaddr                                 AS source_ip,
    dstaddr                                 AS destination_ip,
    srcport                                 AS src_port,
    dstport                                 AS dst_port,
    CASE protocol
        WHEN 6   THEN 'TCP'
        WHEN 17  THEN 'UDP'
        WHEN 1   THEN 'ICMP'
        ELSE CAST(protocol AS varchar)
    END                                     AS protocol_name,
    bytes,
    packets,
    interface_id,
    vpc_id
FROM vpc_flow_logs
WHERE action = 'REJECT'
ORDER BY start DESC
LIMIT 500;

-- Aggregated view – which destination ports are most rejected?
SELECT
    dstport,
    CASE protocol
        WHEN 6  THEN 'TCP'
        WHEN 17 THEN 'UDP'
        WHEN 1  THEN 'ICMP'
        ELSE CAST(protocol AS varchar)
    END                                 AS protocol_name,
    COUNT(*)                            AS reject_count,
    COUNT(DISTINCT srcaddr)             AS unique_sources
FROM vpc_flow_logs
WHERE action = 'REJECT'
GROUP BY dstport, protocol
ORDER BY reject_count DESC
LIMIT 20;

-- =============================================================================
-- QUERY 3: Traffic Between Specific IPs (replace with actual values)
-- Purpose:  Investigate communication between two known instances.
--           Captures both directions of the flow.
-- =============================================================================
-- Replace 10.15.1.X and 10.15.2.X with actual private IPs from Terraform output
SELECT
    from_unixtime(start)                    AS event_time_utc,
    srcaddr,
    dstaddr,
    srcport,
    dstport,
    CASE protocol
        WHEN 6   THEN 'TCP'
        WHEN 17  THEN 'UDP'
        WHEN 1   THEN 'ICMP'
        ELSE CAST(protocol AS varchar)
    END                                     AS protocol_name,
    action,
    bytes,
    packets,
    flow_direction,
    interface_id
FROM vpc_flow_logs
WHERE (srcaddr = '10.15.1.100' AND dstaddr = '10.15.2.200')
   OR (srcaddr = '10.15.2.200' AND dstaddr = '10.15.1.100')
ORDER BY start;

-- =============================================================================
-- QUERY 4: All Connections to Port 22 (SSH)
-- Purpose:  Audit SSH access – who is connecting, from where, and whether
--           attempts were accepted or rejected. Critical for security review.
-- =============================================================================
SELECT
    from_unixtime(start)                    AS event_time_utc,
    srcaddr                                 AS source_ip,
    dstaddr                                 AS destination_ip,
    action,
    bytes,
    packets,
    interface_id,
    CASE tcp_flags
        WHEN 2  THEN 'SYN (new connection)'
        WHEN 18 THEN 'SYN-ACK (handshake)'
        WHEN 16 THEN 'ACK (data)'
        WHEN 4  THEN 'RST (reset)'
        WHEN 1  THEN 'FIN (close)'
        WHEN 24 THEN 'PSH-ACK (data push)'
        ELSE CAST(tcp_flags AS varchar)
    END                                     AS tcp_flag_name
FROM vpc_flow_logs
WHERE dstport  = 22
  AND protocol = 6
ORDER BY start DESC;

-- Summary: SSH accept vs reject counts by source IP
SELECT
    srcaddr                                 AS source_ip,
    action,
    COUNT(*)                                AS connection_count
FROM vpc_flow_logs
WHERE dstport  = 22
  AND protocol = 6
GROUP BY srcaddr, action
ORDER BY connection_count DESC;

-- =============================================================================
-- QUERY 5: Traffic by Protocol (TCP / UDP / ICMP)
-- Purpose:  Understand the protocol mix on your VPC. Unexpected UDP spikes
--           can indicate DNS amplification; ICMP spikes may indicate sweeps.
-- =============================================================================
SELECT
    CASE protocol
        WHEN 6   THEN 'TCP'
        WHEN 17  THEN 'UDP'
        WHEN 1   THEN 'ICMP'
        ELSE CONCAT('Other (proto=', CAST(protocol AS varchar), ')')
    END                                                         AS protocol_name,
    COUNT(*)                                                    AS flow_count,
    SUM(bytes)                                                  AS total_bytes,
    SUM(packets)                                                AS total_packets,
    ROUND(SUM(bytes) / 1048576.0, 2)                           AS total_mb,
    ROUND(SUM(bytes) * 100.0 / SUM(SUM(bytes)) OVER (), 2)    AS pct_of_total,
    SUM(CASE WHEN action = 'ACCEPT' THEN 1 ELSE 0 END)         AS accepted,
    SUM(CASE WHEN action = 'REJECT' THEN 1 ELSE 0 END)         AS rejected
FROM vpc_flow_logs
WHERE protocol IS NOT NULL
GROUP BY protocol
ORDER BY total_bytes DESC;

-- =============================================================================
-- QUERY 6: Security Events Summary (BONUS – combines REJECT + port 22)
-- Purpose:  One-stop security dashboard query.
-- =============================================================================
SELECT
    'Rejected connections'                          AS metric,
    COUNT(*)                                        AS value
FROM vpc_flow_logs WHERE action = 'REJECT'
UNION ALL
SELECT
    'Unique rejected source IPs',
    COUNT(DISTINCT srcaddr)
FROM vpc_flow_logs WHERE action = 'REJECT'
UNION ALL
SELECT
    'SSH accepted connections',
    COUNT(*)
FROM vpc_flow_logs WHERE dstport = 22 AND protocol = 6 AND action = 'ACCEPT'
UNION ALL
SELECT
    'SSH rejected connections',
    COUNT(*)
FROM vpc_flow_logs WHERE dstport = 22 AND protocol = 6 AND action = 'REJECT'
UNION ALL
SELECT
    'Total flow records',
    COUNT(*)
FROM vpc_flow_logs;

-- =============================================================================
-- QUERY 7: Cost Estimation
-- Athena pricing: $5.00 per TB scanned
-- Parquet reduces scan size by ~80% vs CSV (columnar + compressed)
-- =============================================================================
-- After running your queries, check the Athena console:
-- History tab → click each query → "Data scanned" column
--
-- Manual estimate formula (run after each query):
-- Cost ($) = DataScannedBytes / (1024^4) * 5.00
--
-- Example: if a query scanned 50 MB:
-- Cost = 50 / (1024*1024) GB / 1024 * $5.00 = $0.000000238 (essentially free)
--
-- Compare: same query on CSV would scan ~250 MB → 5x more expensive

SELECT
    'Parquet (this lab)'                AS format,
    50                                  AS scan_mb_example,
    ROUND(50 / 1048576.0 / 1024 * 5, 8) AS cost_usd
UNION ALL
SELECT
    'CSV (equivalent)',
    250,
    ROUND(250 / 1048576.0 / 1024 * 5, 8);
