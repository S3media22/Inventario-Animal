# 🐄 Inventario Finca — Sistema Ganadero y Avícola

Sistema web completo para la gestión de inventario animal en fincas ganaderas y avícolas.

## Módulos

- **Dashboard** — Resumen con estadísticas y gráficos en tiempo real
- **Bovinos** — Registro, búsqueda y filtrado de ganado
- **Avícolas** — Gestión de lotes de aves (ponedoras, engorde)
- **Producción de Leche** — Registro diario por turno (AM/PM) con gráficos
- **Producción de Huevos** — Control de producción por lote
- **Vacunación** — Calendario, alertas de próximas vacunas
- **Eventos de Salud** — Enfermedades, tratamientos, cirugías
- **Inseminación Artificial** — Seguimiento con estimación de parto
- **Reportes** — Estadísticas mensuales con gráficos

## Requisitos

- PHP 8.0+
- PostgreSQL 14+
- Servidor web (Apache/Nginx)

## Instalación

### 1. Base de datos

```bash
# Crear la base de datos
psql -U postgres -c "CREATE DATABASE inventario_finca;"

# Ejecutar el esquema
psql -U postgres -d inventario_finca -f database.sql
```

### 2. Configurar conexión

Editar `config/database.php` con los datos de tu servidor PostgreSQL:

```php
define('DB_HOST', 'localhost');
define('DB_PORT', '5432');
define('DB_NAME', 'inventario_finca');
define('DB_USER', 'postgres');
define('DB_PASS', 'tu_password');
```

### 3. Servidor web

Copiar todos los archivos a tu directorio web (ej: `/var/www/html/inventario-finca/`) y acceder desde el navegador.

### Modo Demo

El archivo `index.html` incluye un **modo demo** (`DEMO = true`) que funciona sin backend. Para conectar con PostgreSQL, cambiar `DEMO = false` en el JavaScript.

## Estructura

```
inventario-finca/
├── index.html          ← Aplicación frontend (SPA)
├── api.php             ← API REST PHP
├── database.sql        ← Esquema PostgreSQL + datos demo
├── config/
│   └── database.php    ← Configuración de conexión
└── README.md
```

## Tecnologías

- **Frontend**: HTML5, CSS3 (custom properties, grid, flexbox), JavaScript ES6+
- **Gráficos**: Chart.js 4
- **Backend**: PHP 8 con PDO
- **Base de datos**: PostgreSQL
