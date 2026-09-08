# Real DO Distances - Offline Impact Dashboard 🚀

Este repositorio contiene la solución completa de analítica e ingeniería de datos para el proyecto **Real DO Distances** de **PedidosYa**. El objetivo de este proyecto es medir y visualizar de manera offline el impacto del test de ruteo (*Switchback Test*) ejecutado del **02/09 al 15/09 de 2026** sobre las distancias de Pick Up (PU), Drop Off (DO), tiempos de entrega y calidad del servicio.

El proyecto está diseñado bajo una arquitectura de acoplamiento mínimo: la consulta SQL extrae los datos estructurados directamente desde Google BigQuery y el archivo HTML autónomo procesa y visualiza la información de forma local y 100% offline.

---

## 📂 Estructura del Repositorio

El repositorio se compone de los siguientes archivos clave:

*   **`Dashboard_Real_DO_Distances.html`**: El tablero interactivo principal. Es una aplicación web monopágina (SPA) de cliente que no requiere servidores ni bases de datos. Utiliza **Tailwind CSS** para su diseño visual premium y **Chart.js** para el renderizado interactivo de gráficos de líneas.
*   **`Query_BigQuery_Distances_Real_DO_Switchback.sql`**: La consulta en BigQuery optimizada para extraer tanto la sábana histórica (últimas 8 semanas de baseline de control) como el periodo del Switchback Test (segmentado por flotas de rollout).

---

## 🛠️ Características del Dashboard (`.html`)

1.  **Enfoque 100% Logístico y Operativo:**
    *   Sustitución de todas las métricas financieras (CPO) por indicadores físicos reales: **Delivery Time**, **Tasa de Stacking**, **Distancia PU (km)**, **Distancia DO (km)** y **Seamless (Tasa de Éxito)**.
    *   Soporte para visualización destacada de la variación porcentual ($\Delta$) junto a los valores absolutos de Test (`T`) y Control o Baseline (`C` / `L8W`) en tipografía monoespaciada (`font-mono`) de alta fidelidad.
2.  **Análisis por Buckets de Mean Delay (Saturación de Zona):**
    *   **Gráfico Izquierdo (Distancias):** Curvas suaves de líneas para comparar la evolución de la Distancia PU y Distancia DO promedio según los niveles de saturación en incrementos de 2 minutos. Cuenta con selectores dinámicos integrados en la cabecera.
    *   **Gráfico Derecho (Tiempos y Calidad):** Curvas suaves de líneas que comparan Delivery Time, Seamless % o Stacking % (en un distinguido tono morado `#A855F7`). Permite visualizar todas las variables juntas o aislar una métrica individual.
    *   **Share de Órdenes Fijo:** Curva de distribución de volumen dorada (`#F59E0B`) siempre presente en ambos gráficos en un eje secundario, permitiendo contextualizar el volumen real de la operación por nivel de saturación.
    *   **Líneas de Cuadrícula Inteligentes:** Ajuste dinámico de líneas de cuadrícula horizontales que se activan automáticamente si el eje primario izquierdo está oculto, manteniendo una estética limpia y homogénea en todo momento.
3.  **Tabla de Variación por Flota del Rollout:**
    *   Muestra un desglose granular de las flotas del rollout.
    *   Clasifica y ordena de manera **descendente** a las flotas según su **variación de distancia de Drop Off (`Var % Dist DO`)** para detectar desvíos operativos rápido.
    *   Formateo consistente de todos los indicadores de variación a exactamente **1 decimal** (ej: `+2.1%`, `-1.5 pp`).
4.  **Generación de Reportes Estáticos ("Congelar Tablero"):**
    *   Permite a los analistas cargar los datos de BigQuery, aplicar filtros y hacer clic en *"Congelar Tablero"*.
    *   Esto genera una descarga instantánea de un archivo HTML autocontenido con los datos codificados dentro de la variable `csvData`, perfecto para compartir reportes rápidos y congelados por Slack o correo electrónico.

---

## 📊 Arquitectura de la Query SQL (`.sql`)

La consulta BigQuery está optimizada para la extracción robusta del dataset:
*   **Periodo de Test:** Del 02/09 al 15/09 de 2026.
*   **Periodo de Baseline (L8W):** Del 08/07 al 01/09 de 2026.
*   **Alineación Temporal de Baseline:** Para cada flota, mapea y evalúa únicamente los mismos días de la semana (DOW - *Day of Week*) del baseline correspondientes a su calendario específico de control, evitando sesgos por estacionalidad de fin de semana.
*   **Compatibilidad de Formatos:** Extrae campos tanto de formatos agregados por hora/flota como campos individuales granulares, siendo totalmente autodetectado por el parser de SheetJS del HTML.

---

## 🚀 Instrucciones de Uso

### Paso 1: Extracción de Datos
1.  Abre tu consola de **Google BigQuery**.
2.  Ejecuta el código contenido en `Query_BigQuery_Distances_Real_DO_Switchback.sql`.
3.  Descarga los resultados en formato **CSV** o **Excel** (`.xlsx`).

### Paso 2: Visualización en el Dashboard
1.  Haz doble clic en `Dashboard_Real_DO_Distances.html` para abrirlo en cualquier navegador web moderno (Chrome, Safari, Firefox, Edge). *¡No requiere conexión a Internet!*
2.  Arrastra y suelta tu archivo descargado de BigQuery en la zona de carga (dropzone).
3.  El tablero clasificará automáticamente la información en base al calendario interno de control/treatment de las flotas del rollout.
4.  Utiliza los filtros de vertical (Food, Local Stores, Darkstores) y de flota del rollout para explorar la información.
5.  Haz clic en **"Congelar Tablero (Descargar)"** para guardar un reporte estático con la vista actual y enviárselo a tu equipo.
