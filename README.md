# Traefik NGINX Provider Migration Demo

This repository demonstrates how to migrate from NGINX Ingress Controller to Traefik using the NGINX provider feature.

## Related Blog Posts

- [The Great Kubernetes Ingress Transition: From ingress-nginx EoL to Modern Cloud-Native](https://traefik.io/blog/transition-from-ingress-nginx-to-traefik)
- [Traefik Proxy v.3.6](https://traefik.io/blog/traefik-proxy-3-6-ramequin)

![Ingress Transition Overview](ingress-transition-blog-no-copy.jpg)



## What This Demo Shows

This demonstration illustrates:

1. **Initial Setup**: Creating a K3s cluster with Traefik disabled
2. **NGINX Deployment**: Setting up NGINX Ingress Controller with TLS certificates
3. **Service Verification**: Confirming the backend service is accessible
4. **Controller Migration**: Removing only the NGINX controller (ingress definitions remain untouched)
5. **Zero-Downtime Transition**: Installing Traefik which automatically processes existing NGINX ingress resources


## Quick Demo

This entire migration can be fully demonstrated using the automated script:

```bash
./traefik_nginx_migration.sh
```

This script will walk you through the complete process of generating certificates, setting up the cluster, deploying NGINX, migrating to Traefik, and testing each step.

Alternatively, you can also perform the migration step by step using the following commands in the CLI:

## Manual Setup

### Prerequisites

Before starting, ensure you have the following tools installed:
- k3d
- kubectl
- curl
- openssl

### Step 0: Generate TLS Certificates

Since the certificates are not included in the repository, you need to generate them first:

```bash
# Create the certs directory if it doesn't exist
mkdir -p certs

# Generate a private key
openssl genrsa -out certs/external-key.pem 2048

# Generate a self-signed certificate
openssl req -new -x509 -key certs/external-key.pem -out certs/external-crt.pem -days 365 -subj "/CN=whoami.docker.localhost"
```

### Step 1: Set up the K3s Cluster

```bash
# Create K3s cluster with disabled default Traefik installation
k3d cluster create traefik-nginx \
  --port 80:80@loadbalancer \
  --port 443:443@loadbalancer \
  --port 8080:8080@loadbalancer \
  --port 9090:9090@loadbalancer \
  --k3s-arg "--disable=traefik@server:0"

# Create NGINX IngressClass
kubectl apply -f manifests/ingressclass
```

### Step 2: Deploy NGINX Ingress Controller

```bash
# Add the TLS certificate
kubectl create secret tls external-certs \
  --namespace default \
  --cert=./certs/external-crt.pem \
  --key=./certs/external-key.pem

# Install NGINX Ingress Controller
kubectl apply -f manifests/nginx

# Deploy the ingress resources
kubectl apply -f manifests/ingress

# Test the backend is reachable
curl -k http://whoami.docker.localhost -L -u "user:password" --location-trusted
```

### Step 3: Remove NGINX Ingress Controller

```bash
# Uninstall NGINX Ingress Controller
kubectl delete -f manifests/nginx

# Verify the backend is no longer reachable
curl -k http://whoami.docker.localhost -L -u "user:password" --location-trusted
```

> **🔑 Key Point**: Notice that we only removed the NGINX controller deployment, **NOT the ingress resources**. The ingress definitions remain completely untouched and will be automatically discovered by Traefik in the next step.

### Step 4: Install Traefik with NGINX Provider

```bash
# Install Traefik with NGINX provider (experimental feature)
kubectl apply -f manifests/traefik

# Port forward to access the Traefik dashboard (optional)
kubectl port-forward -n default svc/traefik 8888:8080 &

# Test the backend is reachable again through Traefik
curl -k http://whoami.docker.localhost -L -u "user:password" --location-trusted
```

> **🔄 Seamless Migration**: The backend is now accessible again! Traefik automatically discovered and processed the existing NGINX ingress resources **without any modifications**. This demonstrates migration from NGINX to Traefik.
## Repository Structure

```
.
├── certs/                    # TLS certificates
├── manifests/
│   ├── ingress/             # Ingress resources and backend service
│   ├── ingressclass/        # NGINX IngressClass definition
│   ├── nginx/               # NGINX Ingress Controller manifests
│   └── traefik/             # Traefik with NGINX provider manifests
├── traefik_nginx_migration.sh  # Automated demo script
└── README.md
```
