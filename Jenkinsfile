pipeline {
    agent any

    triggers {
        // Disparador programado nocturno (2:00 AM)
        cron('H 2 * * *')
        // Disparador por sondeo / Webhook de cambios en repositorio
        pollSCM('H/30 * * * *')
    }

    parameters {
        booleanParam(name: 'DEBUG_LOCAL', defaultValue: false, description: 'Generar archivos JSON locales en disco para depuración')
    }

    environment {
        // Credenciales configuradas en Jenkins Credentials Store
        SUPABASE_URL = credentials('SACU_SUPABASE_URL')
        SUPABASE_SERVICE_ROLE_KEY = credentials('SACU_SUPABASE_SERVICE_ROLE_KEY')
        GOOGLE_DRIVE_FOLDER_ID = credentials('SACU_GOOGLE_DRIVE_FOLDER_ID')
        GOOGLE_DRIVE_API_KEY = credentials('SACU_GOOGLE_DRIVE_API_KEY')
    }

    stages {
        stage('Preparar Entorno') {
            steps {
                script {
                    if (isUnix()) {
                        sh '''
                            python3 -m venv .venv || python -m venv .venv
                            . .venv/bin/activate
                            python -m pip install --upgrade pip
                            pip install -r requirements.txt
                        '''
                    } else {
                        bat '''
                            python -m venv .venv
                            call .venv\\Scripts\\activate.bat
                            python -m pip install --upgrade pip
                            pip install -r requirements.txt
                        '''
                    }
                }
            }
        }

        stage('Sincronizar Cursos en Supabase Relacional') {
            steps {
                script {
                    def flag = params.DEBUG_LOCAL ? "--debug-local" : ""
                    if (isUnix()) {
                        sh """
                            . .venv/bin/activate
                            python scripts/update_courses.py ${flag}
                        """
                    } else {
                        bat """
                            call .venv\\Scripts\\activate.bat
                            python scripts/update_courses.py ${flag}
                        """
                    }
                }
            }
        }

        stage('Verificación de Salud') {
            steps {
                script {
                    echo "Validando conexión y servicio de datos en Supabase..."
                    if (isUnix()) {
                        sh '''
                            curl -s -f -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
                                 -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
                                 "${SUPABASE_URL}/rest/v1/v_courses_with_materials?limit=1" > /dev/null || true
                        '''
                    } else {
                        powershell '''
                            $headers = @{
                                "apikey" = $env:SUPABASE_SERVICE_ROLE_KEY
                                "Authorization" = "Bearer $env:SUPABASE_SERVICE_ROLE_KEY"
                            }
                            try {
                                $response = Invoke-RestMethod -Uri "$($env:SUPABASE_URL)/rest/v1/v_courses_with_materials?limit=1" -Headers $headers -Method Get
                                Write-Output "Respuesta exitosa de Supabase: $($response.Count) registros validados."
                            } catch {
                                Write-Warning "Aviso en verificación de salud: $_"
                            }
                        '''
                    }
                }
            }
        }
    }

    post {
        always {
            cleanWs deleteDirs: true, notFailBuild: true
        }
        success {
            echo "Pipeline completado con éxito: Cursos y materiales actualizados en Supabase relacional."
        }
        failure {
            echo "Error: Falló la sincronización de cursos y materiales en Jenkins."
        }
    }
}
