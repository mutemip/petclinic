#!/bin/bash

# Kubernetes Complete Cleanup Script
# Run this on ALL THREE VMs (control plane + both workers)

set -e

echo "=============================================="
echo "  Kubernetes Complete Cleanup Script"
echo "=============================================="
echo ""
echo "This will remove all Kubernetes components"
echo "Press Ctrl+C to cancel, or Enter to continue..."
read

echo ""
echo "Step 1: Resetting kubeadm cluster..."
sudo kubeadm reset -f 2>/dev/null || echo "No cluster to reset"

echo ""
echo "Step 2: Stopping services..."
sudo systemctl stop kubelet 2>/dev/null || true
sudo systemctl stop containerd 2>/dev/null || true

echo ""
echo "Step 3: Removing Kubernetes packages..."
sudo apt-mark unhold kubelet kubeadm kubectl 2>/dev/null || true
sudo apt-get purge -y kubeadm kubectl kubelet kubernetes-cni 2>/dev/null || true

echo ""
echo "Step 4: Removing containerd..."
sudo apt-get purge -y containerd 2>/dev/null || true

echo ""
echo "Step 5: Removing dependencies..."
sudo apt-get autoremove -y

echo ""
echo "Step 6: Cleaning up configuration files and directories..."
sudo rm -rf ~/.kube
sudo rm -rf /etc/kubernetes
sudo rm -rf /var/lib/kubelet
sudo rm -rf /var/lib/etcd
sudo rm -rf /etc/cni
sudo rm -rf /opt/cni
sudo rm -rf /var/lib/cni
sudo rm -rf /run/flannel
sudo rm -rf /etc/containerd
sudo rm -rf /var/lib/containerd
sudo rm -rf /var/lib/calico
sudo rm -rf /etc/calico
sudo rm -rf /var/log/calico
sudo rm -rf /var/run/calico

echo ""
echo "Step 7: Removing kernel module configurations..."
sudo rm -f /etc/modules-load.d/k8s.conf

echo ""
echo "Step 8: Unloading kernel modules..."
sudo modprobe -r overlay 2>/dev/null || true
sudo modprobe -r br_netfilter 2>/dev/null || true

echo ""
echo "Step 9: Removing sysctl configurations..."
sudo rm -f /etc/sysctl.d/k8s.conf
sudo sysctl --system >/dev/null 2>&1

echo ""
echo "Step 10: Removing Kubernetes apt repository..."
sudo rm -f /etc/apt/sources.list.d/kubernetes.list
sudo rm -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo ""
echo "Step 11: Re-enabling swap..."
sudo sed -i '/swap/s/^#//' /etc/fstab
sudo swapon -a 2>/dev/null || echo "Swap already enabled or not configured"

echo ""
echo "Step 12: Cleaning up iptables rules..."
sudo iptables -F
sudo iptables -t nat -F
sudo iptables -t mangle -F
sudo iptables -X

echo ""
echo "Step 13: Removing network interfaces..."
sudo ip link delete cni0 2>/dev/null || true
sudo ip link delete flannel.1 2>/dev/null || true
sudo ip link delete tunl0 2>/dev/null || true
sudo ip link delete vxlan.calico 2>/dev/null || true

echo ""
echo "Step 14: Cleaning up network routes..."
sudo ip route flush proto bird 2>/dev/null || true

echo ""
echo "Step 15: Removing calicoctl (if installed)..."
sudo rm -f /usr/local/bin/calicoctl

echo ""
echo "Step 16: Updating package cache..."
sudo apt-get update

echo ""
echo "Step 17: Verifying cleanup..."
echo ""
echo "Checking for remaining Kubernetes packages:"
dpkg -l | grep -i kube || echo "  ✓ No Kubernetes packages found"
dpkg -l | grep -i containerd || echo "  ✓ No containerd packages found"
echo ""
echo "Checking swap status:"
swapon --show || echo "  ✓ Swap is disabled (normal if you have no swap partition)"
free -h | grep -i swap
echo ""
echo "Checking for Kubernetes processes:"
ps aux | grep -E 'kube|containerd' | grep -v grep || echo "  ✓ No Kubernetes processes running"
echo ""

echo "=============================================="
echo "  Cleanup Complete!"
echo "=============================================="
echo ""
echo "Summary of what was removed:"
echo "  ✓ kubeadm, kubectl, kubelet"
echo "  ✓ containerd"
echo "  ✓ All Kubernetes configuration files"
echo "  ✓ All network configurations"
echo "  ✓ Kernel module configurations"
echo "  ✓ Calico/Flannel components"
echo "  ✓ Swap has been re-enabled"
echo ""
echo "IMPORTANT: It is HIGHLY RECOMMENDED to reboot now"
echo "to ensure all changes take effect and networking is reset."
echo ""
echo "Reboot now? (y/n)"
read -r response
if [[ "$response" =~ ^[Yy]$ ]]; then
    echo "Rebooting in 5 seconds... (Press Ctrl+C to cancel)"
    sleep 5
    sudo reboot
else
    echo ""
    echo "Skipping reboot. You can reboot later with: sudo reboot"
    echo ""
    echo "If you don't reboot, some networking components may not"
    echo "be fully cleaned up until the next restart."
fi