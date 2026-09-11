### Análisis de Optimización y Rendimiento

Este documento detalla el diagnóstico, plan de ejecución, propuesta de indexación, estrategia de particionamiento y correlación metodológica entre **MariaDB** y **Oracle Database** para entornos transaccionales con millones de registros.

---

### Selección de Consultas para Diagnóstico

Se evaluaron dos de las consultas críticas más propensas a cuellos de botella en alta concurrencia:
1. ***Consulta A*** (Consulta 2 - Cálculo de estancia e importe): Búsqueda individual recurrente en casetas de cobro/salida.
2. ***Consulta B*** (Consulta 8 - Top de vehículos con mayor permanencia en el mes): Proceso analítico masivo que agrupa millones de estancias finalizadas.

---

### Diagnóstico y Planes de Ejecución (Antes de la Optimización)

### ***Consulta A: Búsqueda y cálculo de importe:***

EXPLAIN EXTENDED
SELECT e.id_estancia, e.placa, e.fecha_entrada, e.fecha_salida, e.minutos_totales, e.id_tarifa
FROM estancia e
WHERE e.placa = 'RES-102';

***Hallazgo inicial:***
Si únicamente existe la llave foránea sobre placa, el optimizador realiza un Ref Scan sobre el índice secundario, pero debe realizar una operación de Bookmark Lookup / Clustered Index Read por cada fila para obtener fecha_entrada, fecha_salida y id_tarifa.
En una tabla de 10 millones de filas con un vehículo frecuente (cientos de registros), esto satura el buffer pool por lecturas aleatorias (random I/O).

---

### ***Consulta B: Top vehículos acumulados en el mes***

EXPLAIN EXTENDED
SELECT v.placa, SUM(e.minutos_totales) AS tiempo_total
FROM vehiculo v
INNER JOIN estancia e ON v.placa = e.placa
WHERE e.estado = 'FINALIZADA'
  AND e.fecha_salida >= '2026-08-01 00:00:00'
  AND e.fecha_salida <= '2026-08-31 23:59:59'
GROUP BY v.placa
ORDER BY tiempo_total DESC
LIMIT 10;

***Hallazgo inicial:***
Tipo de acceso: ALL (Full Table Scan) o escaneo de rango ineficiente si el índice solo tiene estado.
Cuello de botella: Using temporary; Using filesort. El motor descarga millones de registros a disco o memoria temporal para resolver la agregación SUM y el ordenamiento posterior ORDER BY.

---

### Propuesta de Índices y Justificación de Orden de Columnas

***Regla Aplicada:*** ESR (Equality, Sort/Range, Reference)

### ***Índice idx_estancia_placa_salida_cobro (placa, fecha_salida, fecha_entrada, id_tarifa)***
***Orden:***
- placa (Igualdad): Máxima cardinalidad; reduce el espacio de búsqueda al instante.
- fecha_salida (Condición IS NULL / Rango): Permite filtrar inmediatamente estancias activas.
- fecha_entrada, id_tarifa (Payload/Covering): Transforma la consulta en un Covering Index (Using index). No requiere acceder a la tabla base en disco.

### ***Índice idx_estancia_cierre_analitica (estado, fecha_salida, minutos_totales, placa, id_tarifa)***
***Orden:***
- estado (Igualdad): Filtra rápidamente solo registros 'FINALIZADA'.
- fecha_salida (Rango): Delimita el escaneo estrictamente a las páginas del mes consultado.
- minutos_totales, placa: Evitan I/O a disco para computar el SUM() y resolver el JOIN.

---

### Impacto de los Índices en Operaciones de Escritura (Trade-offs)

Todo índice secundario acelera lecturas, pero penaliza escrituras (INSERT, UPDATE, DELETE):

- ***Costo en INSERT:*** Cada acceso de vehículo a caseta debe insertar un nodo en el índice primario (B+Tree) y actualizar los árboles de idx_estancia_placa_salida_cobro e idx_estancia_cierre_analitica.
- ***Costo en UPDATE:*** Al registrar la salida (fecha_salida = NOW(), estado = 'FINALIZADA'), ambos índices compuestos se actualizan, obligando a reorganizar punteros en el B+Tree y arriesgando Page Splits (fragmentación de páginas InnoDB).

***Mitigación arquitectónica:***
- Mantener un factor de llenado (innodb_fill_factor) adecuado.
- No sobre-indexar: solo 2 índices compuestos bien diseñados resuelven el 90% de las consultas analíticas y transaccionales del módulo.

---

### Estrategia de particionamiento

Se sugiere en los casos que la tabla supera los 5 a 10 millones de registros. Lo más común es el particionamiento por rango mensual sobre la fecha de evento: PARTITION BY RANGE (TO_DAYS(fecha_entrada)).

---

### Análisis Equivalente en Oracle Database

### ***Obtención del Plan de Ejecución:***
En lugar del simple EXPLAIN, se utiliza DBMS_XPLAN.DISPLAY_CURSOR(format => 'ALLSTATS LAST') tras ejecutar la consulta con el hint /*+ GATHER_PLAN_STATISTICS */. Esto permite comparar las estimaciones del optimizador (E-Rows) contra la cardinalidad real (A-Rows) y los Consistent Gets (lecturas lógicas en memoria).

### ***Generación de Traza Profunda (SQL Trace & TKPROF):***
Mediante DBMS_MONITOR.SESSION_TRACE_ENABLE(waits => TRUE, binds => TRUE), capturando los eventos de espera exactos (db file sequential read vs db file scattered read) y procesando el archivo de traza con la utilidad tkprof para auditar el consumo exacto de CPU y tiempo transcurrido por fase (Parse, Execute, Fetch).

### ***Estructuras Avanzadas en Oracle:***
- ***Partitioning:*** Implementación nativa de INTERVAL PARTITIONING BY RANGE (fecha_entrada) INTERVAL (NUMTOYMINTERVAL(1, 'MONTH')), donde Oracle crea las particiones de los nuevos meses de forma 100% automática sin intervención de un DBA.
- ***Local vs Global Indexes:*** Creación de LOCAL INDEXES particionados alineados a las particiones de la tabla para garantizar que el mantenimiento de históricos no invalide los índices transaccionales vigentes.