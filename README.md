# app-cicd

API de gestión de biblioteca (Library Management) construida con .NET 10, desplegada en Azure Kubernetes Service (AKS) mediante un pipeline CI/CD completamente automatizado. Cada push a `main` compila, prueba, analiza, escanea vulnerabilidades, publica la imagen Docker y despliega a producción sin intervención manual.

[![CI/CD](https://github.com/cristiancave/app-cicd/actions/workflows/ci.yml/badge.svg)](https://github.com/cristiancave/app-cicd/actions/workflows/ci.yml)
[![Docker Hub](https://img.shields.io/badge/Docker%20Hub-cristiancave%2Fapp--cicd-2496ED?logo=docker&logoColor=white)](https://hub.docker.com/r/cristiancave/app-cicd)
[![Kubernetes](https://img.shields.io/badge/Deployed%20on-Azure%20AKS-326CE5?logo=kubernetes&logoColor=white)](#despliegue-en-aks)
[![Snyk](https://img.shields.io/badge/Snyk-Dependency%20Scan-4C4A73?logo=snyk&logoColor=white)](https://app.snyk.io)

## La aplicación

La API simula un sistema de gestión de biblioteca que permite administrar libros y préstamos. Se eligió este dominio porque tiene lógica de negocio real (validación de copias disponibles, cálculo de vencimientos, estadísticas) que va más allá de un CRUD básico y demuestra un caso de uso realista.

### Endpoints disponibles

**Health Check y Observabilidad:**
| Método | Endpoint | Descripción |
|---|---|---|
| `GET` | `/health` | Estado de la aplicación. Usado por Kubernetes para readiness y liveness probes |
| `GET` | `/swagger` | Documentación interactiva OpenAPI (Swagger UI) |
| `GET` | `/metrics` | Métricas Prometheus (http_requests_received_total, http_request_duration_seconds, etc.) |

**Libros:**
| Método | Endpoint | Descripción |
|---|---|---|
| `GET` | `/api/books` | Listar todos los libros |
| `GET` | `/api/books/{id}` | Obtener libro por ID |
| `POST` | `/api/books` | Registrar un nuevo libro |
| `PUT` | `/api/books/{id}` | Actualizar un libro existente |
| `DELETE` | `/api/books/{id}` | Eliminar un libro |
| `GET` | `/api/books/available` | Filtrar libros con copias disponibles |
| `GET` | `/api/books/genre/{genre}` | Filtrar por género (Fiction, NonFiction, Science, Technology, History, Art, Philosophy) |
| `GET` | `/api/books/search?query=texto` | Buscar por título o autor |

**Préstamos:**
| Método | Endpoint | Descripción |
|---|---|---|
| `GET` | `/api/loans` | Listar todos los préstamos |
| `POST` | `/api/loans` | Crear préstamo (reduce copias disponibles automáticamente) |
| `POST` | `/api/loans/{id}/return` | Devolver libro (actualiza estado y aumenta copias disponibles) |
| `GET` | `/api/loans/active` | Filtrar préstamos activos |
| `GET` | `/api/loans/overdue` | Filtrar préstamos vencidos |

**Estadísticas:**
| Método | Endpoint | Descripción |
|---|---|---|
| `GET` | `/api/stats` | Total de libros, préstamos activos, libros más prestados |

### Lógica de negocio

- Al crear un préstamo, la API **valida que haya copias disponibles** del libro. Si no hay, retorna `400 Bad Request`.
- Al crear un préstamo, `availableCopies` del libro se **reduce automáticamente**.
- Al devolver un libro, `availableCopies` se **incrementa**, `returnDate` se registra y `status` cambia a `Returned`.
- El endpoint `/api/loans/overdue` compara `dueDate` con la fecha actual para detectar préstamos vencidos que aún no se han devuelto.

## Observabilidad y SLOs

La aplicación expone métricas Prometheus estándar mediante el paquete `prometheus-net.AspNetCore`. El endpoint `/metrics` es scrapeado automáticamente por Azure Monitor managed Prometheus cada 30 segundos.

### Métricas expuestas

El endpoint `/metrics` expone automáticamente:

| Métrica | Tipo | Descripción |
|---|---|---|
| `http_requests_received_total` | Counter | Total de peticiones HTTP recibidas, etiquetadas por método, endpoint y código de respuesta |
| `http_request_duration_seconds` | Histogram | Duración de cada petición en segundos (incluye percentiles p50, p90, p95, p99) |
| `http_requests_in_progress` | Gauge | Peticiones siendo procesadas en este momento |

### SLOs definidos

Se definieron 3 Service Level Objectives para monitorear la salud de la aplicación en producción:

| SLO | Objetivo | Descripción |
|---|---|---|
| **Disponibilidad** | ≥ 99.5% | Tasa de respuestas exitosas (2xx) sobre el total de peticiones |
| **Error rate** | ≤ 0.5% | Tasa de respuestas con error de servidor (5xx) |
| **Latencia p95** | ≤ 500ms | El 95% de las peticiones deben responder en menos de 500 milisegundos |

### Integración con Prometheus

La aplicación expone métricas con solo dos líneas de código en `Program.cs`:

```csharp
app.UseHttpMetrics();   // Intercepta cada petición y registra métricas
app.MapMetrics();       // Expone el endpoint /metrics en formato Prometheus
```

El paquete `prometheus-net.AspNetCore` se encarga del resto: instrumenta automáticamente cada endpoint y genera las métricas estándar que Azure Monitor Prometheus recolecta.

### Implementación

```
App .NET (4 pods)
    ↓ expone /metrics
Azure Monitor managed Prometheus (PodMonitor scrape cada 30s)
    ↓
Prometheus Rule Groups (Bicep)
    ├── 4 Recording rules (precálculos SLI)
    └── 3 Alerting rules (disparan cuando se violan SLOs)
    ↓
Azure Managed Grafana
    └── Dashboard SLO con 7 paneles visuales
```

Para más detalles sobre la infraestructura de observabilidad (PodMonitor, Bicep rules, dashboard Grafana), ver el repo [app-cicd-infra](https://github.com/cristiancave/app-cicd-infra).

## Estructura del repositorio

```
app-cicd/
├── AppCicd/                       # Código fuente de la API
│   ├── Program.cs                 # Endpoints Minimal API + Swagger + Prometheus metrics
│   ├── Models/                    # Modelos de datos (Book, Loan, Enums)
│   ├── AppCicd.csproj             # Proyecto .NET con analizadores Roslyn + prometheus-net
│   └── appsettings.json           # Configuración de la aplicación
├── AppCicd.Tests/                 # Pruebas unitarias y de integración
│   ├── *Tests.cs                  # Tests con xUnit + WebApplicationFactory
│   └── AppCicd.Tests.csproj       # Proyecto de tests
├── .github/
│   └── workflows/
│       └── ci.yml                 # Pipeline CI/CD (GitHub Actions)
├── Dockerfile                     # Multi-stage build (SDK → Runtime)
├── .dockerignore                  # Excluye bin/, obj/, .git del contexto Docker
├── .gitignore                     # Excluye archivos de compilación
└── README.md
```

## Pipeline CI/CD

El archivo `ci.yml` define dos jobs que se ejecutan en secuencia:

```mermaid
flowchart LR
    subgraph "Job 1: build-and-test (CI)"
        A[Checkout] --> B[Setup .NET]
        B --> C[Restore]
        C --> D[Snyk scan]
        D --> E[SonarCloud begin]
        E --> F[Build + analysis]
        F --> G[Run tests + coverage]
        G --> H[SonarCloud end]
        H --> I[Format check]
        I --> J[Build image]
        J --> K[Grype scan]
        K --> L[Push to Docker Hub]
    end

    subgraph "Job 2: deploy-to-aks (CD)"
        M[Azure login OIDC] --> N[Get AKS credentials]
        N --> O[Deploy + rollout]
    end

    L -->|"Solo en main"| M
```

### Job 1: build-and-test (CI)

Se ejecuta en **cada push y pull request**:

| Step | Qué hace | Por qué es importante |
|---|---|---|
| **Checkout** | Descarga el código con historial completo | SonarCloud necesita el historial para análisis incremental |
| **Setup .NET + Java** | Instala SDK .NET 10 y Java 17 | SonarScanner requiere Java para ejecutarse |
| **Restore** | Descarga paquetes NuGet | Separado del build para aprovechar cache |
| **Snyk scan** | Escanea dependencias NuGet por vulnerabilidades conocidas | Detecta CVEs en paquetes de terceros antes de compilar. Complementa Grype (imagen) y SonarCloud (código) |
| **SonarCloud begin** | Inicia análisis estático con SonarCloud | Envuelve el build para capturar información de análisis |
| **Build** | Compila con analizadores Roslyn y --warnaserror | Detecta bugs, code smells y vulnerabilidades en compilación |
| **Run tests + coverage** | Pruebas con xUnit y reporte de cobertura OpenCover | Valida lógica de negocio y mide cobertura de código |
| **SonarCloud end** | Cierra y sube resultados a SonarCloud | Dashboard de calidad en sonarcloud.io |
| **Format check** | Verifica formato con dotnet format | Asegura consistencia de estilo |
| **Build image** | Construye imagen Docker multi-stage | Imagen final ~200MB vs ~800MB con SDK |
| **Grype scan** | Escanea imagen Docker por CVEs | Si encuentra vulnerabilidades críticas, la imagen no se publica |
| **Push to Docker Hub** | Publica la imagen | Solo si todos los pasos anteriores pasaron |

### Job 2: deploy-to-aks (CD)

Se ejecuta **solo en la rama `main`** y solo si el Job 1 fue exitoso:

| Step | Qué hace | Por qué es importante |
|---|---|---|
| **Azure login (OIDC)** | Se autentica en Azure sin contraseñas | Credenciales federadas: token temporal, sin secretos almacenados |
| **Get AKS credentials** | Descarga el kubeconfig del cluster | Permite ejecutar comandos kubectl |
| **Deploy to AKS** | Actualiza imagen y reinicia los pods | kubectl set image + rollout restart + rollout status |

### Seguridad en el pipeline: 3 capas complementarias

El pipeline implementa un modelo de seguridad por capas donde cada herramienta cubre un ámbito distinto:

| Herramienta | Qué escanea | Cuándo actúa |
|---|---|---|
| **SonarCloud** | Tu código fuente (bugs, code smells, vulnerabilidades) | Durante el build |
| **Snyk** | Tus dependencias (paquetes NuGet de terceros) | Después del restore, antes del build |
| **Grype** | Tu imagen Docker (imagen base + runtime + dependencias del SO) | Después del build, antes del push |

Esta separación garantiza que ningún vector de ataque pase sin ser revisado: el código propio, las librerías externas y la imagen final de despliegue.

### ¿Por qué Grype y no Trivy?

En marzo de 2026, Trivy (Aqua Security) sufrió un ataque a la cadena de suministro (CVE-2026-33634) que comprometió GitHub Actions, binarios de release e imágenes Docker Hub. Los atacantes inyectaron malware que exfiltraba credenciales de CI/CD desde los runners. Se seleccionó **Grype** (Anchore) como alternativa segura. Adicionalmente, se integró **Snyk** para escanear las dependencias del proyecto (paquetes NuGet). Mientras Grype escanea la imagen Docker completa, Snyk se enfoca específicamente en las dependencias del código fuente, proporcionando una segunda capa de análisis que cubre vulnerabilidades a nivel de librería.

## Dockerfile

La imagen usa **multi-stage build** para optimizar tamaño y seguridad:

```
Stage 1 (build):  SDK ~800MB  → Compila y publica la app
Stage 2 (final):  Runtime ~200MB → Solo copia los binarios compilados
```

Beneficios:
- Imagen final ~75% más pequeña que si incluyera el SDK completo.
- Sin código fuente en la imagen final, solo binarios compilados.
- Sin herramientas de desarrollo que podrían ser explotadas.
- Cache de capas: copia primero el .csproj para aprovechar cache de dependencias.

## Pruebas

Pruebas de integración con **xUnit** y **WebApplicationFactory**:

- Health check retorna 200 OK
- CRUD completo de libros (crear, leer, actualizar, eliminar)
- Filtros por género, disponibilidad y búsqueda
- Creación de préstamos reduce copias disponibles
- Préstamo falla si no hay copias (400 Bad Request)
- Devolución incrementa copias y cambia estado
- Filtro de préstamos activos y vencidos
- Estadísticas retornan datos correctos

Los tests se ejecutan automáticamente en cada push con reporte de cobertura enviado a SonarCloud.

## Análisis estático de código

Se utilizan dos herramientas complementarias:

**Analizadores Roslyn (.NET nativo):**
```xml
<TreatWarningsAsErrors>true</TreatWarningsAsErrors>
<EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>
<AnalysisLevel>latest-recommended</AnalysisLevel>
```

**SonarCloud (análisis en la nube):**
- Detecta bugs, vulnerabilidades, code smells y duplicación
- Mide cobertura de código con reportes OpenCover
- Dashboard público en sonarcloud.io con Quality Gate

## Despliegue en AKS

La aplicación corre en Azure Kubernetes Service con la siguiente configuración:

- **4 réplicas** para alta disponibilidad y distribución de carga
- **Readiness probe** en `/health` — Kubernetes verifica que el pod esté listo antes de enviarle tráfico
- **Liveness probe** en `/health` — si el pod deja de responder, Kubernetes lo reinicia
- **Resource limits** — cada pod tiene CPU y memoria limitados
- **LoadBalancer** — Azure asigna una IP pública
- **Puerto nombrado `http`** — requerido por el PodMonitor para scraping de métricas

### Acceso a la aplicación

```
http://<EXTERNAL-IP>/health         # Health check
http://<EXTERNAL-IP>/swagger        # Documentación interactiva
http://<EXTERNAL-IP>/api/books      # API de libros
http://<EXTERNAL-IP>/metrics        # Métricas Prometheus
```

Para obtener la IP actual:
```bash
kubectl get service app-cicd-service
```

## Ejecución local

### Con .NET directamente
```bash
cd AppCicd/
dotnet run
# Abrir http://localhost:5232/swagger
```

### Con Docker
```bash
docker build -t app-cicd:local .
docker run -p 8080:8080 app-cicd:local
# Abrir http://localhost:8080/swagger
```

### Ejecutar pruebas
```bash
dotnet test AppCicd.Tests/AppCicd.Tests.csproj --verbosity normal
```

## Seguridad

| Capa | Mecanismo | Descripción |
|---|---|---|
| **Código** | Analizadores Roslyn + SonarCloud | Detección de bugs, vulnerabilidades y code smells |
| **Dependencias** | Snyk | Escaneo de vulnerabilidades en paquetes NuGet |
| **Formato** | dotnet format | Consistencia de estilo |
| **Imagen Docker** | Grype (Anchore) | Escaneo de CVEs en imagen base y dependencias del SO |
| **Autenticación Azure** | OIDC Federation | Tokens temporales, sin contraseñas almacenadas |
| **Service Principal** | RBAC (Contributor) | Menor privilegio, limitado a la suscripción |
| **Secretos** | GitHub Secrets + Azure Key Vault | Encriptados, nunca en código |
| **Kubernetes** | Probes + Resource limits | Self-healing y aislamiento de recursos |
| **Monitoreo** | SLOs + Alertas Prometheus | Detección proactiva de degradación del servicio |

## Tecnologías

| Tecnología | Versión | Propósito |
|---|---|---|
| .NET | 10.0 | Framework de la API (Minimal APIs) |
| prometheus-net | - | Exposición de métricas Prometheus |
| xUnit | - | Framework de pruebas |
| Docker | Multi-stage | Contenerización de la aplicación |
| GitHub Actions | v6 | Pipeline CI/CD automatizado |
| SonarCloud | - | Análisis estático y cobertura de código |
| Snyk | CLI | Escaneo de vulnerabilidades en dependencias |
| Grype | v6 | Escaneo de vulnerabilidades de imágenes |
| Azure AKS | Kubernetes 1.34 | Orquestación de contenedores |
| Azure Monitor Prometheus | Managed | Recolección y almacenamiento de métricas |
| Azure Managed Grafana | - | Dashboards de monitoreo y SLOs |
| OIDC | Federation | Autenticación sin secretos |

## Repositorio relacionado

| Repositorio | Responsabilidad |
|---|---|
| [app-cicd](https://github.com/cristiancave/app-cicd) | Código fuente, Dockerfile, CI/CD (GitHub Actions), métricas Prometheus |
| [app-cicd-infra](https://github.com/cristiancave/app-cicd-infra) | Terraform, K8s manifests, Bicep (SLO rules), Grafana dashboard, Jenkins |