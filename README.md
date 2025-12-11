Ingress Controller: Acts as a gateway that processes external requests and directs them to the appropriate services based on Ingress rules.
Ingress Resource: Defines how traffic should be routed to services within the cluster.
Service: Handles the actual application logic and responds to the user request.
Pods: The units of the application that are managed by the services and run inside the cluster.


How Ingress Works (Traffic Flow) 

Step-by-Step Traffic Flow

1️⃣ User sends a request
Example:
https://example.com/app1

2️⃣ DNS resolves to the load balancer’s IP
Example:
AWS ALB or NGINX external IP

3️⃣ Load Balancer receives traffic

4️⃣ Ingress Controller checks routing rules
It looks at:

Host (example.com)

Path (/app1)

5️⃣ Ingress Controller sends traffic to the correct Kubernetes service
For /app1 → svc-app1

6️⃣ Service sends traffic to pods
Using selectors.


Setup 
--------------------------

✅ Step 1: Associate IAM OIDC Provider

EKS needs OIDC to attach IAM roles to service accounts.

eksctl utils associate-iam-oidc-provider \
  --cluster demo-cluster \
  --approve

✅ Step 2: Download IAM Policy

This policy allows the controller to create/manage ALBs.

curl -o iam-policy.json \
https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.1/docs/install/iam_policy.json

✅ Step 3: Create IAM Policy    

aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam-policy.json

This will return an ARN like:
arn:aws:iam::<ACCOUNT_ID>:policy/AWSLoadBalancerControllerIAMPolicy

Step 4: Create IAM Role for Controller ServiceAccount

Replace <ACCOUNT_ID> with your AWS account:
eksctl create iamserviceaccount \
  --cluster demo-cluster \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --attach-policy-arn arn:aws:iam::<ACCOUNT_ID>:policy/AWSLoadBalancerControllerIAMPolicy \
  --approve

✅ Step 5: Install AWS Load Balancer Controller (via Helm) 
helm repo add eks https://aws.github.io/eks-charts
helm repo update

Install:

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=demo-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=us-east-1 \
  --set vpcId=demo-vpc-123

✅ Step 6: Verify Installation
kubectl get pods -n kube-system


You should see:

aws-load-balancer-controller-xxxxx   Running
aws-load-balancer-controller-yyyyy   Running