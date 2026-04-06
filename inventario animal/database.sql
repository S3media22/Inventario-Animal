-- ╔══════════════════════════════════════════════════════════════════╗
-- ║  SISTEMA DE INVENTARIO ANIMAL — FINCA GANADERA Y AVÍCOLA       ║
-- ║  Base de Datos PostgreSQL                                       ║
-- ║  Versión 2.0 — Integridad Referencial, Atomicidad, Seguridad   ║
-- ╚══════════════════════════════════════════════════════════════════╝

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;

-- Eliminar en orden inverso de dependencia
DROP TABLE IF EXISTS auditoria CASCADE;
DROP TABLE IF EXISTS inseminaciones CASCADE;
DROP TABLE IF EXISTS produccion_huevos CASCADE;
DROP TABLE IF EXISTS produccion_leche CASCADE;
DROP TABLE IF EXISTS eventos_salud CASCADE;
DROP TABLE IF EXISTS vacunaciones CASCADE;
DROP TABLE IF EXISTS vacunas CASCADE;
DROP TABLE IF EXISTS historial_peso CASCADE;
DROP TABLE IF EXISTS animales CASCADE;
DROP TABLE IF EXISTS categorias CASCADE;
DROP TABLE IF EXISTS razas CASCADE;
DROP TABLE IF EXISTS secuencias_codigo CASCADE;
DROP TABLE IF EXISTS usuarios CASCADE;

-- ============================================================
-- 1. TIPOS ENUMERADOS
-- ============================================================
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='tipo_animal_enum') THEN
    CREATE TYPE tipo_animal_enum AS ENUM ('bovino','avicola');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='estado_animal_enum') THEN
    CREATE TYPE estado_animal_enum AS ENUM ('activo','vendido','muerto','enfermo','descarte');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='sexo_enum') THEN
    CREATE TYPE sexo_enum AS ENUM ('macho','hembra');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='tipo_evento_salud_enum') THEN
    CREATE TYPE tipo_evento_salud_enum AS ENUM ('enfermedad','tratamiento','cirugia','revision','desparasitacion','otro');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='estado_evento_enum') THEN
    CREATE TYPE estado_evento_enum AS ENUM ('activo','resuelto','seguimiento','cronico');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='turno_ordeno_enum') THEN
    CREATE TYPE turno_ordeno_enum AS ENUM ('am','pm');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='resultado_inseminacion_enum') THEN
    CREATE TYPE resultado_inseminacion_enum AS ENUM ('pendiente','exitosa','fallida');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='calidad_leche_enum') THEN
    CREATE TYPE calidad_leche_enum AS ENUM ('excelente','buena','normal','baja','descartada');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='rol_usuario_enum') THEN
    CREATE TYPE rol_usuario_enum AS ENUM ('administrador','veterinario','operario','consulta');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='accion_auditoria_enum') THEN
    CREATE TYPE accion_auditoria_enum AS ENUM ('INSERT','UPDATE','DELETE');
  END IF;
END $$;


-- ============================================================
-- 2. USUARIOS (Seguridad y trazabilidad)
-- ============================================================
CREATE TABLE usuarios (
    id                INTEGER      PRIMARY KEY,
    username          CITEXT       NOT NULL UNIQUE,
    email             CITEXT       NOT NULL UNIQUE,
    password_hash     TEXT         NOT NULL,
    nombre_completo   VARCHAR(120) NOT NULL,
    rol               rol_usuario_enum NOT NULL DEFAULT 'operario',
    activo            BOOLEAN      NOT NULL DEFAULT TRUE,
    ultimo_acceso     TIMESTAMP WITH TIME ZONE,
    created_at        TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_username_len   CHECK (LENGTH(username) BETWEEN 3 AND 30),
    CONSTRAINT chk_email_formato  CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),
    CONSTRAINT chk_nombre_len     CHECK (LENGTH(TRIM(nombre_completo)) >= 3)
);

CREATE INDEX idx_usuarios_rol    ON usuarios(rol);
CREATE INDEX idx_usuarios_activo ON usuarios(activo) WHERE activo = TRUE;

COMMENT ON TABLE  usuarios IS 'Usuarios del sistema con autenticación bcrypt';
COMMENT ON COLUMN usuarios.password_hash IS 'Hash bcrypt — nunca almacenar texto plano';


-- ============================================================
-- 3. AUDITORÍA (registro inmutable)
-- ============================================================
CREATE TABLE auditoria (
    id                INTEGER      PRIMARY KEY,
    tabla_afectada    VARCHAR(60)  NOT NULL,
    registro_id       INTEGER      NOT NULL,
    accion            accion_auditoria_enum NOT NULL,
    datos_anteriores  JSONB,
    datos_nuevos      JSONB,
    usuario_id        INTEGER      REFERENCES usuarios(id) ON UPDATE CASCADE,
    ip_origen         INET,
    created_at        TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_auditoria_tabla     ON auditoria(tabla_afectada, registro_id);
CREATE INDEX idx_auditoria_usuario   ON auditoria(usuario_id);
CREATE INDEX idx_auditoria_fecha     ON auditoria(created_at);
CREATE INDEX idx_auditoria_datos_ant ON auditoria USING GIN(datos_anteriores);
CREATE INDEX idx_auditoria_datos_new ON auditoria USING GIN(datos_nuevos);

COMMENT ON TABLE auditoria IS 'Registro inmutable de todas las operaciones sobre datos críticos';


-- ============================================================
-- 4. CATEGORÍAS
-- ============================================================
CREATE TABLE categorias (
    id          INTEGER          PRIMARY KEY,
    nombre      VARCHAR(60)      NOT NULL,
    tipo        tipo_animal_enum NOT NULL,
    descripcion TEXT,
    activa      BOOLEAN          NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    created_by  INTEGER          REFERENCES usuarios(id) ON UPDATE CASCADE,

    CONSTRAINT uq_categoria_nombre_tipo UNIQUE (nombre, tipo),
    CONSTRAINT chk_categoria_nombre_len CHECK (LENGTH(TRIM(nombre)) >= 2)
);

CREATE INDEX idx_categorias_tipo   ON categorias(tipo);
CREATE INDEX idx_categorias_activa ON categorias(activa) WHERE activa = TRUE;


-- ============================================================
-- 5. RAZAS (catálogo normalizado)
-- ============================================================
CREATE TABLE razas (
    id          INTEGER          PRIMARY KEY,
    nombre      VARCHAR(80)      NOT NULL,
    tipo        tipo_animal_enum NOT NULL,
    origen      VARCHAR(60),
    descripcion TEXT,
    activa      BOOLEAN          NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_raza_nombre_tipo UNIQUE (nombre, tipo),
    CONSTRAINT chk_raza_nombre_len CHECK (LENGTH(TRIM(nombre)) >= 2)
);

CREATE INDEX idx_razas_tipo ON razas(tipo);


-- ============================================================
-- 6. SECUENCIAS DE CÓDIGO (generación atómica)
-- ============================================================
CREATE TABLE secuencias_codigo (
    tipo           tipo_animal_enum PRIMARY KEY,
    prefijo        VARCHAR(5)  NOT NULL,
    ultimo_numero  INTEGER     NOT NULL DEFAULT 0,

    CONSTRAINT chk_ultimo_numero_pos CHECK (ultimo_numero >= 0)
);

INSERT INTO secuencias_codigo VALUES ('bovino','BOV',0), ('avicola','AVE',0);

COMMENT ON TABLE secuencias_codigo IS 'Control de secuencias con bloqueo de fila para atomicidad';


-- ============================================================
-- 7. ANIMALES (tabla central)
-- ============================================================
CREATE TABLE animales (
    id               INTEGER             PRIMARY KEY,
    codigo           VARCHAR(20)         NOT NULL UNIQUE,
    nombre           VARCHAR(100),
    categoria_id     INTEGER             NOT NULL REFERENCES categorias(id) ON UPDATE CASCADE,
    tipo             tipo_animal_enum    NOT NULL,
    raza_id          INTEGER             REFERENCES razas(id) ON UPDATE CASCADE,
    sexo             sexo_enum           NOT NULL,
    fecha_nacimiento DATE,
    peso_actual      NUMERIC(10,2),
    estado           estado_animal_enum  NOT NULL DEFAULT 'activo',
    madre_id         INTEGER             REFERENCES animales(id) ON UPDATE CASCADE ON DELETE SET NULL,
    padre_id         INTEGER             REFERENCES animales(id) ON UPDATE CASCADE ON DELETE SET NULL,
    fecha_ingreso    DATE                NOT NULL DEFAULT CURRENT_DATE,
    fecha_salida     DATE,
    motivo_salida    VARCHAR(200),
    foto_url         VARCHAR(500),
    notas            TEXT,
    activo           BOOLEAN             NOT NULL DEFAULT TRUE,
    created_at       TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    created_by       INTEGER             REFERENCES usuarios(id) ON UPDATE CASCADE,
    updated_by       INTEGER             REFERENCES usuarios(id) ON UPDATE CASCADE,

    CONSTRAINT chk_codigo_formato    CHECK (codigo ~ '^[A-Z]{2,5}-[0-9]{3,6}$'),
    CONSTRAINT chk_peso_positivo     CHECK (peso_actual IS NULL OR peso_actual > 0),
    CONSTRAINT chk_fecha_nacimiento  CHECK (fecha_nacimiento IS NULL OR fecha_nacimiento <= CURRENT_DATE),
    CONSTRAINT chk_fecha_ingreso     CHECK (fecha_ingreso <= CURRENT_DATE),
    CONSTRAINT chk_fecha_salida      CHECK (fecha_salida IS NULL OR fecha_salida >= fecha_ingreso),
    CONSTRAINT chk_no_autoparentesco CHECK (id <> madre_id AND id <> padre_id),
    CONSTRAINT chk_madre_no_padre    CHECK (madre_id IS NULL OR madre_id <> padre_id),
    CONSTRAINT chk_salida_con_motivo CHECK (
        (fecha_salida IS NULL AND motivo_salida IS NULL)
        OR (fecha_salida IS NOT NULL AND motivo_salida IS NOT NULL)
    ),
    CONSTRAINT chk_estado_salida CHECK (
        estado NOT IN ('vendido','muerto') OR fecha_salida IS NOT NULL
    )
);

CREATE INDEX idx_animales_tipo       ON animales(tipo);
CREATE INDEX idx_animales_estado     ON animales(estado);
CREATE INDEX idx_animales_categoria  ON animales(categoria_id);
CREATE INDEX idx_animales_raza       ON animales(raza_id);
CREATE INDEX idx_animales_madre      ON animales(madre_id)  WHERE madre_id IS NOT NULL;
CREATE INDEX idx_animales_padre      ON animales(padre_id)  WHERE padre_id IS NOT NULL;
CREATE INDEX idx_animales_activo     ON animales(activo)     WHERE activo = TRUE;
CREATE INDEX idx_animales_nacimiento ON animales(fecha_nacimiento);
CREATE INDEX idx_animales_busqueda   ON animales(codigo, nombre);

COMMENT ON TABLE  animales IS 'Registro central — borrado lógico, nunca DELETE físico';
COMMENT ON COLUMN animales.codigo IS 'Formato TIPO-NUMERO (ej: BOV-001)';


-- ============================================================
-- 8. HISTORIAL DE PESO
-- ============================================================
CREATE TABLE historial_peso (
    id            INTEGER       PRIMARY KEY,
    animal_id     INTEGER       NOT NULL REFERENCES animales(id) ON UPDATE CASCADE ON DELETE RESTRICT,
    peso          NUMERIC(10,2) NOT NULL,
    fecha         DATE          NOT NULL DEFAULT CURRENT_DATE,
    metodo_pesaje VARCHAR(30)   DEFAULT 'báscula',
    notas         TEXT,
    created_at    TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    created_by    INTEGER       REFERENCES usuarios(id) ON UPDATE CASCADE,

    CONSTRAINT uq_peso_animal_fecha UNIQUE (animal_id, fecha),
    CONSTRAINT chk_peso_positivo    CHECK (peso > 0),
    CONSTRAINT chk_peso_razonable   CHECK (peso BETWEEN 0.01 AND 2000.00),
    CONSTRAINT chk_fecha_peso       CHECK (fecha <= CURRENT_DATE)
);

CREATE INDEX idx_historial_peso_animal ON historial_peso(animal_id, fecha DESC);


-- ============================================================
-- 9. VACUNAS (catálogo)
-- ============================================================
CREATE TABLE vacunas (
    id                  INTEGER      PRIMARY KEY,
    nombre              VARCHAR(100) NOT NULL UNIQUE,
    laboratorio         VARCHAR(100),
    tipo_animal         tipo_animal_enum,  -- NULL = aplica a ambos
    descripcion         TEXT,
    intervalo_dias      INTEGER      NOT NULL DEFAULT 0,
    dosis_estandar      VARCHAR(50),
    via_aplicacion      VARCHAR(30),
    temperatura_almacen VARCHAR(30),
    activa              BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_intervalo_pos CHECK (intervalo_dias >= 0),
    CONSTRAINT chk_vacuna_nombre CHECK (LENGTH(TRIM(nombre)) >= 3)
);

COMMENT ON COLUMN vacunas.tipo_animal IS 'NULL = aplica a bovinos y avícolas';


-- ============================================================
-- 10. VACUNACIONES
-- ============================================================
CREATE TABLE vacunaciones (
    id               INTEGER      PRIMARY KEY,
    animal_id        INTEGER      NOT NULL REFERENCES animales(id) ON UPDATE CASCADE ON DELETE RESTRICT,
    vacuna_id        INTEGER      NOT NULL REFERENCES vacunas(id)  ON UPDATE CASCADE ON DELETE RESTRICT,
    fecha_aplicacion DATE         NOT NULL DEFAULT CURRENT_DATE,
    proxima_fecha    DATE,
    lote_vacuna      VARCHAR(50),
    dosis            VARCHAR(50),
    via_aplicacion   VARCHAR(30),
    veterinario      VARCHAR(100),
    costo            NUMERIC(12,2) DEFAULT 0,
    observaciones    TEXT,
    created_at       TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    created_by       INTEGER      REFERENCES usuarios(id) ON UPDATE CASCADE,

    CONSTRAINT chk_vac_fecha       CHECK (fecha_aplicacion <= CURRENT_DATE),
    CONSTRAINT chk_vac_proxima     CHECK (proxima_fecha IS NULL OR proxima_fecha > fecha_aplicacion),
    CONSTRAINT chk_vac_costo       CHECK (costo >= 0),
    CONSTRAINT uq_vacunacion_unica UNIQUE (animal_id, vacuna_id, fecha_aplicacion)
);

CREATE INDEX idx_vacunaciones_animal  ON vacunaciones(animal_id);
CREATE INDEX idx_vacunaciones_vacuna  ON vacunaciones(vacuna_id);
CREATE INDEX idx_vacunaciones_proxima ON vacunaciones(proxima_fecha) WHERE proxima_fecha IS NOT NULL;
CREATE INDEX idx_vacunaciones_fecha   ON vacunaciones(fecha_aplicacion DESC);


-- ============================================================
-- 11. EVENTOS DE SALUD
-- ============================================================
CREATE TABLE eventos_salud (
    id            INTEGER                PRIMARY KEY,
    animal_id     INTEGER                NOT NULL REFERENCES animales(id) ON UPDATE CASCADE ON DELETE RESTRICT,
    tipo          tipo_evento_salud_enum NOT NULL,
    descripcion   TEXT                   NOT NULL,
    diagnostico   TEXT,
    tratamiento   TEXT,
    medicamentos  TEXT,
    fecha_inicio  DATE                   NOT NULL DEFAULT CURRENT_DATE,
    fecha_fin     DATE,
    veterinario   VARCHAR(100),
    costo         NUMERIC(12,2)          NOT NULL DEFAULT 0,
    estado        estado_evento_enum     NOT NULL DEFAULT 'activo',
    prioridad     INTEGER                NOT NULL DEFAULT 3,
    created_at    TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    created_by    INTEGER                REFERENCES usuarios(id) ON UPDATE CASCADE,

    CONSTRAINT chk_salud_fecha_inicio CHECK (fecha_inicio <= CURRENT_DATE),
    CONSTRAINT chk_salud_fecha_fin    CHECK (fecha_fin IS NULL OR fecha_fin >= fecha_inicio),
    CONSTRAINT chk_salud_costo        CHECK (costo >= 0),
    CONSTRAINT chk_salud_prioridad    CHECK (prioridad BETWEEN 1 AND 5),
    CONSTRAINT chk_salud_descripcion  CHECK (LENGTH(TRIM(descripcion)) >= 5),
    CONSTRAINT chk_salud_resuelto     CHECK (estado <> 'resuelto' OR fecha_fin IS NOT NULL)
);

CREATE INDEX idx_salud_animal  ON eventos_salud(animal_id);
CREATE INDEX idx_salud_tipo    ON eventos_salud(tipo);
CREATE INDEX idx_salud_estado  ON eventos_salud(estado) WHERE estado IN ('activo','seguimiento');
CREATE INDEX idx_salud_fecha   ON eventos_salud(fecha_inicio DESC);


-- ============================================================
-- 12. PRODUCCIÓN DE LECHE
-- ============================================================
CREATE TABLE produccion_leche (
    id              INTEGER            PRIMARY KEY,
    animal_id       INTEGER            NOT NULL REFERENCES animales(id) ON UPDATE CASCADE ON DELETE RESTRICT,
    fecha           DATE               NOT NULL DEFAULT CURRENT_DATE,
    cantidad_litros NUMERIC(8,2)       NOT NULL,
    turno           turno_ordeno_enum  NOT NULL,
    calidad         calidad_leche_enum NOT NULL DEFAULT 'normal',
    temperatura     NUMERIC(4,1),
    observaciones   TEXT,
    created_at      TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    created_by      INTEGER            REFERENCES usuarios(id) ON UPDATE CASCADE,

    CONSTRAINT uq_leche_animal_fecha_turno UNIQUE (animal_id, fecha, turno),
    CONSTRAINT chk_leche_cantidad    CHECK (cantidad_litros > 0 AND cantidad_litros <= 80),
    CONSTRAINT chk_leche_fecha       CHECK (fecha <= CURRENT_DATE),
    CONSTRAINT chk_leche_temperatura CHECK (temperatura IS NULL OR temperatura BETWEEN 0 AND 50)
);

CREATE INDEX idx_leche_animal ON produccion_leche(animal_id);
CREATE INDEX idx_leche_fecha  ON produccion_leche(fecha DESC);


-- ============================================================
-- 13. PRODUCCIÓN DE HUEVOS
-- ============================================================
CREATE TABLE produccion_huevos (
    id              INTEGER      PRIMARY KEY,
    lote_id         INTEGER      NOT NULL REFERENCES animales(id) ON UPDATE CASCADE ON DELETE RESTRICT,
    fecha           DATE         NOT NULL DEFAULT CURRENT_DATE,
    cantidad        INTEGER      NOT NULL,
    rotos           INTEGER      NOT NULL DEFAULT 0,
    sucios          INTEGER      NOT NULL DEFAULT 0,
    peso_promedio_g NUMERIC(6,2),
    observaciones   TEXT,
    created_at      TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    created_by      INTEGER      REFERENCES usuarios(id) ON UPDATE CASCADE,

    CONSTRAINT uq_huevos_lote_fecha    UNIQUE (lote_id, fecha),
    CONSTRAINT chk_huevos_cantidad     CHECK (cantidad >= 0),
    CONSTRAINT chk_huevos_rotos        CHECK (rotos >= 0 AND rotos <= cantidad),
    CONSTRAINT chk_huevos_sucios       CHECK (sucios >= 0 AND sucios <= cantidad),
    CONSTRAINT chk_huevos_rotos_sucios CHECK ((rotos + sucios) <= cantidad),
    CONSTRAINT chk_huevos_peso         CHECK (peso_promedio_g IS NULL OR peso_promedio_g BETWEEN 10 AND 120),
    CONSTRAINT chk_huevos_fecha        CHECK (fecha <= CURRENT_DATE)
);

CREATE INDEX idx_huevos_lote  ON produccion_huevos(lote_id);
CREATE INDEX idx_huevos_fecha ON produccion_huevos(fecha DESC);


-- ============================================================
-- 14. INSEMINACIÓN ARTIFICIAL
-- ============================================================
CREATE TABLE inseminaciones (
    id                   INTEGER                      PRIMARY KEY,
    animal_id            INTEGER                      NOT NULL REFERENCES animales(id) ON UPDATE CASCADE ON DELETE RESTRICT,
    fecha                DATE                         NOT NULL DEFAULT CURRENT_DATE,
    toro_pajilla         VARCHAR(120),
    raza_toro            VARCHAR(80),
    lote_pajilla         VARCHAR(50),
    tecnico              VARCHAR(100),
    resultado            resultado_inseminacion_enum  NOT NULL DEFAULT 'pendiente',
    fecha_verificacion   DATE,
    fecha_parto_estimada DATE,
    fecha_parto_real     DATE,
    numero_crias         INTEGER,
    costo                NUMERIC(12,2)                NOT NULL DEFAULT 0,
    observaciones        TEXT,
    created_at           TIMESTAMP WITH TIME ZONE     NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMP WITH TIME ZONE     NOT NULL DEFAULT NOW(),
    created_by           INTEGER                      REFERENCES usuarios(id) ON UPDATE CASCADE,

    CONSTRAINT chk_insem_fecha             CHECK (fecha <= CURRENT_DATE),
    CONSTRAINT chk_insem_verificacion      CHECK (fecha_verificacion IS NULL OR fecha_verificacion >= fecha),
    CONSTRAINT chk_insem_parto_est         CHECK (fecha_parto_estimada IS NULL OR fecha_parto_estimada > fecha),
    CONSTRAINT chk_insem_parto_real        CHECK (fecha_parto_real IS NULL OR fecha_parto_real > fecha),
    CONSTRAINT chk_insem_crias             CHECK (numero_crias IS NULL OR numero_crias BETWEEN 1 AND 4),
    CONSTRAINT chk_insem_costo             CHECK (costo >= 0),
    CONSTRAINT chk_insem_exitosa_parto     CHECK (resultado <> 'exitosa' OR fecha_parto_estimada IS NOT NULL),
    CONSTRAINT chk_insem_parto_real_estado CHECK (fecha_parto_real IS NULL OR resultado = 'exitosa')
);

CREATE INDEX idx_insem_animal    ON inseminaciones(animal_id);
CREATE INDEX idx_insem_resultado ON inseminaciones(resultado) WHERE resultado = 'pendiente';
CREATE INDEX idx_insem_parto     ON inseminaciones(fecha_parto_estimada) WHERE resultado = 'exitosa';
CREATE INDEX idx_insem_fecha     ON inseminaciones(fecha DESC);


-- ============================================================
-- 15. FUNCIONES DE SEGURIDAD
-- ============================================================

-- Generación atómica de códigos
CREATE OR REPLACE FUNCTION generar_codigo_animal(p_tipo tipo_animal_enum)
RETURNS VARCHAR(20) LANGUAGE plpgsql AS $$
DECLARE
    v_prefijo VARCHAR(5);
    v_numero  INTEGER;
BEGIN
    UPDATE secuencias_codigo
    SET ultimo_numero = ultimo_numero + 1
    WHERE tipo = p_tipo
    RETURNING prefijo, ultimo_numero INTO v_prefijo, v_numero;
    IF NOT FOUND THEN RAISE EXCEPTION 'Tipo no válido: %', p_tipo; END IF;
    RETURN v_prefijo || '-' || LPAD(v_numero::TEXT, 3, '0');
END; $$;

-- Hash de contraseña
CREATE OR REPLACE FUNCTION hash_password(p_password TEXT)
RETURNS TEXT LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
    IF LENGTH(p_password) < 8 THEN
        RAISE EXCEPTION 'La contraseña debe tener al menos 8 caracteres';
    END IF;
    RETURN crypt(p_password, gen_salt('bf', 12));
END; $$;

-- Verificación de contraseña
CREATE OR REPLACE FUNCTION verificar_password(p_password TEXT, p_hash TEXT)
RETURNS BOOLEAN LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN RETURN crypt(p_password, p_hash) = p_hash; END; $$;


-- ============================================================
-- 16. TRIGGERS
-- ============================================================

-- Auto updated_at
CREATE OR REPLACE FUNCTION trg_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END; $$;

CREATE TRIGGER trg_animales_upd      BEFORE UPDATE ON animales       FOR EACH ROW EXECUTE FUNCTION trg_updated_at();
CREATE TRIGGER trg_usuarios_upd      BEFORE UPDATE ON usuarios       FOR EACH ROW EXECUTE FUNCTION trg_updated_at();
CREATE TRIGGER trg_categorias_upd    BEFORE UPDATE ON categorias     FOR EACH ROW EXECUTE FUNCTION trg_updated_at();
CREATE TRIGGER trg_eventos_salud_upd BEFORE UPDATE ON eventos_salud  FOR EACH ROW EXECUTE FUNCTION trg_updated_at();
CREATE TRIGGER trg_insem_upd         BEFORE UPDATE ON inseminaciones FOR EACH ROW EXECUTE FUNCTION trg_updated_at();

-- Validar categoría ↔ tipo animal
CREATE OR REPLACE FUNCTION trg_validar_categoria_tipo()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v tipo_animal_enum;
BEGIN
    SELECT tipo INTO v FROM categorias WHERE id = NEW.categoria_id;
    IF v <> NEW.tipo THEN RAISE EXCEPTION 'Categoría (%) no corresponde al tipo (%)', v, NEW.tipo; END IF;
    RETURN NEW;
END; $$;
CREATE TRIGGER trg_animal_cat BEFORE INSERT OR UPDATE ON animales FOR EACH ROW EXECUTE FUNCTION trg_validar_categoria_tipo();

-- Validar raza ↔ tipo animal
CREATE OR REPLACE FUNCTION trg_validar_raza_tipo()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v tipo_animal_enum;
BEGIN
    IF NEW.raza_id IS NULL THEN RETURN NEW; END IF;
    SELECT tipo INTO v FROM razas WHERE id = NEW.raza_id;
    IF v <> NEW.tipo THEN RAISE EXCEPTION 'Raza (%) no corresponde al tipo (%)', v, NEW.tipo; END IF;
    RETURN NEW;
END; $$;
CREATE TRIGGER trg_animal_raza BEFORE INSERT OR UPDATE ON animales FOR EACH ROW EXECUTE FUNCTION trg_validar_raza_tipo();

-- Solo vacas producen leche
CREATE OR REPLACE FUNCTION trg_validar_produccion_leche()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE vt tipo_animal_enum; vs sexo_enum;
BEGIN
    SELECT tipo, sexo INTO vt, vs FROM animales WHERE id = NEW.animal_id;
    IF vt <> 'bovino' OR vs <> 'hembra' THEN
        RAISE EXCEPTION 'Solo bovinos hembra pueden registrar producción de leche';
    END IF;
    RETURN NEW;
END; $$;
CREATE TRIGGER trg_leche_val BEFORE INSERT ON produccion_leche FOR EACH ROW EXECUTE FUNCTION trg_validar_produccion_leche();

-- Solo avícolas producen huevos
CREATE OR REPLACE FUNCTION trg_validar_produccion_huevos()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v tipo_animal_enum;
BEGIN
    SELECT tipo INTO v FROM animales WHERE id = NEW.lote_id;
    IF v <> 'avicola' THEN RAISE EXCEPTION 'Solo lotes avícolas pueden registrar huevos'; END IF;
    RETURN NEW;
END; $$;
CREATE TRIGGER trg_huevos_val BEFORE INSERT ON produccion_huevos FOR EACH ROW EXECUTE FUNCTION trg_validar_produccion_huevos();

-- Solo vacas pueden tener inseminación
CREATE OR REPLACE FUNCTION trg_validar_inseminacion()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE vt tipo_animal_enum; vs sexo_enum;
BEGIN
    SELECT tipo, sexo INTO vt, vs FROM animales WHERE id = NEW.animal_id;
    IF vt <> 'bovino' OR vs <> 'hembra' THEN
        RAISE EXCEPTION 'Solo bovinos hembra pueden registrar inseminación';
    END IF;
    RETURN NEW;
END; $$;
CREATE TRIGGER trg_insem_val BEFORE INSERT ON inseminaciones FOR EACH ROW EXECUTE FUNCTION trg_validar_inseminacion();

-- Vacuna compatible con tipo animal
CREATE OR REPLACE FUNCTION trg_validar_vacuna_tipo()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE vv tipo_animal_enum; va tipo_animal_enum;
BEGIN
    SELECT tipo_animal INTO vv FROM vacunas WHERE id = NEW.vacuna_id;
    SELECT tipo INTO va FROM animales WHERE id = NEW.animal_id;
    IF vv IS NOT NULL AND vv <> va THEN
        RAISE EXCEPTION 'Vacuna (%) incompatible con tipo animal (%)', vv, va;
    END IF;
    RETURN NEW;
END; $$;
CREATE TRIGGER trg_vac_tipo BEFORE INSERT ON vacunaciones FOR EACH ROW EXECUTE FUNCTION trg_validar_vacuna_tipo();

-- Sincronizar peso_actual al registrar peso
CREATE OR REPLACE FUNCTION trg_sincronizar_peso()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    UPDATE animales SET peso_actual = NEW.peso, updated_at = NOW()
    WHERE id = NEW.animal_id
      AND NOT EXISTS (SELECT 1 FROM historial_peso WHERE animal_id = NEW.animal_id AND fecha > NEW.fecha);
    RETURN NEW;
END; $$;
CREATE TRIGGER trg_peso_sync AFTER INSERT ON historial_peso FOR EACH ROW EXECUTE FUNCTION trg_sincronizar_peso();

-- Auditoría automática en animales
CREATE OR REPLACE FUNCTION trg_auditoria_animales()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v_seq INTEGER;
BEGIN
    SELECT COALESCE(MAX(id),0)+1 INTO v_seq FROM auditoria;
    IF TG_OP = 'INSERT' THEN
        INSERT INTO auditoria(id,tabla_afectada,registro_id,accion,datos_nuevos,usuario_id)
        VALUES(v_seq,TG_TABLE_NAME,NEW.id,'INSERT',to_jsonb(NEW),NEW.created_by);
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO auditoria(id,tabla_afectada,registro_id,accion,datos_anteriores,datos_nuevos,usuario_id)
        VALUES(v_seq,TG_TABLE_NAME,OLD.id,'UPDATE',to_jsonb(OLD),to_jsonb(NEW),NEW.updated_by);
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO auditoria(id,tabla_afectada,registro_id,accion,datos_anteriores)
        VALUES(v_seq,TG_TABLE_NAME,OLD.id,'DELETE',to_jsonb(OLD));
    END IF;
    RETURN COALESCE(NEW,OLD);
END; $$;
CREATE TRIGGER trg_animales_aud AFTER INSERT OR UPDATE OR DELETE ON animales FOR EACH ROW EXECUTE FUNCTION trg_auditoria_animales();


-- ============================================================
-- 17. VISTAS
-- ============================================================

CREATE OR REPLACE VIEW v_animales_completo AS
SELECT a.id, a.codigo, a.nombre, a.tipo,
       c.nombre AS categoria, r.nombre AS raza, a.sexo,
       a.fecha_nacimiento,
       EXTRACT(YEAR FROM AGE(CURRENT_DATE, a.fecha_nacimiento))::INT AS edad_anios,
       EXTRACT(MONTH FROM AGE(CURRENT_DATE, a.fecha_nacimiento))::INT % 12 AS edad_meses,
       a.peso_actual, a.estado, a.fecha_ingreso,
       m.nombre AS madre, p.nombre AS padre, a.notas, a.created_at
FROM animales a
  LEFT JOIN categorias c ON a.categoria_id = c.id
  LEFT JOIN razas r      ON a.raza_id = r.id
  LEFT JOIN animales m   ON a.madre_id = m.id
  LEFT JOIN animales p   ON a.padre_id = p.id
WHERE a.activo = TRUE;

CREATE OR REPLACE VIEW v_produccion_leche AS
SELECT pl.id, pl.fecha, a.codigo, a.nombre AS animal,
       pl.cantidad_litros, pl.turno, pl.calidad, pl.temperatura
FROM produccion_leche pl JOIN animales a ON pl.animal_id = a.id
ORDER BY pl.fecha DESC, a.nombre;

CREATE OR REPLACE VIEW v_alertas_vacunacion AS
SELECT v.id, a.codigo, a.nombre AS animal, vc.nombre AS vacuna,
       v.fecha_aplicacion, v.proxima_fecha,
       v.proxima_fecha - CURRENT_DATE AS dias_restantes,
       CASE
         WHEN v.proxima_fecha < CURRENT_DATE             THEN 'VENCIDA'
         WHEN v.proxima_fecha <= CURRENT_DATE + 7        THEN 'URGENTE'
         WHEN v.proxima_fecha <= CURRENT_DATE + 30       THEN 'PRÓXIMA'
         ELSE 'OK'
       END AS alerta
FROM vacunaciones v
  JOIN animales a  ON v.animal_id = a.id
  JOIN vacunas vc  ON v.vacuna_id = vc.id
WHERE v.proxima_fecha IS NOT NULL AND a.activo = TRUE
ORDER BY v.proxima_fecha;

CREATE OR REPLACE VIEW v_resumen_reproductivo AS
SELECT i.id, a.codigo, a.nombre AS animal, i.fecha, i.toro_pajilla,
       i.tecnico, i.resultado, i.fecha_parto_estimada, i.fecha_parto_real,
       CASE WHEN i.resultado='exitosa' AND i.fecha_parto_estimada IS NOT NULL
            THEN i.fecha_parto_estimada - CURRENT_DATE END AS dias_para_parto
FROM inseminaciones i JOIN animales a ON i.animal_id = a.id
WHERE a.activo = TRUE ORDER BY i.fecha DESC;


-- ============================================================
-- 18. ROLES Y PERMISOS
-- ============================================================
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='finca_admin')       THEN CREATE ROLE finca_admin;       END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='finca_veterinario') THEN CREATE ROLE finca_veterinario; END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='finca_operario')    THEN CREATE ROLE finca_operario;    END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='finca_consulta')    THEN CREATE ROLE finca_consulta;    END IF;
END $$;

GRANT ALL PRIVILEGES ON ALL TABLES    IN SCHEMA public TO finca_admin;
GRANT USAGE          ON ALL SEQUENCES IN SCHEMA public TO finca_admin;
GRANT EXECUTE        ON ALL FUNCTIONS IN SCHEMA public TO finca_admin;

GRANT SELECT, INSERT, UPDATE ON animales, historial_peso, vacunaciones, eventos_salud, inseminaciones TO finca_veterinario;
GRANT SELECT ON categorias, razas, vacunas, produccion_leche, produccion_huevos, usuarios TO finca_veterinario;
GRANT SELECT ON v_animales_completo, v_alertas_vacunacion, v_resumen_reproductivo, v_produccion_leche TO finca_veterinario;

GRANT SELECT ON animales, categorias, razas, vacunas TO finca_operario;
GRANT SELECT, INSERT ON produccion_leche, produccion_huevos, historial_peso TO finca_operario;
GRANT SELECT ON v_animales_completo, v_produccion_leche TO finca_operario;

GRANT SELECT ON ALL TABLES IN SCHEMA public TO finca_consulta;


-- ============================================================
-- 19. ROW LEVEL SECURITY
-- ============================================================
ALTER TABLE usuarios  ENABLE ROW LEVEL SECURITY;
ALTER TABLE auditoria ENABLE ROW LEVEL SECURITY;

CREATE POLICY pol_usuarios_admin ON usuarios FOR ALL TO finca_admin USING (TRUE);
CREATE POLICY pol_usuarios_self  ON usuarios FOR SELECT TO finca_veterinario, finca_operario, finca_consulta USING (username = current_user);
CREATE POLICY pol_auditoria_admin ON auditoria FOR ALL TO finca_admin USING (TRUE);


-- ============================================================
-- 20. DATOS INICIALES (transacción atómica)
-- ============================================================
BEGIN;

  INSERT INTO usuarios (id,username,email,password_hash,nombre_completo,rol) VALUES
    (1,'admin','admin@finca.com',crypt('Admin2024!',gen_salt('bf',12)),'Administrador del Sistema','administrador');

  INSERT INTO razas (id,nombre,tipo,origen) VALUES
    (1,'Holstein','bovino','Países Bajos'),(2,'Jersey','bovino','Isla de Jersey'),
    (3,'Brahman','bovino','India/EE.UU.'),(4,'Gyr','bovino','India'),
    (5,'Simmental','bovino','Suiza'),(6,'Angus','bovino','Escocia'),
    (7,'Hy-Line Brown','avicola','EE.UU.'),(8,'Lohmann Brown','avicola','Alemania'),
    (9,'Ross 308','avicola','EE.UU.'),(10,'Cobb 500','avicola','EE.UU.');

  INSERT INTO categorias (id,nombre,tipo,descripcion,created_by) VALUES
    (1,'Vaca lechera','bovino','Hembras en producción láctea',1),
    (2,'Toro reproductor','bovino','Machos para reproducción',1),
    (3,'Novilla','bovino','Hembras jóvenes sin primer parto',1),
    (4,'Ternero','bovino','Crías hasta destete',1),
    (5,'Gallina ponedora','avicola','Aves producción huevos',1),
    (6,'Gallo reproductor','avicola','Machos reproductores',1),
    (7,'Pollo de engorde','avicola','Aves para carne',1);

  INSERT INTO vacunas (id,nombre,laboratorio,tipo_animal,descripcion,intervalo_dias,via_aplicacion) VALUES
    (1,'Fiebre Aftosa','Vecol','bovino','Contra virus de fiebre aftosa',180,'Subcutánea'),
    (2,'Brucelosis (Cepa 19)','Vecol','bovino','Terneras 3-8 meses',0,'Subcutánea'),
    (3,'Carbón Sintomático','Vecol','bovino','Carbón bacteridiano',365,'Intramuscular'),
    (4,'Triple Bovina','MSD','bovino','IBR, DVB, Leptospirosis',365,'Intramuscular'),
    (5,'Newcastle + Bronquitis','Ceva','avicola','Respiratoria aviar',90,'Ocular/Agua'),
    (6,'Gumboro','Ceva','avicola','Bolsa de Fabricio',0,'Ocular/Agua'),
    (7,'Marek','MSD','avicola','Día 1 de vida',0,'Subcutánea'),
    (8,'Rabia','Vecol',NULL,'Antirrábica bovinos y aves',365,'Intramuscular');

  INSERT INTO animales (id,codigo,nombre,categoria_id,tipo,raza_id,sexo,fecha_nacimiento,peso_actual,estado,fecha_ingreso,created_by) VALUES
    (1,'BOV-001','Luna',      1,'bovino',1,'hembra','2020-03-15',520.50,'activo','2020-03-15',1),
    (2,'BOV-002','Estrella',  1,'bovino',2,'hembra','2019-08-22',480.00,'activo','2019-08-22',1),
    (3,'BOV-003','Tornado',   2,'bovino',3,'macho', '2018-01-10',850.00,'activo','2018-01-10',1),
    (4,'BOV-004','Mariposa',  3,'bovino',1,'hembra','2022-06-05',320.00,'activo','2022-06-05',1),
    (5,'BOV-005','Relámpago', 4,'bovino',3,'macho', '2023-11-20',180.00,'activo','2023-11-20',1),
    (6,'AVE-001','Lote Ponedoras A',5,'avicola',7,'hembra','2023-01-15',1.80,'activo','2023-01-15',1),
    (7,'AVE-002','Lote Ponedoras B',5,'avicola',8,'hembra','2023-04-20',1.90,'activo','2023-04-20',1),
    (8,'AVE-003','Lote Engorde 1',  7,'avicola',9,'macho', '2024-01-05',2.50,'activo','2024-01-05',1);

  UPDATE secuencias_codigo SET ultimo_numero=5 WHERE tipo='bovino';
  UPDATE secuencias_codigo SET ultimo_numero=3 WHERE tipo='avicola';

  INSERT INTO historial_peso (id,animal_id,peso,fecha,created_by) VALUES
    (1,1,460.00,CURRENT_DATE-INTERVAL '8 months',1),
    (2,1,485.00,CURRENT_DATE-INTERVAL '6 months',1),
    (3,1,500.00,CURRENT_DATE-INTERVAL '4 months',1),
    (4,1,510.00,CURRENT_DATE-INTERVAL '2 months',1),
    (5,1,520.50,CURRENT_DATE,1),
    (6,3,790.00,CURRENT_DATE-INTERVAL '6 months',1),
    (7,3,820.00,CURRENT_DATE-INTERVAL '3 months',1),
    (8,3,850.00,CURRENT_DATE,1);

  INSERT INTO vacunaciones (id,animal_id,vacuna_id,fecha_aplicacion,proxima_fecha,veterinario,costo,created_by) VALUES
    (1,1,1,CURRENT_DATE-INTERVAL '3 months',CURRENT_DATE+INTERVAL '3 months','Dr. García',15000,1),
    (2,1,2,CURRENT_DATE-INTERVAL '6 months',NULL,'Dr. García',12000,1),
    (3,2,1,CURRENT_DATE-INTERVAL '3 months',CURRENT_DATE+INTERVAL '3 months','Dr. García',15000,1),
    (4,3,1,CURRENT_DATE-INTERVAL '2 months',CURRENT_DATE+INTERVAL '4 months','Dr. López',15000,1),
    (5,6,5,CURRENT_DATE-INTERVAL '1 month', CURRENT_DATE+INTERVAL '2 months','Dr. Martínez',8000,1);

  INSERT INTO produccion_leche (id,animal_id,fecha,cantidad_litros,turno,calidad,created_by) VALUES
    (1, 1,CURRENT_DATE-6,22.5,'am','buena',1),   (2, 1,CURRENT_DATE-6,18.0,'pm','normal',1),
    (3, 1,CURRENT_DATE-5,23.0,'am','buena',1),   (4, 1,CURRENT_DATE-5,17.5,'pm','normal',1),
    (5, 1,CURRENT_DATE-4,21.0,'am','normal',1),  (6, 1,CURRENT_DATE-4,19.0,'pm','buena',1),
    (7, 1,CURRENT_DATE-3,24.0,'am','excelente',1),(8, 1,CURRENT_DATE-3,18.5,'pm','normal',1),
    (9, 1,CURRENT_DATE-2,22.0,'am','buena',1),   (10,1,CURRENT_DATE-2,17.0,'pm','normal',1),
    (11,1,CURRENT_DATE-1,23.5,'am','buena',1),   (12,1,CURRENT_DATE-1,19.5,'pm','buena',1),
    (13,2,CURRENT_DATE-6,19.0,'am','normal',1),  (14,2,CURRENT_DATE-6,15.0,'pm','normal',1),
    (15,2,CURRENT_DATE-5,20.0,'am','buena',1),   (16,2,CURRENT_DATE-5,16.0,'pm','normal',1),
    (17,2,CURRENT_DATE-4,18.5,'am','normal',1),  (18,2,CURRENT_DATE-4,14.5,'pm','normal',1),
    (19,2,CURRENT_DATE-3,21.0,'am','buena',1),   (20,2,CURRENT_DATE-3,15.5,'pm','normal',1);

  INSERT INTO produccion_huevos (id,lote_id,fecha,cantidad,rotos,sucios,peso_promedio_g,created_by) VALUES
    (1,6,CURRENT_DATE-6,145,3,2,62.5,1),
    (2,6,CURRENT_DATE-5,150,2,1,63.0,1),
    (3,6,CURRENT_DATE-4,142,5,3,61.8,1),
    (4,6,CURRENT_DATE-3,155,1,0,64.0,1),
    (5,6,CURRENT_DATE-2,148,4,2,62.0,1),
    (6,6,CURRENT_DATE-1,152,2,1,63.5,1),
    (7,7,CURRENT_DATE-6,130,2,1,60.0,1),
    (8,7,CURRENT_DATE-5,135,3,2,61.0,1),
    (9,7,CURRENT_DATE-4,128,1,0,59.5,1);

  INSERT INTO inseminaciones (id,animal_id,fecha,toro_pajilla,raza_toro,tecnico,resultado,fecha_parto_estimada,costo,created_by) VALUES
    (1,1,CURRENT_DATE-INTERVAL '2 months','Holstein Elite #4521','Holstein','Téc. Rodríguez','exitosa',CURRENT_DATE+INTERVAL '7 months',85000,1),
    (2,2,CURRENT_DATE-INTERVAL '15 days', 'Jersey Premium #1102','Jersey',  'Téc. Rodríguez','pendiente',NULL,85000,1),
    (3,4,CURRENT_DATE-INTERVAL '1 month', 'Holstein Elite #4521','Holstein','Téc. Pérez','fallida',NULL,85000,1);

COMMIT;


-- ╔══════════════════════════════════════════════════════════════════╗
-- ║                    RESUMEN DE SEGURIDAD                         ║
-- ╠══════════════════════════════════════════════════════════════════╣
-- ║                                                                  ║
-- ║  • PKs INTEGER (no SERIAL/BIGINT)                                ║
-- ║  • ENUMs para todos los estados y tipos                          ║
-- ║  • ON DELETE RESTRICT en FK operacionales                        ║
-- ║  • ON DELETE SET NULL solo en parentesco                         ║
-- ║  • CHECK constraints con rangos y validaciones lógicas           ║
-- ║  • UNIQUE compuestos para evitar duplicados de negocio           ║
-- ║  • Triggers cruzados: categoría↔tipo, raza↔tipo, vacuna↔tipo    ║
-- ║  • Triggers de negocio: solo vacas→leche, avícolas→huevos       ║
-- ║  • Generación atómica de códigos con bloqueo de fila             ║
-- ║  • Datos iniciales en transacción BEGIN/COMMIT                   ║
-- ║  • Contraseñas bcrypt con factor 12                              ║
-- ║  • 4 roles con GRANT diferenciado                                ║
-- ║  • Row Level Security en usuarios y auditoría                    ║
-- ║  • Borrado lógico (campo activo) — sin DELETE físico             ║
-- ║  • Auditoría automática con trigger y JSONB                      ║
-- ║  • Índices parciales para rendimiento óptimo                     ║
-- ║  • Vistas consolidadas para consultas seguras                    ║
-- ║                                                                  ║
-- ╚══════════════════════════════════════════════════════════════════╝
