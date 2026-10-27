-- =============================================================================
-- ESQUEMA COMPLETO Y UNIFICADO DE BASE DE DATOS (SUPABASE / POSTGRESQL)
-- Proyecto: Plataforma SACU - Módulo Académico, Búsqueda y Guías CSP
-- =============================================================================

-- -----------------------------------------------------------------------------
-- EXTENSIONES Y TIPOS ENUM
-- -----------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS unaccent;

DO $$ BEGIN
    CREATE TYPE role_type_enum AS ENUM ('Teoria', 'Practica', 'Laboratorio', 'General');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE access_type AS ENUM ('FREE', 'PREMIUM');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- =============================================================================
-- 1. MÓDULO ACADÉMICO PRINCIPAL
-- =============================================================================

-- Facultades (ej. FIIS, FIEE, etc.)
CREATE TABLE IF NOT EXISTS public.faculties (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code VARCHAR(50) NOT NULL UNIQUE,
    name VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now())
);

-- Cursos oficiales por facultad
CREATE TABLE IF NOT EXISTS public.courses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    faculty_id UUID NOT NULL REFERENCES public.faculties(id) ON DELETE CASCADE,
    course_code VARCHAR(50) NOT NULL,
    full_name VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()),
    CONSTRAINT uq_courses_faculty_code UNIQUE (faculty_id, course_code)
);

-- Docentes registrados por facultad
CREATE TABLE IF NOT EXISTS public.professors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    faculty_id UUID NOT NULL REFERENCES public.faculties(id) ON DELETE CASCADE,
    full_name VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()),
    CONSTRAINT uq_professors_faculty_name UNIQUE (faculty_id, full_name)
);

-- Relación Docente - Curso con Tipo de Rol
CREATE TABLE IF NOT EXISTS public.professor_courses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    professor_id UUID NOT NULL REFERENCES public.professors(id) ON DELETE CASCADE,
    course_id UUID NOT NULL REFERENCES public.courses(id) ON DELETE CASCADE,
    role_type role_type_enum NOT NULL DEFAULT 'Teoria',
    created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()),
    CONSTRAINT uq_professor_courses_prof_course_role UNIQUE (professor_id, course_id, role_type)
);

-- Reseñas académicas por docente y curso
CREATE TABLE IF NOT EXISTS public.reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    professor_course_id UUID NOT NULL REFERENCES public.professor_courses(id) ON DELETE CASCADE,
    author_tag VARCHAR(100) DEFAULT 'Estudiante Anónimo',
    teaching_score NUMERIC(2,1) NOT NULL CHECK (teaching_score >= 1.0 AND teaching_score <= 5.0),
    difficulty_score NUMERIC(2,1) NOT NULL CHECK (difficulty_score >= 1.0 AND difficulty_score <= 5.0),
    dedication_score NUMERIC(2,1) NOT NULL CHECK (dedication_score >= 1.0 AND dedication_score <= 5.0),
    comment TEXT NOT NULL,
    is_approved BOOLEAN DEFAULT true,
    flagged_count INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now())
);

-- Reportes de moderación de reseñas
CREATE TABLE IF NOT EXISTS public.reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    review_id UUID NOT NULL REFERENCES public.reviews(id) ON DELETE CASCADE,
    reason TEXT NOT NULL,
    status VARCHAR(50) DEFAULT 'pending' CHECK (status IN ('pending', 'resolved', 'dismissed')),
    created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now())
);

-- Tags de profesores (ej. "Exigente", "Didáctico", "Barco")
CREATE TABLE IF NOT EXISTS public.professor_tags (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL UNIQUE,
    created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now())
);

-- Asignación de tags a profesores
CREATE TABLE IF NOT EXISTS public.professor_tag_assignments (
    professor_id UUID NOT NULL REFERENCES public.professors(id) ON DELETE CASCADE,
    tag_id UUID NOT NULL REFERENCES public.professor_tags(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()),
    PRIMARY KEY (professor_id, tag_id)
);

-- =============================================================================
-- 2. MÓDULO CSP: DOCUMENTOS GUÍAS, PÁGINAS E ÍNDICE INVERSO
-- =============================================================================

-- Documentos PDF de "Cómo Sobrevivir a tu Profe" (Catálogo e Índice Estructurado)
CREATE TABLE IF NOT EXISTS public.csp_documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    doc_id VARCHAR(255) NOT NULL UNIQUE,          -- Google Drive File ID
    file_name VARCHAR(255) NOT NULL,              -- ej. csp_26-1_1er.pdf
    period VARCHAR(50) NOT NULL DEFAULT 'General',-- ej. 26-1
    cycle INT NOT NULL DEFAULT 1 CHECK (cycle >= 1 AND cycle <= 10),
    title VARCHAR(255) NOT NULL,
    description TEXT,
    pdf_url TEXT NOT NULL,
    total_pages INT NOT NULL DEFAULT 0,
    file_size_bytes BIGINT DEFAULT 0,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    index_data JSONB NOT NULL DEFAULT '[]'::jsonb,
    created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now())
);

-- Contenido textual extraído por página para visualización rápida y previews
CREATE TABLE IF NOT EXISTS public.csp_document_pages (
    page_id BIGSERIAL PRIMARY KEY,
    doc_id VARCHAR(255) NOT NULL REFERENCES public.csp_documents(doc_id) ON DELETE CASCADE,
    page_number INT NOT NULL,
    content_text TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()),
    CONSTRAINT uq_csp_doc_page UNIQUE (doc_id, page_number)
);

-- Índice Invertido Normalizado con N-Gramas para Búsqueda O(1)
CREATE TABLE IF NOT EXISTS public.professors_search_index (
    term VARCHAR(255) PRIMARY KEY,               -- Término o n-grama normalizado (ej. "juan carlos perez")
    n_gram INT NOT NULL DEFAULT 1,               -- Tamaño de n-grama (1 a 4)
    documents JSONB NOT NULL DEFAULT '[]'::jsonb,
    total_occurrences INT NOT NULL DEFAULT 1,
    updated_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now())
);

-- =============================================================================
-- 3. MÓDULOS DE SOPORTE E INFORMACIÓN ESTUDIANTIL
-- =============================================================================

-- Biblioteca Digital de Libros
CREATE TABLE IF NOT EXISTS public.library_books (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    faculty_id UUID NOT NULL REFERENCES public.faculties(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    physical_location TEXT,
    file_size_mb NUMERIC(6,2),
    access_condition access_type NOT NULL DEFAULT 'FREE',
    price INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now())
);

-- Eventos de la Agrupación / Facultad
CREATE TABLE IF NOT EXISTS public.events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    event_date DATE NOT NULL,
    event_time TIME NOT NULL,
    location TEXT NOT NULL,
    event_type VARCHAR(100) NOT NULL,
    image_url TEXT,
    organizer VARCHAR(255),
    description TEXT,
    community_link TEXT,
    registration_link TEXT,
    created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now())
);

-- Expositores de Eventos
CREATE TABLE IF NOT EXISTS public.event_speakers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    short_description TEXT,
    created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now())
);

-- Avisos y Deadlines de Cursos
CREATE TABLE IF NOT EXISTS public.notices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    course_id UUID NOT NULL REFERENCES public.courses(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    deadline TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now())
);

-- Alertas por Sección de Curso
CREATE TABLE IF NOT EXISTS public.course_alerts (
    course_id VARCHAR(50) NOT NULL,
    section VARCHAR(50) NOT NULL,
    alerts TEXT[] NOT NULL DEFAULT '{}',
    PRIMARY KEY (course_id, section)
);

-- Delegados Estudiantiles por Curso
CREATE TABLE IF NOT EXISTS public.course_delegates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    course_id VARCHAR(50) NOT NULL,
    section VARCHAR(50) DEFAULT 'U',
    unicode TEXT,
    created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now())
);

-- =============================================================================
-- ÍNDICES DE RENDIMIENTO
-- =============================================================================
CREATE INDEX IF NOT EXISTS idx_courses_faculty ON public.courses(faculty_id);
CREATE INDEX IF NOT EXISTS idx_courses_code ON public.courses(course_code);
CREATE INDEX IF NOT EXISTS idx_professors_faculty ON public.professors(faculty_id);
CREATE INDEX IF NOT EXISTS idx_prof_courses_prof ON public.professor_courses(professor_id);
CREATE INDEX IF NOT EXISTS idx_prof_courses_course ON public.professor_courses(course_id);
CREATE INDEX IF NOT EXISTS idx_reviews_prof_course ON public.reviews(professor_course_id);

CREATE INDEX IF NOT EXISTS idx_csp_docs_period_cycle ON public.csp_documents(period, cycle);
CREATE INDEX IF NOT EXISTS idx_csp_doc_pages_doc_page ON public.csp_document_pages(doc_id, page_number);
CREATE INDEX IF NOT EXISTS idx_search_index_ngram ON public.professors_search_index(n_gram);
CREATE INDEX IF NOT EXISTS idx_search_index_docs_gin ON public.professors_search_index USING gin (documents jsonb_path_ops);

-- =============================================================================
-- 4. MÓDULO DE REPOSITORIO Y MATERIALES DE CURSOS
-- =============================================================================

-- Tabla relacional para materiales por curso (ID incremental, sin blobs ni URLs redundantes)
CREATE TABLE IF NOT EXISTS public.course_materials (
    id BIGSERIAL PRIMARY KEY,
    course_id UUID NOT NULL REFERENCES public.courses(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    file_path TEXT NOT NULL,                     -- Ruta relativa jerárquica ej. 'Examenes_Parciales/2024-1/EP.pdf'
    drive_file_id VARCHAR(255) NOT NULL,         -- ID nativo en Google Drive
    folder_category VARCHAR(100) DEFAULT 'General', -- Categoría inferida de la carpeta contenedora
    mime_type VARCHAR(100) DEFAULT 'application/pdf',
    size_bytes BIGINT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()),
    CONSTRAINT uq_course_material UNIQUE (drive_file_id)
);

CREATE INDEX IF NOT EXISTS idx_course_materials_course_id ON public.course_materials(course_id);
CREATE INDEX IF NOT EXISTS idx_course_materials_drive_id ON public.course_materials(drive_file_id);
CREATE INDEX IF NOT EXISTS idx_course_materials_category ON public.course_materials(folder_category);

-- Permisos: el BIGSERIAL crea la secuencia course_materials_id_seq, que requiere
-- USAGE explícito; sin esto PostgREST responde 403 (42501) en cada INSERT.
GRANT SELECT ON public.course_materials TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.course_materials TO authenticated, service_role;
GRANT USAGE, SELECT ON SEQUENCE public.course_materials_id_seq TO authenticated, service_role;

-- Vista agregada para consumo directo por parte de sistemas externos
CREATE OR REPLACE VIEW public.v_courses_with_materials AS
SELECT 
    c.id AS course_id,
    c.course_code,
    c.full_name AS course_name,
    f.code AS faculty_code,
    COUNT(m.id) AS total_materials,
    COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'id', m.id,
                'name', m.name,
                'file_path', m.file_path,
                'category', m.folder_category,
                'drive_file_id', m.drive_file_id,
                'mime_type', m.mime_type,
                'size_bytes', m.size_bytes
            ) ORDER BY m.file_path
        ) FILTER (WHERE m.id IS NOT NULL),
        '[]'::jsonb
    ) AS materials
FROM public.courses c
LEFT JOIN public.faculties f ON c.faculty_id = f.id
LEFT JOIN public.course_materials m ON c.id = m.course_id
GROUP BY c.id, c.course_code, c.full_name, f.code;

COMMENT ON TABLE public.course_materials IS 'Almacén relacional de materiales y archivos indexados por curso, referenciando Google Drive.';
COMMENT ON VIEW public.v_courses_with_materials IS 'Vista optimizada para consultar cursos con su lista estructurada de materiales vía PostgREST.';

-- =============================================================================
-- COMENTARIOS DESCRIPTIVOS
-- =============================================================================
COMMENT ON TABLE public.csp_documents IS 'Catálogo central de documentos guía CSP con metadatos y su índice de profesores/cursos.';
COMMENT ON COLUMN public.csp_documents.index_data IS 'Índice de profesores y cursos con array de páginas: [{"course_id": "uuid", "course_code": "str", "course_name": "str", "professor_id": "uuid", "professor_name": "str", "role_type": "str", "pages": [int]}]';
COMMENT ON TABLE public.csp_document_pages IS 'Texto extraído por página para preview instantáneo de fragmentos en el visor de documentos.';
COMMENT ON TABLE public.professors_search_index IS 'Índice inverso normalizado con N-gramas (hasta 4 palabras) y lista de páginas exactas por PDF.';