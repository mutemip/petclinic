# Initialize with Calico's recommended pod network CIDR
sudo kubeadm init --apiserver-advertise-address=192.168.5.5 --pod-network-cidr=192.168.0.0/16

# Set up kubeconfig
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Verify control plane is up
kubectl get nodes

