#!/usr/bin/env bash
# ==============================================================================
# Teardown & Cleanup for Lakehouse Cross-Engine Interoperability Demo
# ==============================================================================
# This script cleanly destroys all cloud resources created for the Lakehouse demo.
#
# Resources Cleaned Up:
#   1. Lakehouse Catalog service account IAM bindings on the GCS warehouse bucket
#   2. Lakehouse Iceberg tables ("iceberg_table_test" and "taxi_trips_spark")
#   3. Lakehouse namespace ("default")
#   4. Lakehouse Iceberg REST Catalog
#   5. Cloud Storage warehouse bucket and all stored Parquet data/metadata files
#   6. BigQuery "ai_models" dataset
#   7. BigQuery Cloud Resource Connection for Gemini Enterprise Agent Platform & IAM bindings
#   8. User IAM role assignments
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
    echo "Please ensure .env exists with PROJECT_ID, REGION, CATALOG_NAME, etc."
    exit 1
fi

# Validate required variables
: "${PROJECT_ID:?Environment variable PROJECT_ID is required}"
: "${REGION:?Environment variable REGION is required}"
: "${CATALOG_NAME:?Environment variable CATALOG_NAME is required}"
: "${WAREHOUSE_BUCKET:?Environment variable WAREHOUSE_BUCKET is required}"
: "${USER_EMAIL:?Environment variable USER_EMAIL is required}"

echo "=================================================================="
echo "Starting Lakehouse environment teardown with parameters:"
echo "  Project ID:        ${PROJECT_ID}"
echo "  Region:            ${REGION}"
echo "  Catalog Name:      ${CATALOG_NAME}"
echo "  Warehouse Bucket:  gs://${WAREHOUSE_BUCKET}"
echo "  User Email:        ${USER_EMAIL}"
echo "=================================================================="

# ------------------------------------------------------------------------------
# 2. Remove Lakehouse Catalog Service Account GCS IAM Binding
# ------------------------------------------------------------------------------
echo ""
echo "Step 1: Removing Lakehouse Catalog IAM binding from warehouse bucket..."
export CATALOG_SA=$(gcloud biglake iceberg catalogs describe "${CATALOG_NAME}" --project="${PROJECT_ID}" --format="value(biglake-service-account)" 2>/dev/null || echo "")

if [[ -n "${CATALOG_SA}" ]]; then
    gcloud storage buckets remove-iam-policy-binding "gs://${WAREHOUSE_BUCKET}" \
        --member="serviceAccount:${CATALOG_SA}" \
        --role="roles/storage.objectUser" || true
fi

# ------------------------------------------------------------------------------
# 3. Delete Lakehouse Iceberg Tables
# ------------------------------------------------------------------------------
echo ""
echo "Step 2: Deleting Lakehouse Iceberg tables..."
gcloud biglake iceberg tables delete iceberg_table_test \
    --project="${PROJECT_ID}" \
    --namespace=default \
    --catalog="${CATALOG_NAME}" \
    --quiet || true

gcloud biglake iceberg tables delete taxi_trips_spark \
    --project="${PROJECT_ID}" \
    --namespace=default \
    --catalog="${CATALOG_NAME}" \
    --quiet || true

# ------------------------------------------------------------------------------
# 4. Delete Lakehouse Namespace and Catalog
# ------------------------------------------------------------------------------
echo ""
echo "Step 3: Deleting Lakehouse namespace 'default'..."
gcloud biglake iceberg namespaces delete default \
    --project="${PROJECT_ID}" \
    --catalog="${CATALOG_NAME}" \
    --quiet || true

echo ""
echo "Step 4: Deleting Lakehouse Iceberg REST Catalog '${CATALOG_NAME}'..."
gcloud biglake iceberg catalogs delete "${CATALOG_NAME}" \
    --project="${PROJECT_ID}" \
    --quiet || true

# ------------------------------------------------------------------------------
# 5. Delete Cloud Storage Warehouse Bucket
# ------------------------------------------------------------------------------
echo ""
echo "Step 5: Deleting Cloud Storage warehouse bucket and all stored data..."
gcloud storage rm -r "gs://${WAREHOUSE_BUCKET}" || true

# ------------------------------------------------------------------------------
# 6. Delete BigQuery AI Models Dataset
# ------------------------------------------------------------------------------
echo ""
echo "Step 6: Deleting BigQuery ai_models dataset..."
bq rm -r -f -d --location="${REGION}" "${PROJECT_ID}:ai_models" || true

# ------------------------------------------------------------------------------
# 7. Remove BigQuery Vertex AI Connection & IAM Binding
# ------------------------------------------------------------------------------
echo ""
echo "Step 7: Removing BigQuery Gemini Enterprise Agent Platform connection..."
export BQ_CONN_SA=$(bq show --format=json --connection "${PROJECT_ID}.${REGION}.vertex_ai_conn" 2>/dev/null | jq -r '.cloudResource.serviceAccountId' 2>/dev/null || echo "")

if [[ -n "${BQ_CONN_SA}" && "${BQ_CONN_SA}" != "null" ]]; then
    gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${BQ_CONN_SA}" \
        --role="roles/aiplatform.user" || true
fi

bq rm --connection --location="${REGION}" vertex_ai_conn || true

# ------------------------------------------------------------------------------
# 8. Revoke User IAM Roles
# ------------------------------------------------------------------------------
echo ""
echo "Step 8: Revoking user administrative IAM roles..."
gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
    --member="user:${USER_EMAIL}" --role="roles/biglake.admin" || true

gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
    --member="user:${USER_EMAIL}" --role="roles/bigquery.admin" || true

gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
    --member="user:${USER_EMAIL}" --role="roles/dataproc.editor" || true

gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
    --member="user:${USER_EMAIL}" --role="roles/aiplatform.user" || true

gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
    --member="user:${USER_EMAIL}" --role="roles/storage.admin" || true

gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
    --member="user:${USER_EMAIL}" --role="roles/compute.networkAdmin" || true

echo ""
echo "=================================================================="
echo "Lakehouse environment cleanup completed successfully!"
echo "=================================================================="
