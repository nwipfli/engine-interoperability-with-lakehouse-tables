#!/usr/bin/env bash
# ==============================================================================
# Setup Environment for Lakehouse Cross-Engine Interoperability Demo
# ==============================================================================
# This script provisions the necessary Google Cloud infrastructure for demonstrating
# multi-engine Lakehouse table interoperability between Google BigQuery and
# Managed Apache Spark Serverless over Apache Iceberg.
#
# Components Provisioned:
#   1. Google Cloud APIs enablement (Lakehouse, BigQuery, Dataproc, AI Platform, Storage)
#   2. User IAM role assignments for administrative permissions
#   3. BigQuery Cloud Resource Connection for Gemini Enterprise Agent Platform
#   4. Google Cloud Storage (GCS) bucket for Lakehouse warehouse data
#   5. Lakehouse Iceberg REST Catalog with vended credentials
#   6. Lakehouse namespace ("default") and initial Iceberg table
#   7. BigQuery DML property enablement on the Lakehouse Iceberg table
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# 1. Load Environment Configuration
# ------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

if [[ -f "${ENV_FILE}" ]]; then
    echo "Loading environment variables from ${ENV_FILE}..."
    # shellcheck source=/dev/null
    source "${ENV_FILE}"
else
    echo "Error: .env file not found at ${ENV_FILE}"
    echo "Please copy .env.example to .env and configure your variables:"
    echo "  cp .env.example .env"
    exit 1
fi

# Validate required variables
: "${PROJECT_ID:?Environment variable PROJECT_ID is required}"
: "${REGION:?Environment variable REGION is required}"
: "${CATALOG_NAME:?Environment variable CATALOG_NAME is required}"
: "${WAREHOUSE_BUCKET:?Environment variable WAREHOUSE_BUCKET is required}"
: "${USER_EMAIL:?Environment variable USER_EMAIL is required}"

echo "=================================================================="
echo "Starting Lakehouse environment setup with parameters:"
echo "  Project ID:        ${PROJECT_ID}"
echo "  Region:            ${REGION}"
echo "  Catalog Name:      ${CATALOG_NAME}"
echo "  Warehouse Bucket:  gs://${WAREHOUSE_BUCKET}"
echo "  User Email:        ${USER_EMAIL}"
echo "=================================================================="

# ------------------------------------------------------------------------------
# 2. Enable Required Google Cloud APIs
# ------------------------------------------------------------------------------
echo ""
echo "Step 1: Enabling required Google Cloud APIs..."
gcloud services enable \
    biglake.googleapis.com \
    bigquery.googleapis.com \
    bigquerystorage.googleapis.com \
    dataproc.googleapis.com \
    aiplatform.googleapis.com \
    notebooks.googleapis.com \
    compute.googleapis.com \
    storage.googleapis.com \
    --project="${PROJECT_ID}"

# ------------------------------------------------------------------------------
# 3. Grant User IAM Roles
# ------------------------------------------------------------------------------
echo ""
echo "Step 2: Granting user administrative IAM roles..."
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="user:${USER_EMAIL}" --role="roles/biglake.admin"

gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="user:${USER_EMAIL}" --role="roles/bigquery.admin"

gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="user:${USER_EMAIL}" --role="roles/dataproc.editor"

gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="user:${USER_EMAIL}" --role="roles/aiplatform.user"

gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="user:${USER_EMAIL}" --role="roles/storage.admin"

gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="user:${USER_EMAIL}" --role="roles/compute.networkAdmin"

# ------------------------------------------------------------------------------
# 4. Create BigQuery Cloud Resource Connection for Gemini Enterprise Agent Platform
# ------------------------------------------------------------------------------
echo ""
echo "Step 3: Creating BigQuery Cloud Resource Connection for Gemini Enterprise Agent Platform..."
bq mk --connection --location="${REGION}" --project_id="${PROJECT_ID}" \
    --connection_type=CLOUD_RESOURCE vertex_ai_conn

echo "Waiting for connection service account propagation (20s)..."
sleep 20

export BQ_CONN_SA=$(bq show --format=json --connection "${PROJECT_ID}.${REGION}.vertex_ai_conn" | jq -r '.cloudResource.serviceAccountId')
echo "Connection Service Account: ${BQ_CONN_SA}"

echo "Granting aiplatform.user role to BigQuery connection service account..."
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${BQ_CONN_SA}" \
    --role="roles/aiplatform.user"

# ------------------------------------------------------------------------------
# 5. Create Cloud Storage Bucket for Lakehouse Iceberg Warehouse
# ------------------------------------------------------------------------------
echo ""
echo "Step 4: Creating Cloud Storage bucket for Lakehouse warehouse..."
gcloud storage buckets create "gs://${WAREHOUSE_BUCKET}" \
    --project="${PROJECT_ID}" \
    --location="${REGION}"

# ------------------------------------------------------------------------------
# 6. Create Lakehouse Iceberg REST Catalog
# ------------------------------------------------------------------------------
echo ""
echo "Step 5: Creating Lakehouse Iceberg REST Catalog with vended credentials..."
gcloud biglake iceberg catalogs create "${CATALOG_NAME}" \
    --project="${PROJECT_ID}" \
    --catalog-type=biglake \
    --default-location="gs://${WAREHOUSE_BUCKET}" \
    --credential-mode=vended-credentials

echo "Waiting for Lakehouse Catalog service account propagation (20s)..."
sleep 20

export CATALOG_SA=$(gcloud biglake iceberg catalogs describe "${CATALOG_NAME}" --project="${PROJECT_ID}" --format="value(biglake-service-account)")
echo "Lakehouse Catalog Service Account: ${CATALOG_SA}"

echo "Granting storage.objectUser role on warehouse bucket to Lakehouse catalog service account..."
gcloud storage buckets add-iam-policy-binding "gs://${WAREHOUSE_BUCKET}" \
    --member="serviceAccount:${CATALOG_SA}" \
    --role="roles/storage.objectUser"

# ------------------------------------------------------------------------------
# 7. Create Lakehouse Namespace and Initial Table
# ------------------------------------------------------------------------------
echo ""
echo "Step 6: Creating Lakehouse namespace 'default'..."
gcloud biglake iceberg namespaces create default \
    --project="${PROJECT_ID}" \
    --catalog="${CATALOG_NAME}"

echo ""
echo "Step 7: Creating Lakehouse Iceberg table 'iceberg_table_test' from table_definition.json..."
gcloud biglake iceberg tables create \
    --project="${PROJECT_ID}" \
    --catalog="${CATALOG_NAME}" \
    --namespace=default \
    --create-from-file="${SCRIPT_DIR}/table_definition.json"

# ------------------------------------------------------------------------------
# 8. Enable BigQuery DML on Lakehouse Table
# ------------------------------------------------------------------------------
echo ""
echo "Step 8: Enabling BigQuery DML support on table properties..."
gcloud biglake iceberg tables update iceberg_table_test \
    --project="${PROJECT_ID}" \
    --catalog="${CATALOG_NAME}" \
    --namespace=default \
    --update-properties="gcp.biglake.bigquery-dml.enabled=true"

echo ""
echo "=================================================================="
echo "Lakehouse environment setup completed successfully!"
echo "You can now run the interactive demo notebook: cross_engine_demo.ipynb"
echo "=================================================================="