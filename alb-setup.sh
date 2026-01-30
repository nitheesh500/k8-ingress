#!/bin/bash
set -euo pipefail

# ============== CONFIG ==================
CLUSTER_NAME="demo-cluster"
VPC_ID="demo-vpc-123"
AWS_REGION="us-east-1"
ACCOUNT_ID="992382567166"


NAMESPACE="kube-system"
SERVICE_ACCOUNT="aws-load-balancer-controller"

POLICY_NAME="AWSLoadBalancerControllerIAMPolicy"
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"

HELM_RELEASE="aws-load-balancer-controller"
HELM_REPO_NAME="eks"
HELM_REPO_URL="https://aws.github.io/eks-charts"


# ========================================
# Cluster existence check
echo " Checking for cluster"
aws eks describe-cluster \
  --name "${CLUSTER_NAME}" \
  --region "${REGION}" \
  >/dev/null \
  || { echo "❌ EKS cluster '${CLUSTER_NAME}' not found"; exit 1; }

echo "🚀 Starting AWS Load Balancer Controller setup"

# ---------- STEP 1: Associate OIDC ----------
echo "🔗 Step 1: Associating IAM OIDC provider (idempotent)..."
eksctl utils associate-iam-oidc-provider \
  --cluster "${CLUSTER_NAME}" \
  --approve

# ---------- STEP 2: Download latest IAM policy ----------
echo "📥 Step 2: Downloading latest IAM policy..."
curl -fsSL \
https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json \
-o iam-policy.json

# ---------- STEP 3: Create or update IAM policy ----------
echo "🛡️ Step 3: Creating or updating IAM policy..."

if aws iam get-policy --policy-arn "${POLICY_ARN}" >/dev/null 2>&1; then
  echo "Policy exists. Creating new version and setting as default..."
  aws iam create-policy-version \
    --policy-arn "${POLICY_ARN}" \
    --policy-document file://iam-policy.json \
    --set-as-default
else
  echo "Policy does not exist. Creating..."
  aws iam create-policy \
    --policy-name "${POLICY_NAME}" \
    --policy-document file://iam-policy.json
fi

# ---------- STEP 4: Create IAM role + ServiceAccount ----------
echo "👤 Step 4: Creating IAM service account (IRSA)..."

eksctl create iamserviceaccount \
  --cluster "${CLUSTER_NAME}" \
  --namespace "${NAMESPACE}" \
  --name "${SERVICE_ACCOUNT}" \
  --attach-policy-arn "${POLICY_ARN}" \
  --override-existing-serviceaccounts \
  --approve

# ---------- STEP 5: Install / Upgrade Controller ----------
echo "📦 Step 5: Installing / upgrading AWS Load Balancer Controller..."

helm repo add "${HELM_REPO_NAME}" "${HELM_REPO_URL}" || true
helm repo update

helm upgrade --install "${HELM_RELEASE}" eks/aws-load-balancer-controller \
  -n "${NAMESPACE}" \
  --set clusterName="${CLUSTER_NAME}" \
  --set serviceAccount.create=false \
  --set serviceAccount.name="${SERVICE_ACCOUNT}" \
  --set region="${AWS_REGION}" \
  --set vpcId="${VPC_ID}"

echo "⏳ Waiting for controller rollout..."
kubectl rollout status deployment aws-load-balancer-controller -n "${NAMESPACE}"

echo "🎉 SUCCESS: AWS Load Balancer Controller fully set up"
