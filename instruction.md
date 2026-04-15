# Deploying to GCP Cloud Run

This guide walks through deploying the ASP.NET Core Web API to GCP Cloud Run manually (no Terraform). The app uses an in-memory database, so no external DB setup is required.

---

## Prerequisites

- GCP account with billing enabled
- [`gcloud` CLI](https://cloud.google.com/sdk/docs/install) installed and authenticated:
  ```bash
  gcloud auth login
  gcloud config set project YOUR_PROJECT_ID
  ```
- Docker installed (for local testing and optional manual image build)
- This repository on GitHub

---

## 1. Enable Required GCP APIs

```bash
gcloud services enable \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com
```

---

## 2. Create an Artifact Registry Repository

```bash
gcloud artifacts repositories create aspnet-webapi \
  --repository-format=docker \
  --location=us-central1 \
  --description="ASP.NET Core WebAPI Docker images"
```

Configure Docker to authenticate with the registry:

```bash
gcloud auth configure-docker us-central1-docker.pkg.dev
```

---

## 3. Deploy to Cloud Run

### Option A: Quick deploy from source (recommended for first deploy)

Cloud Build builds the image automatically from the local `Dockerfile` — no manual `docker build` needed:

```bash
gcloud run deploy aspnet-webapi \
  --source . \
  --region us-central1 \
  --platform managed \
  --allow-unauthenticated \
  --set-env-vars ASPNETCORE_ENVIRONMENT=Development \
  --port 8080
```

When prompted, confirm creating an Artifact Registry repository if one does not already exist.

### Option B: Build manually, then deploy

```bash
export PROJECT_ID=$(gcloud config get-value project)
export IMAGE=us-central1-docker.pkg.dev/${PROJECT_ID}/aspnet-webapi/sample-api:latest

# Build the image locally
docker build -t ${IMAGE} .

# Push to Artifact Registry
docker push ${IMAGE}

# Deploy from the pushed image
gcloud run deploy aspnet-webapi \
  --image ${IMAGE} \
  --region us-central1 \
  --platform managed \
  --allow-unauthenticated \
  --set-env-vars ASPNETCORE_ENVIRONMENT=Development \
  --port 8080
```

---

## 4. Set Up CI/CD via Cloud Build + GitHub (optional)

This automates deployment on every push to `main`.

### Step 1: Connect GitHub to Cloud Build

1. Open **GCP Console → Cloud Build → Triggers**
2. Click **Connect Repository**
3. Select **GitHub** as the source
4. Authenticate and install the **Cloud Build GitHub App** on your repository
5. Select `ASPNETCore-WebAPI-Sample` and confirm

### Step 2: Create `cloudbuild.yaml` in the repo root

Create a file named `cloudbuild.yaml` with the following content (replace `YOUR_PROJECT_ID`):

```yaml
steps:
  - name: 'gcr.io/cloud-builders/docker'
    args:
      - 'build'
      - '-t'
      - 'us-central1-docker.pkg.dev/$PROJECT_ID/aspnet-webapi/sample-api:$COMMIT_SHA'
      - '.'

  - name: 'gcr.io/cloud-builders/docker'
    args:
      - 'push'
      - 'us-central1-docker.pkg.dev/$PROJECT_ID/aspnet-webapi/sample-api:$COMMIT_SHA'

  - name: 'gcr.io/google.com/cloudsdktool/cloud-sdk'
    entrypoint: gcloud
    args:
      - 'run'
      - 'deploy'
      - 'aspnet-webapi'
      - '--image'
      - 'us-central1-docker.pkg.dev/$PROJECT_ID/aspnet-webapi/sample-api:$COMMIT_SHA'
      - '--region'
      - 'us-central1'
      - '--platform'
      - 'managed'
      - '--set-env-vars'
      - 'ASPNETCORE_ENVIRONMENT=Development'
      - '--port'
      - '8080'

images:
  - 'us-central1-docker.pkg.dev/$PROJECT_ID/aspnet-webapi/sample-api:$COMMIT_SHA'
```

### Step 3: Grant Cloud Build permission to deploy to Cloud Run

```bash
export PROJECT_ID=$(gcloud config get-value project)
export PROJECT_NUMBER=$(gcloud projects describe ${PROJECT_ID} --format='value(projectNumber)')

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
  --role="roles/run.admin"

gcloud iam service-accounts add-iam-policy-binding \
  ${PROJECT_NUMBER}-compute@developer.gserviceaccount.com \
  --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
  --role="roles/iam.serviceAccountUser"
```

### Step 4: Create the Cloud Build trigger

```bash
gcloud builds triggers create github \
  --repo-name=ASPNETCore-WebAPI-Sample \
  --repo-owner=YOUR_GITHUB_USERNAME \
  --branch-pattern='^main$' \
  --build-config=cloudbuild.yaml \
  --name=deploy-on-push-main
```

From now on, every push to `main` triggers an automatic build and deploy.

---

## 5. Verify the Deployment

Get the service URL:

```bash
gcloud run services describe aspnet-webapi \
  --region us-central1 \
  --format='value(status.url)'
```

Open the following URLs in a browser (replace `SERVICE_URL` with the output above):

| What | URL |
|------|-----|
| Swagger UI | `https://SERVICE_URL/swagger` |
| Foods API v1 | `https://SERVICE_URL/api/v1/foods` |
| Foods API v2 | `https://SERVICE_URL/api/v2/foods` |

**Expected result:** Swagger UI loads with V1 and V2 groups. `GET /api/v1/foods` returns a list of seeded food items.

---

## Local Testing with Docker Compose

```bash
# Build and start
docker compose up --build

# Access Swagger UI
open http://localhost:8080/swagger

# Stop
docker compose down
```

---

## Notes

- **In-memory database**: Each container instance has its own isolated in-memory database. If Cloud Run scales to multiple instances, state is not shared between them. This is expected for this demo app.
- **Cold starts**: Cloud Run scales to zero by default. The first request after idle takes ~2–4 seconds. Add `--min-instances 1` to the deploy command to keep a warm instance.
- **HTTPS**: Cloud Run terminates TLS externally; the container only receives HTTP on port 8080. `UseHttpsRedirection()` in the app has no effect inside Cloud Run.
- **Swagger in production**: Swagger UI is enabled because `ASPNETCORE_ENVIRONMENT=Development` is set in the container. This is intentional for this demo.
