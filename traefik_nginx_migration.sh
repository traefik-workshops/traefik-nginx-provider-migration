#!/bin/bash

# Traefik NGinX Provider Demo Script
# A comprehensive demonstration of setting up Traefik with NGinX provider

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Demo configuration
CLUSTER_NAME="traefik-nginx"
NAMESPACE="default"
BACKEND_URL="http://whoami.docker.localhost"
DASHBOARD_PORT="8888"
CERT_PATH="./certs/external-crt.pem"
KEY_PATH="./certs/external-key.pem"

# Function to print colored output
print_step() {
    echo -e "\n${CYAN}===================================================${NC}"
    echo -e "${WHITE}$1${NC}"
    echo -e "${CYAN}===================================================${NC}\n"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Function to wait for user input
wait_for_user() {
    echo -e "\n${YELLOW}Press Enter to continue...${NC}"
    read -r
    clear
}

# Function to check if command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        print_error "Command '$1' not found. Please install it first."
        exit 1
    fi
}

# Function to wait for deployment to be ready
wait_for_deployment() {
    local namespace=$1
    local deployment=$2
    local timeout=${3:-300}
    
    print_info "Waiting for deployment $deployment to be ready..."
    if kubectl wait --for=condition=available --timeout=${timeout}s deployment/$deployment -n $namespace &>/dev/null; then
        print_success "Deployment $deployment is ready!"
    else
        print_warning "Deployment $deployment may not be fully ready, continuing..."
    fi
}

# Function to test endpoint
test_endpoint() {
    local url=$1
    local expected_code=${2:-200}
    local description=$3
    
    print_info "Testing: $description"
    echo -e "${PURPLE}curl -k $url -L -u 'user:password' --location-trusted${NC}"
    
    local response_body
    local response_code
    local temp_file=$(mktemp)
    
    # Make the request and capture both body and status code
    if response_code=$(curl -k "$url" -L -u "user:password" --location-trusted -w '%{http_code}' -o "$temp_file" 2>/dev/null); then
        response_body=$(cat "$temp_file")
        rm -f "$temp_file"
        
        echo -e "\n${CYAN}📋 Response Details:${NC}"
        echo -e "${WHITE}Status Code: ${response_code}${NC}"
        echo -e "${WHITE}Response Body:${NC}"
        echo -e "${YELLOW}----------------------------------------${NC}"
        
        if [[ -n "$response_body" && "$response_body" != *"curl:"* ]]; then
            # Pretty print the response if it's not empty or an error
            echo -e "${GREEN}$response_body${NC}"
        else
            echo -e "${RED}(Empty or error response)${NC}"
        fi
        echo -e "${YELLOW}----------------------------------------${NC}\n"
        
        if [[ "$response_code" == "$expected_code" ]]; then
            print_success "✅ Success! Response code: $response_code"
            return 0
        else
            print_warning "⚠️  Unexpected response code: $response_code (expected: $expected_code)"
            return 1
        fi
    else
        rm -f "$temp_file"
        print_error "❌ Request failed or timed out"
        echo -e "${RED}Connection could not be established${NC}\n"
        return 1
    fi
}

# Function to create cluster
create_cluster() {
    print_info "Creating k3d cluster: $CLUSTER_NAME"
    print_info "This will create a cluster with Traefik disabled and necessary ports exposed"
    
    if k3d cluster list | grep -q "$CLUSTER_NAME"; then
        print_warning "Cluster $CLUSTER_NAME already exists, skipping creation..."
        return 0
    fi
    
    echo -e "${PURPLE}k3d cluster create $CLUSTER_NAME --port 80:80@loadbalancer --port 443:443@loadbalancer --port 8080:8080@loadbalancer --port 9090:9090@loadbalancer --k3s-arg \"--disable=traefik@server:0\"${NC}"
    
    if k3d cluster create "$CLUSTER_NAME" \
        --port 80:80@loadbalancer \
        --port 443:443@loadbalancer \
        --port 8080:8080@loadbalancer \
        --port 9090:9090@loadbalancer \
        --k3s-arg "--disable=traefik@server:0"; then
        print_success "Cluster created successfully!"
        
        print_info "Waiting for cluster to be ready..."
        sleep 10
        kubectl wait --for=condition=ready nodes --all --timeout=60s || print_warning "Some nodes may not be fully ready"
    else
        print_error "Failed to create cluster"
        exit 1
    fi
}

# Function to show cluster status
show_cluster_status() {
    print_info "Current cluster status:"
    echo -e "${PURPLE}"
    kubectl get nodes -o wide 2>/dev/null || echo "No cluster found"
    kubectl get pods -A 2>/dev/null || echo "No pods found"
    echo -e "${NC}"
}

# Function to cleanup
cleanup() {
    print_step "🧹 CLEANUP"
    
    print_info "Cleaning up deployed resources..."
    
    # Clean up Traefik
    if [[ -d "manifests/traefik" ]]; then
        print_info "Removing Traefik resources..."
        kubectl delete -f manifests/traefik --ignore-not-found=true || true
    fi
    
    # Clean up Ingress
    if [[ -d "manifests/ingress" ]]; then
        print_info "Removing Ingress resources..."
        kubectl delete -f manifests/ingress --ignore-not-found=true || true
    fi
    
    # Clean up NGinX (in case it's still there)
    if [[ -d "manifests/nginx" ]]; then
        print_info "Removing NGinX resources..."
        kubectl delete -f manifests/nginx --ignore-not-found=true || true
    fi
    
    # Clean up IngressClass
    if [[ -d "manifests/ingressclass" ]]; then
        print_info "Removing IngressClass resources..."
        kubectl delete -f manifests/ingressclass --ignore-not-found=true || true
    fi
    
    # Clean up TLS secret
    kubectl delete secret external-certs --namespace "$NAMESPACE" --ignore-not-found=true || true
    
    # Delete the k3d cluster
    print_info "Deleting k3d cluster: $CLUSTER_NAME"
    if k3d cluster list | grep -q "$CLUSTER_NAME"; then
        echo -e "${PURPLE}k3d cluster delete $CLUSTER_NAME${NC}"
        k3d cluster delete "$CLUSTER_NAME" || print_warning "Failed to delete cluster"
        print_success "Cluster deleted successfully!"
    else
        print_warning "Cluster $CLUSTER_NAME not found, skipping deletion..."
    fi
    
    print_success "Cleanup completed!"
}

# Main demo function
main() {
    # Trap cleanup on exit
    trap cleanup EXIT
    
    clear
    echo -e "${PURPLE}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║   🚀 TRAEFIK NGINX PROVIDER DEMONSTRATION 🚀                  ║
║                                                               ║
║   This script demonstrates the transition from NGinX          ║
║   Ingress Controller to Traefik with NGinX provider           ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    print_info "Checking prerequisites..."
    check_command "k3d"
    check_command "kubectl"
    check_command "curl"
    
    wait_for_user
    
    # ============================================================================
    # STEP 0: CREATE CLUSTER
    # ============================================================================
    
    print_step "🚀 STEP 0: CREATE K3D CLUSTER"
    
    create_cluster
    
    show_cluster_status
    wait_for_user
    
    # ============================================================================
    # STEP 1: SET UP ENVIRONMENT
    # ============================================================================
    
    print_step "📦 STEP 1: SET UP ENVIRONMENT"
    
    print_info "Creating NGinX IngressClass..."
    if [[ -d "manifests/ingressclass" ]]; then
        kubectl apply -f manifests/ingressclass
        print_success "IngressClass applied!"
    else
        print_warning "IngressClass manifests not found, skipping..."
    fi
    
    show_cluster_status
    wait_for_user
    
    # ============================================================================
    # STEP 2: EXPOSE BACKEND WITH NGINX
    # ============================================================================
    
    print_step "🔧 STEP 2: EXPOSE BACKEND WITH NGINX INGRESS"
    
    print_info "Creating TLS certificate secret..."
    if [[ -f "$CERT_PATH" && -f "$KEY_PATH" ]]; then
        kubectl create secret tls external-certs \
            --namespace "$NAMESPACE" \
            --cert="$CERT_PATH" \
            --key="$KEY_PATH" 2>/dev/null || print_warning "Secret already exists or files not found"
        print_success "TLS secret created!"
    else
        print_warning "Certificate files not found at $CERT_PATH and $KEY_PATH"
    fi
    
    print_info "Installing NGinX Ingress Controller..."
    if [[ -d "manifests/nginx" ]]; then
        kubectl apply -f manifests/nginx
        print_success "NGinX manifests applied!"
        
        # Wait for NGinX to be ready
        sleep 5
        wait_for_deployment "$NAMESPACE" "nginx-ingress-controller" 120
    else
        print_warning "NGinX manifests not found at manifests/nginx"
    fi
    
    print_info "Deploying the ingress configuration..."
    if [[ -d "manifests/ingress" ]]; then
        kubectl apply -f manifests/ingress
        print_success "Ingress configuration applied!"
        sleep 3
    else
        print_warning "Ingress manifests not found at manifests/ingress"
    fi
    
    print_info "Testing backend accessibility through NGinX..."
    sleep 5  # Give NGinX time to process the ingress
    test_endpoint "$BACKEND_URL" "200" "Backend through NGinX Ingress"
    
    wait_for_user
    
    # ============================================================================
    # STEP 3: UNINSTALL NGINX
    # ============================================================================
    
    print_step "🗑️  STEP 3: UNINSTALL NGINX INGRESS"
    
    print_info "Uninstalling NGinX Ingress Controller..."
    if [[ -d "manifests/nginx" ]]; then
        kubectl delete -f manifests/nginx --ignore-not-found=true
        print_success "NGinX Ingress Controller removed!"
    fi
    
    print_info "Waiting for NGinX pods to terminate..."
    sleep 5
    
    print_info "Checking what remains after NGinX controller removal..."
    echo -e "${PURPLE}kubectl get ingress -A${NC}"
    kubectl get ingress -A 2>/dev/null || echo "No ingresses found"
    echo ""
    
    print_success "✨ Notice: The NGinX Ingress resources are still present!"
    print_info "🔑 Only the NGinX controller (pods/services) was removed, not the ingress definitions"
    
    print_info "Testing backend accessibility (should fail now)..."
    if test_endpoint "$BACKEND_URL" "200" "Backend without any ingress controller"; then
        print_warning "Unexpected: Backend is still accessible!"
    else
        print_success "Expected behavior: Backend is not accessible without ingress controller"
        print_info "💡 The ingress resources exist, but there's no controller to process them"
    fi
    
    wait_for_user
    
    # ============================================================================
    # STEP 4: INSTALL TRAEFIK WITH NGINX PROVIDER
    # ============================================================================
    
    print_step "🌟 STEP 4: INSTALL TRAEFIK WITH NGINX PROVIDER"
    
    print_info "Installing Traefik with NGinX provider ..."
    if [[ -d "manifests/traefik" ]]; then
        kubectl apply -f manifests/traefik
        print_success "Traefik manifests applied!"
        
        # Wait for Traefik to be ready
        sleep 5
        wait_for_deployment "$NAMESPACE" "traefik" 120
    else
        print_warning "Traefik manifests not found at manifests/traefik"
    fi
    
    print_info "Testing backend accessibility through Traefik..."
    sleep 5  # Give Traefik time to discover the ingress
    test_endpoint "$BACKEND_URL" "200" "Backend through Traefik with NGinX provider"
    
    print_success "🎉 Backend is now accessible through Traefik with NGinX provider!"
    print_info "✨ Notice: The NGinX Ingress resources were NOT removed or modified!"
    print_info "🔄 Traefik automatically discovered and processed the existing NGinX Ingress"
    print_info "Take a moment to review the response above..."
    sleep 5  # Give user time to read the response
    
    # ============================================================================
    # FINAL STATUS AND DEMONSTRATION
    # ============================================================================
    
    print_step "🎉 DEMONSTRATION COMPLETE!"
    
    echo -e "${GREEN}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                    🎯 SUMMARY                                 ║
║                                                               ║
║  ✅ Verified cluster connection and setup                     ║
║  ✅ NGinX Ingress Controller deployed and tested              ║
║  ✅ NGinX Controller removed - backend became inaccessible    ║
║  ✅ Traefik with NGinX provider deployed                      ║
║  ✅ Backend accessible again through Traefik                  ║
║                                                               ║
║  🔑 KEY INSIGHT: The NGinX Ingress resources remained         ║
║     unchanged! Traefik automatically discovered and           ║
║     processed them using its NGinX provider.                  ║
║                                                               ║
║  This enables seamless migration from NGinX to Traefik        ║
║  without modifying existing ingress configurations!           ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    print_info "Available endpoints:"
    echo -e "${CYAN}  🌐 Backend: $BACKEND_URL${NC}"
    
    print_info "To explore the NGinX provider integration:"
    echo -e "${YELLOW}  kubectl get ingress -A${NC} ${WHITE}# Show existing NGinX ingress resources${NC}"
    echo -e "${YELLOW}  kubectl describe ingress -n $NAMESPACE${NC} ${WHITE}# View ingress details${NC}"
    echo -e "${YELLOW}  kubectl logs -n $NAMESPACE deployment/traefik${NC} ${WHITE}# See Traefik discovering NGinX ingresses${NC}"
    
    echo -e "\n${WHITE}Press Enter to cleanup deployed resources and exit, or Ctrl+C to keep the environment running...${NC}"
    read -r
}

# Handle script arguments
case "${1:-demo}" in
    "demo")
        main
        ;;
    "cleanup")
        cleanup
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [demo|cleanup|help]"
        echo "  demo    - Run the full demonstration (default)"
        echo "  cleanup - Clean up resources and exit"
        echo "  help    - Show this help message"
        ;;
    *)
        print_error "Unknown option: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac