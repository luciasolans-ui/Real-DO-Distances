-- =====================================================================================
-- PROYECTO REAL DO DISTANCES: EXTRACCIÓN DE SÁBANA DE ÓRDENES (HISTÓRICO & TEST SWITCHBACK)
--
-- Esta consulta extrae la sábana de órdenes agregada por día, flota, vertical y tier horario
-- para el periodo del Switchback Test (02/09/2026 al 15/09/2026) y su respectivo
-- baseline de las últimas 8 semanas (08/07/2026 al 01/09/2026).
--
-- Rango total extraído: 08/07/2026 al 15/09/2026.
-- Exclusiones aplicadas: 
--    1. Ventana del Mundial 2026 (hasta el 19/07/2026, con sus días de descanso).
--    2. Incidencias en la App, se marca la columna is_incident para excluir de métricas
--       del test todos los Sábados (20h a 23h) y Domingos (00h a 03h), pero mantenerlos
--       en la validación nacional completa sin exclusiones.
-- =====================================================================================
WITH zdim_sp AS (
   -- 1. Dimensión de Zonas y Flotas de Argentina (Mapeo robusto por par (city_id, zone_id) para evitar duplicados, excluyendo zonas sin flotas)
   SELECT
     ci.id AS city_id,
     zo.id AS zone_id,
     zo.fleet_id AS fleet_id
   FROM `peya-data-origins-pro.cl_hurrier.countries` c
   LEFT JOIN UNNEST(c.cities) ci
   LEFT JOIN UNNEST(ci.zones) zo
   WHERE c.country_code = 'ar' 
     AND zo.id IS NOT NULL
     AND ci.id IS NOT NULL
     AND zo.fleet_id IS NOT NULL
),
rdds_sp AS (
   -- 2. Distancia Google ruteada (RDDS) para Pickup y Dropoff
   SELECT
     delivery_id,
     ANY_VALUE(stack_lead_id)             AS stack_lead_id,
     MAX(pickup_distance_google)          AS pu_g,
     MAX(dropoff_distance_google)         AS dof_g
   FROM `fulfillment-dwh-production.curated_data_shared.rider_payment_delivery_distance_service`
   WHERE created_date BETWEEN '2026-07-08' AND '2026-09-15'
     AND country_code = 'ar'
     AND region = 'Americas'
   GROUP BY delivery_id
),
bags_sp AS (
   -- 3. Ponderador de bolsas para prorratear correctamente DistPU en agrupados
   SELECT
     stack_lead_id AS lead,
     MAX(pu_g) AS lead_pu,
     COUNT(*) AS bagsize
   FROM rdds_sp
   WHERE stack_lead_id IS NOT NULL
   GROUP BY stack_lead_id
),
cpo_data_sp AS (
   -- 4. Datos de CPO (Costo por Orden)
   SELECT
     delivery_id,
     basic_cpo_lc                                   AS cpo_base,   
     basic_payment_per_km_pu_lc                     AS cpo_pu,     
     basic_payment_per_km_do_lc                     AS cpo_do,     
     basic_cpo_lc + CAST(scoring_cpo_lc AS FLOAT64) AS cpo_total  
   FROM `peya-datamarts-pro.dm_cpo.overall_cpo`
   WHERE created_date BETWEEN '2026-07-08' AND '2026-09-15'
     AND country_code = 'ar'
),
seamless_data_sp AS (
   -- 5. Tasa de Seamless Delivery
   SELECT
     platform_order_code_str AS oid,
     created_date_local AS dt,
     MAX(CAST(non_seamless_order AS INT64)) AS non_seamless
   FROM `peya-datamarts-pro.dm_fulfillment.non_seamless_delivery_order_level`
   WHERE created_date_local BETWEEN '2026-07-08' AND '2026-09-15'
     AND country_name = 'Argentina'
   GROUP BY oid, dt
),
raw_orders_sp AS (
   -- 6. Extracción optimizada de la entrega primaria (PRIMARY DELIVERY ONLY)
   -- Filtrado metodológico alineado a la Skill: utilizando fo.order_status = "CONFIRMED"
   SELECT
     lo.platform_order_code,
     fo.order_status AS order_status_fo,
     lo.order_status AS order_status_lo,
     lo.created_date_local,
     lo.created_at_local, -- Agregada para clasificar el tier horario
     lo.city.city_id AS city_id,
     lo.zone.zone_id AS zone_id,
     lo.city.city_name,
     lo.timings.zone_stats.mean_delay,
     lo.vendor.vertical_type,
     lo.is_order_late_10,
     lo.is_preorder, -- Seleccionamos is_preorder para discriminar en la suma de tiempos
     (CASE WHEN 
       (EXTRACT(DAYOFWEEK FROM lo.created_at_local) = 7 AND EXTRACT(HOUR FROM lo.created_at_local) IN (20, 21, 22, 23))
       OR
       (EXTRACT(DAYOFWEEK FROM lo.created_at_local) = 1 AND EXTRACT(HOUR FROM lo.created_at_local) IN (0, 1, 2, 3))
      THEN 1 ELSE 0 END) AS is_incident,
     (SELECT AS STRUCT 
        delivery_id, 
        is_stacked, 
        timings.actual_delivery_time AS actual_delivery_time
      FROM UNNEST(lo.deliveries) 
      WHERE is_primary 
      LIMIT 1
     ) AS prim_del
   FROM `peya-bi-tools-pro.il_logistics.fact_logistic_orders` lo
   INNER JOIN `peya-bi-tools-pro.il_core.fact_orders` fo
     ON lo.platform_order_code = CAST(fo.order_id AS STRING)
   WHERE lo.created_date BETWEEN '2026-07-08'-1 AND '2026-09-15'+1
     AND lo.created_date_local BETWEEN '2026-07-08' AND '2026-09-15'
     AND fo.registered_date BETWEEN '2026-07-08' AND '2026-09-15' -- Agregado para mantener eficiencia de partición
     AND lo.country.country_id = 3
     AND lower(lo.vendor.vertical_type) NOT LIKE ('%courier%')
),
universe_sp AS (
   -- 7. Agrupamiento, mapeo de flotas e identificación de verticales y tiers horarios alineados con la lógica del usuario
   SELECT
     ro.platform_order_code,
     order_status_fo,
     order_status_lo,
     ro.created_date_local AS dt,
     z.fleet_id,
     ro.city_name,
     ro.mean_delay AS md,
     CASE 
       WHEN LOWER(ro.vertical_type) LIKE '%darkstore%' 
            OR LOWER(ro.vertical_type) LIKE '%dmart%' 
            OR LOWER(ro.vertical_type) LIKE '%peyamarket%' 
            OR LOWER(ro.vertical_type) LIKE '%market_peya%'
            THEN 'DMARTS'
       WHEN LOWER(ro.vertical_type) = 'restaurants' THEN 'RESTAURANTS'
       ELSE 'LOCAL STORES'
     END AS vertical,
     CASE 
       WHEN EXTRACT(HOUR FROM ro.created_at_local) BETWEEN 7 AND 10 THEN '2 - Morning'
       WHEN EXTRACT(HOUR FROM ro.created_at_local) BETWEEN 11 AND 14 THEN '3 - Lunch'
       WHEN EXTRACT(HOUR FROM ro.created_at_local) BETWEEN 15 AND 18 THEN '4 - Afternoon'
       WHEN EXTRACT(HOUR FROM ro.created_at_local) BETWEEN 19 AND 23 THEN '5 - Dinner'
       ELSE '1 - Post Dinner'
     END AS time_tier,
     ro.prim_del.delivery_id AS did,
     ro.prim_del.is_stacked,
     ro.prim_del.actual_delivery_time AS delivery_time_seconds,
     ro.is_order_late_10 AS ol10,
     ro.is_preorder, -- Pasamos is_preorder
     ro.is_incident
   FROM raw_orders_sp ro
   INNER JOIN zdim_sp z ON z.zone_id = ro.zone_id AND z.city_id = ro.city_id
   WHERE ro.prim_del.delivery_id IS NOT NULL
     -- Exclusión de distorsión de la ventana del Mundial 2026 (08/07 al 19/07 excepto días de descanso)
     AND NOT (
       ro.created_date_local BETWEEN '2026-06-11' AND '2026-07-19'
       AND ro.created_date_local NOT IN ('2026-07-08', '2026-07-12', '2026-07-13', '2026-07-16', '2026-07-17') 
     )
)
-- 8. Ensamble de Métricas consolidadas agrupadas por día, flota, vertical y tier horario
SELECT
   u.dt                 AS fecha,
   u.fleet_id           AS fleet_id,
   u.vertical           AS vertical,
   u.time_tier          AS time_tier,
   CAST(FLOOR(u.md / 2) * 2 AS INT64)      AS mean_delay_zona_min,
   u.is_incident        AS is_incident,
   COUNT(*)             AS orders_total_count,
   COUNT(CASE WHEN order_status_fo = "CONFIRMED" AND order_status_lo = "completed" THEN platform_order_code ELSE NULL END) AS orders_completed_count, 
   COUNT(CASE WHEN u.is_preorder IS FALSE AND order_status_fo = "CONFIRMED" AND order_status_lo = "completed" THEN platform_order_code ELSE NULL END)  AS delivery_time_orders_count, 
   ROUND(SUM(IF(u.is_preorder IS FALSE AND order_status_fo = "CONFIRMED" AND order_status_lo = "completed", SAFE_DIVIDE(u.delivery_time_seconds, 60), 0)), 2) AS delivery_time_sum, 
   SUM(CASE WHEN order_status_fo = "CONFIRMED" AND order_status_lo = "completed" THEN u.ol10 ELSE NULL END)        AS late_10_sum, 
   SUM(IF(s.non_seamless = 0 AND order_status_fo = "CONFIRMED" AND order_status_lo = "completed", 1, 0))           AS seamless_sum,
   SUM(IF(u.is_stacked IS TRUE AND order_status_fo = "CONFIRMED" AND order_status_lo = "completed", 1, 0))         AS stacked_sum, 
   
   -- MEAN DELAY EXACTO CALCULADO SOBRE ÓRDENES TOTALES (u.md IS NOT NULL), REMOVIENDO FILTROS DE ESTADO COMPLETED/CONFIRMED
   ROUND(SUM(IF(u.md IS NOT NULL, u.md, 0)), 2) AS mean_delay_sum,
   COUNT(CASE WHEN u.md IS NOT NULL THEN platform_order_code ELSE NULL END) AS mean_delay_orders_count,

   ROUND(SUM(COALESCE(b.lead_pu / b.bagsize, rd.pu_g)) / 1000, 3)        AS pickup_distance_sum,
   ROUND(SUM(rd.dof_g) / 1000, 3)                                        AS dropoff_distance_sum,
   ROUND(SUM((COALESCE(b.lead_pu / b.bagsize, rd.pu_g) + COALESCE(rd.dof_g, 0)) / 1000), 3)                        AS total_distance_sum,
   ROUND(SUM(cp.cpo_base), 2)                                            AS cpo_base_sum,
   ROUND(SUM(cp.cpo_pu), 2)                                              AS cpo_dist_pu_sum,
   ROUND(SUM(cp.cpo_do), 2)                                              AS cpo_dist_do_sum,
   ROUND(SUM(cp.cpo_total), 2)                                           AS cpo_total_sum
FROM universe_sp u
LEFT JOIN seamless_data_sp s  ON s.oid = u.platform_order_code AND s.dt = u.dt
LEFT JOIN rdds_sp           rd ON rd.delivery_id = u.did
LEFT JOIN bags_sp           b  ON b.lead        = rd.stack_lead_id
LEFT JOIN cpo_data_sp       cp ON cp.delivery_id = u.did
GROUP BY  ALL
ORDER BY fecha DESC,fleet_id;