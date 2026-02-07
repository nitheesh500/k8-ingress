# #!/bin/bash
# set -euo pipefail

# # ================= CONFIG =================
# CLUSTER_NAME="myk8cluster"
# AWS_REGION="us-east-1"
# ACCOUNT_ID="992382567167"

# NAMESPACE="kube-system"
# SERVICE_ACCOUNT="aws-load-balancer-controller"
# POLICY_NAME="AWSLoadBalancerControllerIAMPolicy"

# POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"

# HELM_RELEASE="aws-load-balancer-controller"
# # =========================================

# echo "🔍 Checking EKS cluster..."
# aws eks describe-cluster \
#   --name "$CLUSTER_NAME" \
#   --region "$AWS_REGION" \
#   >/dev/null
# echo "✅ Cluster exists"

# echo "🔗 Associating IAM OIDC provider (safe to re-run)..."
# eksctl utils associate-iam-oidc-provider \
#   --cluster "$CLUSTER_NAME" \
#   --approve

# echo "👤 Creating / updating IAM ServiceAccount (IRSA)..."
# eksctl create iamserviceaccount \
#   --cluster "$CLUSTER_NAME" \
#   --namespace "$NAMESPACE" \
#   --name "$SERVICE_ACCOUNT" \
#   --attach-policy-arn "$POLICY_ARN" \
#   --override-existing-serviceaccounts \
#   --approve

# echo "📦 Installing / upgrading AWS Load Balancer Controller..."
# helm repo add eks https://aws.github.io/eks-charts || true
# helm repo update

# VPC_ID=$(aws eks describe-cluster \
#   --name "$CLUSTER_NAME" \
#   --region "$AWS_REGION" \
#   --query "cluster.resourcesVpcConfig.vpcId" \
#   --output text)

# helm upgrade --install "$HELM_RELEASE" eks/aws-load-balancer-controller \
#   -n "$NAMESPACE" \
#   --set clusterName="$CLUSTER_NAME" \
#   --set serviceAccount.create=false \
#   --set serviceAccount.name="$SERVICE_ACCOUNT" \
#   --set region="$AWS_REGION" \
#   --set vpcId="$VPC_ID"

# kubectl rollout status deployment/aws-load-balancer-controller -n "$NAMESPACE"

# echo "🎉 AWS Load Balancer Controller installed correctly"




#!/bin/bash
set -euo pipefail

# ============== CONFIG ==================
CLUSTER_NAME="myk8cluster"
AWS_REGION="us-east-1"
ACCOUNT_ID="992382567167"



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
  --region "${AWS_REGION}" \
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

EXISTING_POLICY_ARN=$(aws iam list-policies \
  --scope Local \
  --query "Policies[?PolicyName=='${POLICY_NAME}'].Arn" \
  --output text)

if [[ -n "$EXISTING_POLICY_ARN" && "$EXISTING_POLICY_ARN" != "None" ]]; then
  echo "✅ Policy exists: $EXISTING_POLICY_ARN"



  echo "🔄 Creating new policy version and setting as default..."
  aws iam create-policy-version \
    --policy-arn "$EXISTING_POLICY_ARN" \
    --policy-document file://iam-policy.json \
    --set-as-default

  POLICY_ARN="$EXISTING_POLICY_ARN"

else
  echo "🆕 Policy does not exist. Creating..."
  POLICY_ARN=$(aws iam create-policy \
    --policy-name "${POLICY_NAME}" \
    --policy-document file://iam-policy.json \
    --query "Policy.Arn" \
    --output text)

  echo "✅ Created policy: $POLICY_ARN"
fi


# ---------- STEP 4: Create IAM role + ServiceAccount ----------
echo "👤 Step 4: Creating IAM service account (IRSA)..."
# eksctl create iamserviceaccount \
#   --cluster myk8cluster \
#   --namespace kube-system \
#   --name aws-load-balancer-controller \
#   --attach-policy-arn arn:aws:iam::992382567167:policy/AWSLoadBalancerControllerIAMPolicy \
#   --approve

eksctl create iamserviceaccount \
  --cluster "${CLUSTER_NAME}" \
  --namespace "${NAMESPACE}" \
  --name "${SERVICE_ACCOUNT}" \
  --attach-policy-arn "${POLICY_ARN}" \
  --approve
 VPC_ID=$(aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --query "cluster.resourcesVpcConfig.vpcId" \
  --output text)
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
