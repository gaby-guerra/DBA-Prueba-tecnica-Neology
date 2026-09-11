# Modelo de Datos - Sistema de Estacionamiento

## Diagrama Entidad-Relación

```mermaid
erDiagram
    TIPO_VEHICULO ||--o{ VEHICULO : clasifica
    TIPO_VEHICULO ||--o{ TARIFA : define
    RESIDENTE ||--o{ VEHICULO : posee
    VEHICULO ||--o{ ESTANCIA : genera
    TARIFA ||--o{ ESTANCIA : aplica
    ESTANCIA ||--o| CARGO_PAGO : liquida
    RESIDENTE ||--o{ CIERRE_MENSUAL : liquida
    CIERRE_MENSUAL ||--o{ DETALLE_CIERRE_RESIDENTE : contiene
    ESTANCIA ||--o| DETALLE_CIERRE_RESIDENTE : agrupa

    TIPO_VEHICULO {
        int id_tipo_vehiculo PK
        varchar codigo UK
        varchar descripcion
        tinyint requiere_pago
    }

    RESIDENTE {
        int id_residente PK
        varchar nombre
        varchar numero_departamento
        varchar telefono
        tinyint activo
    }

    VEHICULO {
        varchar placa PK
        int id_tipo_vehiculo FK
        int id_residente FK
        varchar marca
        varchar modelo
        datetime fecha_registro
    }

    TARIFA {
        int id_tarifa PK
        int id_tipo_vehiculo FK
        decimal costo_por_minuto
        datetime fecha_inicio
        datetime fecha_fin
        tinyint activo
    }

    ESTANCIA {
        bigint id_estancia PK
        varchar placa FK
        int id_tarifa FK
        datetime fecha_entrada
        datetime fecha_salida
        int minutos_totales
        varchar estado
        varchar estancia_activa_uk UK
    }

    CARGO_PAGO {
        bigint id_pago PK
        bigint id_estancia FK
        int id_cierre FK
        decimal monto
        datetime fecha_pago
        varchar metodo_pago
    }

    CIERRE_MENSUAL {
        int id_cierre PK
        int id_residente FK
        int anio
        int mes
        int total_minutos
        decimal total_monto
        varchar estado
        datetime fecha_cierre
    }

    DETALLE_CIERRE_RESIDENTE {
        bigint id_detalle PK
        int id_cierre FK
        bigint id_estancia FK
        int minutos_facturados
        decimal monto_facturado
    }

    AUDITORIA_LOG {
        bigint id_auditoria PK
        varchar tabla_afectada
        varchar operacion
        varchar id_registro
        json datos_previos
        json datos_nuevos
        varchar usuario_bd
        datetime fecha_evento
    }
```