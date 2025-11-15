# Download Calico manifest
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/tigera-operator.yaml

# Download custom resources
curl https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/custom-resources.yaml -O

# Apply Calico
kubectl create -f custom-resources.yaml

# Wait for Calico pods to be ready
kubectl get pods -n calico-system --watch