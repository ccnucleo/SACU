import { supabase, isSupabaseConfigured } from '../../../core/config/supabaseClient'

export interface DriveFileNode {
  name: string
  type: 'file'
  id: string
  mimeType?: string
  size?: number
}

export interface DriveFolderNode {
  name: string
  type: 'folder'
  id: string
  total_files?: number
  children: (DriveFolderNode | DriveFileNode)[]
}

export type DriveNode = DriveFolderNode | DriveFileNode

export interface DriveCourseInfo {
  course_id: string
  course_name: string
  id?: string
  scanned_at?: string
  total_files?: number
}

export interface DriveCatalogIndex {
  total_courses: number
  total_files: number
  scanned_at?: string
  courses: DriveCourseInfo[]
}

export interface DriveCourseData {
  course_id: string
  course_name: string
  id?: string
  scanned_at?: string
  tree: DriveFolderNode
}

export interface CourseMaterialRow {
  id?: number | string
  name: string
  file_path: string
  category?: string
  drive_file_id: string
  mime_type?: string
  size_bytes?: number
}

// Memory cache to avoid re-fetching data of the same course in the same session
const courseCache: Record<string, DriveCourseData> = {}

/**
 * Reconstruye la estructura jerárquica de árbol (carpetas y archivos)
 * a partir de la lista plana de materiales relacionales de Supabase.
 */
export function buildTreeFromMaterials(
  courseId: string,
  courseName: string,
  materials: CourseMaterialRow[]
): DriveFolderNode {
  const rootNode: DriveFolderNode = {
    name: courseName || courseId,
    type: 'folder',
    id: `root_${courseId}`,
    children: [],
    total_files: materials.length,
  }

  for (const item of materials) {
    const rawPath = item.file_path || item.name
    const parts = rawPath.split('/').filter(Boolean)
    if (parts.length === 0) continue

    let currentNode = rootNode
    for (let i = 0; i < parts.length - 1; i++) {
      const folderName = parts[i]
      let childFolder = currentNode.children.find(
        (c): c is DriveFolderNode => c.type === 'folder' && c.name === folderName
      )
      if (!childFolder) {
        childFolder = {
          name: folderName,
          type: 'folder',
          id: `folder_${courseId}_${parts.slice(0, i + 1).join('_')}`,
          children: [],
          total_files: 0,
        }
        currentNode.children.push(childFolder)
      }
      currentNode = childFolder
    }

    const fileName = parts[parts.length - 1]
    const fileNode: DriveFileNode = {
      name: fileName,
      type: 'file',
      id: item.drive_file_id,
      mimeType: item.mime_type || 'application/pdf',
      size: item.size_bytes || 0,
    }
    currentNode.children.push(fileNode)
  }

  function calculateTotal(node: DriveFolderNode): number {
    let sum = 0
    for (const child of node.children) {
      if (child.type === 'file') {
        sum += 1
      } else {
        sum += calculateTotal(child)
      }
    }
    node.total_files = sum
    return sum
  }

  calculateTotal(rootNode)
  return rootNode
}

/**
 * Consulta la lista de cursos disponibles priorizando la base de datos relacional de Supabase.
 * Con fallback a archivos locales en caso de desconexión o entorno estático.
 */
export async function fetchDriveCourses(): Promise<DriveCourseInfo[]> {
  // 1. Intentar consulta a base de datos relacional en Supabase
  if (isSupabaseConfigured() && supabase) {
    try {
      const { data, error } = await supabase
        .from('v_courses_with_materials')
        .select('course_id, course_code, course_name, total_materials')
        .order('course_code', { ascending: true })

      if (!error && Array.isArray(data) && data.length > 0) {
        return data.map((row: any) => ({
          course_id: row.course_code || row.course_id,
          course_name: row.course_name,
          id: row.course_id,
          total_files: Number(row.total_materials) || 0,
        }))
      }
    } catch (e) {
      console.warn('[SACU Relational DB] Aviso al consultar v_courses_with_materials:', e)
    }
  }

  // 2. Fallback a datos locales estáticos si existen
  try {
    const res = await fetch('/data/courses/index.json')
    if (res.ok) {
      const data = await res.json()
      if (Array.isArray(data)) {
        return data
      } else if (data && Array.isArray(data.courses)) {
        return data.courses
      }
    }
  } catch (e) {
    console.warn('[SACU Static Data] Error al cargar /data/courses/index.json', e)
  }
  return []
}

export async function fetchDriveCatalogIndex(): Promise<DriveCatalogIndex | null> {
  const courses = await fetchDriveCourses()
  if (courses.length > 0) {
    const totalFiles = courses.reduce((acc, c) => acc + (c.total_files || 0), 0)
    return {
      total_courses: courses.length,
      total_files: totalFiles,
      courses,
    }
  }
  return null
}

/**
 * Obtiene los materiales estructurados del curso específico desde Supabase relacional
 * o recurre al fallback local si no está disponible.
 */
export async function fetchCourseDriveData(courseId: string): Promise<DriveCourseData> {
  if (courseCache[courseId]) {
    return courseCache[courseId]
  }

  // 1. Intentar obtener desde base de datos relacional de Supabase
  if (isSupabaseConfigured() && supabase) {
    try {
      const { data, error } = await supabase
        .from('v_courses_with_materials')
        .select('course_id, course_code, course_name, total_materials, materials')
        .or(`course_code.eq.${courseId},course_id.eq.${courseId}`)
        .maybeSingle()

      if (!error && data) {
        const materialsList: CourseMaterialRow[] = Array.isArray(data.materials) ? data.materials : []
        const tree = buildTreeFromMaterials(courseId, data.course_name, materialsList)
        const courseResult: DriveCourseData = {
          course_id: data.course_code || courseId,
          course_name: data.course_name,
          id: data.course_id,
          tree,
        }
        courseCache[courseId] = courseResult
        return courseResult
      }
    } catch (e) {
      console.warn(`[SACU Relational DB] Aviso al cargar curso ${courseId} desde Supabase:`, e)
    }
  }

  // 2. Fallback a archivo JSON estático local
  try {
    const res = await fetch(`/data/courses/${encodeURIComponent(courseId)}.json`)
    if (res.ok) {
      const data = await res.json()
      courseCache[courseId] = data
      return data
    }
  } catch (e) {
    console.warn(`[SACU Static Data] Error al cargar /data/courses/${courseId}.json`, e)
  }

  // Fallback si no existe el curso en ningún origen
  const fallbackData: DriveCourseData = {
    course_id: courseId,
    course_name: courseId,
    tree: {
      name: courseId,
      type: 'folder',
      id: `root_${courseId}`,
      children: [],
    },
  }
  return fallbackData
}

export function formatDisplayName(rawName: string): string {
  if (!rawName) return ''
  return rawName.replace(/_/g, ' ').trim()
}

/**
 * Fabricación dinámica de URLs de Drive mediante ID nativo (sin persistencia en BD)
 */
export function getDriveViewUrl(driveFileId: string): string {
  if (!driveFileId) return ''
  return `https://drive.google.com/file/d/${driveFileId}/view`
}

export function getDriveDownloadUrl(driveFileId: string): string {
  if (!driveFileId) return ''
  return `https://drive.google.com/uc?export=download&id=${driveFileId}`
}
