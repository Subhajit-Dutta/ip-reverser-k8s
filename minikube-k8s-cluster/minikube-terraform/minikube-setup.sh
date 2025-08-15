#!/bin/bash

# Minikube Setup Script - Python Wrapper
# This eliminates ALL bash templating issues by using Python

set -e

echo "Starting Minikube setup using Python approach..."

# Install Python if not present
if ! command -v python3 &> /dev/null; then
    echo "Installing Python3..."
    apt-get update -y
    apt-get install -y python3 python3-pip
fi

# Create the Python setup script
cat > /tmp/minikube_setup.py << 'EOF'
#!/usr/bin/env python3
import os, sys, subprocess, time, json, logging
from pathlib import Path

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s',
                   handlers=[logging.FileHandler('/var/log/minikube-setup.log'), logging.StreamHandler(sys.stdout)])
logger = logging.getLogger(__name__)

class MinikubeSetup:
    def __init__(self):
        self.cluster_name = sys.argv[1] if len(sys.argv) > 1 else "minikube-demo"
        self.environment = sys.argv[2] if len(sys.argv) > 2 else "demo"
        self.minikube_version = sys.argv[3] if len(sys.argv) > 3 else "v1.32.0"
        self.kubernetes_version = sys.argv[4] if len(sys.argv) > 4 else "v1.28.3"
        self.minikube_driver = sys.argv[5] if len(sys.argv) > 5 else "docker"
        self.minikube_memory = sys.argv[6] if len(sys.argv) > 6 else "3900"
        self.minikube_cpus = sys.argv[7] if len(sys.argv) > 7 else "2"
        self.ubuntu_home = "/home/ubuntu"
        self.minikube_home = f"{self.ubuntu_home}/.minikube"
        self.kube_config = f"{self.ubuntu_home}/.kube/config"
        logger.info(f"Starting setup for {self.cluster_name}")

    def run_cmd(self, cmd, check=True, user=None):
        if isinstance(cmd, str): cmd = cmd.split()
        if user == "ubuntu":
            env = {'HOME': self.ubuntu_home, 'MINIKUBE_HOME': self.minikube_home, 'KUBECONFIG': self.kube_config, 
                   'CHANGE_MINIKUBE_NONE_USER': 'true', 'PATH': '/usr/local/bin:/usr/bin:/bin'}
            cmd = ['sudo', '-i', '-u', 'ubuntu'] + cmd
        else: env = os.environ.copy()
        try:
            logger.info(f"Running: {' '.join(cmd)}")
            result = subprocess.run(cmd, check=check, capture_output=True, text=True, env=env)
            if result.stdout: logger.info(f"Output: {result.stdout.strip()}")
            return result
        except subprocess.CalledProcessError as e:
            logger.error(f"Command failed: {e}")
            if check: raise
            return e

    def get_metadata(self):
        try:
            private_ip = subprocess.run(['curl', '-s', 'http://169.254.169.254/latest/meta-data/local-ipv4'], 
                                      capture_output=True, text=True, timeout=10).stdout.strip()
            public_ip = subprocess.run(['curl', '-s', 'http://169.254.169.254/latest/meta-data/public-ipv4'], 
                                     capture_output=True, text=True, timeout=10).stdout.strip()
            instance_type = subprocess.run(['curl', '-s', 'http://169.254.169.254/latest/meta-data/instance-type'], 
                                         capture_output=True, text=True, timeout=10).stdout.strip()
            logger.info(f"Metadata: {private_ip}, {public_ip}, {instance_type}")
            return private_ip, public_ip, instance_type
        except: return "unknown", "unknown", "unknown"

    def update_system(self):
        logger.info("Updating system...")
        os.environ['DEBIAN_FRONTEND'] = 'noninteractive'
        self.run_cmd("apt-get update -y")
        self.run_cmd("apt-get upgrade -y")
        self.run_cmd("apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release unzip jq conntrack socat")

    def install_docker(self):
        logger.info("Installing Docker...")
        subprocess.run(["bash", "-c", "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg"])
        lsb = subprocess.run(['lsb_release', '-cs'], capture_output=True, text=True).stdout.strip()
        with open('/etc/apt/sources.list.d/docker.list', 'w') as f:
            f.write(f"deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu {lsb} stable\n")
        self.run_cmd("apt-get update -y")
        self.run_cmd("apt-get install -y docker-ce docker-ce-cli containerd.io")
        self.run_cmd("systemctl enable docker")
        self.run_cmd("systemctl start docker")
        self.run_cmd("usermod -aG docker ubuntu")
        time.sleep(10)
        self.run_cmd("chmod 666 /var/run/docker.sock")
        self.run_cmd("chown root:docker /var/run/docker.sock")
        os.makedirs('/etc/docker', exist_ok=True)
        with open('/etc/docker/daemon.json', 'w') as f:
            json.dump({"exec-opts": ["native.cgroupdriver=systemd"], "log-driver": "json-file", 
                      "log-opts": {"max-size": "100m"}, "storage-driver": "overlay2", 
                      "insecure-registries": ["10.96.0.0/12", "192.168.0.0/16"]}, f, indent=2)
        self.run_cmd("systemctl daemon-reload")
        self.run_cmd("systemctl restart docker")
        time.sleep(10)

    def install_k8s_tools(self):
        logger.info("Installing Kubernetes tools...")
        self.run_cmd(f"curl -LO https://dl.k8s.io/release/{self.kubernetes_version}/bin/linux/amd64/kubectl")
        self.run_cmd("chmod +x kubectl")
        self.run_cmd("mv kubectl /usr/local/bin/")
        self.run_cmd(f"curl -LO https://storage.googleapis.com/minikube/releases/{self.minikube_version}/minikube-linux-amd64")
        self.run_cmd("chmod +x minikube-linux-amd64")
        self.run_cmd("mv minikube-linux-amd64 /usr/local/bin/minikube")
        self.run_cmd(["bash", "-c", "curl -L https://github.com/kubernetes-sigs/cri-tools/releases/download/v1.28.0/crictl-v1.28.0-linux-amd64.tar.gz | tar -C /usr/local/bin -xz"])

    def configure_system(self):
        logger.info("Configuring system...")
        self.run_cmd("swapoff -a")
        self.run_cmd("sed -i '/ swap / s/^\\(.*\\)$/#\\1/g' /etc/fstab")
        self.run_cmd("modprobe br_netfilter")
        Path('/etc/modules-load.d').mkdir(exist_ok=True)
        with open('/etc/modules-load.d/minikube.conf', 'w') as f: f.write('br_netfilter\n')
        with open('/etc/sysctl.d/minikube.conf', 'w') as f:
            f.write("net.bridge.bridge-nf-call-iptables = 1\nnet.bridge.bridge-nf-call-ip6tables = 1\nnet.ipv4.ip_forward = 1\n")
        self.run_cmd("sysctl --system")

    def start_minikube(self):
        logger.info("Starting Minikube...")
        Path(self.minikube_home).mkdir(parents=True, exist_ok=True)
        Path(f"{self.ubuntu_home}/.kube").mkdir(parents=True, exist_ok=True)
        self.run_cmd(f"chown -R ubuntu:ubuntu {self.ubuntu_home}/.minikube")
        self.run_cmd(f"chown -R ubuntu:ubuntu {self.ubuntu_home}/.kube")
        
        # Test Docker
        if self.run_cmd("docker ps", check=False, user="ubuntu").returncode != 0:
            self.run_cmd("chmod 666 /var/run/docker.sock")
            self.run_cmd("docker ps", user="ubuntu")
        
        # Get resources
        mem_output = subprocess.run(['free', '-m'], capture_output=True, text=True)
        total_mem = int(mem_output.stdout.split('\n')[1].split()[1])
        cpu_cores = int(subprocess.run(['nproc'], capture_output=True, text=True).stdout.strip())
        
        # Calculate resources
        req_mem, req_cpus = int(self.minikube_memory), int(self.minikube_cpus)
        minikube_mem = req_mem if total_mem >= req_mem else total_mem - 512
        minikube_cpus = req_cpus if cpu_cores >= req_cpus else cpu_cores
        
        logger.info(f"Starting with {minikube_mem}MB memory and {minikube_cpus} CPUs")
        
        # Start Minikube
        cmd = ["minikube", "start", f"--driver={self.minikube_driver}", f"--memory={minikube_mem}", 
               f"--cpus={minikube_cpus}", f"--kubernetes-version={self.kubernetes_version}", 
               "--delete-on-failure", "--force", "--wait=true", "--wait-timeout=600s", "--v=3"]
        
        result = self.run_cmd(cmd, user="ubuntu")
        if result.returncode != 0:
            self.run_cmd("minikube logs", check=False, user="ubuntu")
            raise Exception("Minikube startup failed")
        
        self.run_cmd("minikube status", user="ubuntu")
        self.run_cmd("kubectl get nodes", user="ubuntu")
        
        # Wait for ready
        for i in range(30):
            result = self.run_cmd("kubectl get nodes", check=False, user="ubuntu")
            if "Ready" in result.stdout: break
            time.sleep(10)

    def enable_addons(self):
        logger.info("Enabling addons...")
        for addon in ["storage-provisioner", "default-storageclass"]:
            self.run_cmd(f"minikube addons enable {addon}", user="ubuntu")
        for addon in ["dashboard", "metrics-server"]:
            self.run_cmd(f"minikube addons enable {addon}", check=False, user="ubuntu")

    def create_rbac(self):
        logger.info("Creating Jenkins RBAC...")
        rbac = """apiVersion: v1
kind: ServiceAccount
metadata:
  name: jenkins-deployer
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: jenkins-deployer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: jenkins-deployer
  namespace: default"""
        with open('/tmp/jenkins-rbac.yaml', 'w') as f: f.write(rbac)
        self.run_cmd("kubectl apply -f /tmp/jenkins-rbac.yaml", user="ubuntu")

    def create_files(self):
        private_ip, public_ip, instance_type = self.get_metadata()
        
        # Info file
        info = f"""Minikube Cluster Information
===========================
Cluster Name: {self.cluster_name}
Environment: {self.environment}
Setup Date: {time.strftime('%Y-%m-%d %H:%M:%S')}

Instance Information:
- Private IP: {private_ip}
- Public IP: {public_ip}  
- Instance Type: {instance_type}

Minikube Configuration:
- Version: {self.minikube_version}
- Kubernetes Version: {self.kubernetes_version}
- Driver: {self.minikube_driver}
- Memory: {self.minikube_memory}MB
- CPUs: {self.minikube_cpus}

Access Information:
- SSH: ssh -i {self.cluster_name}-key.pem ubuntu@{public_ip}
- Kubernetes API: https://{private_ip}:8443

Setup completed at: {time.strftime('%Y-%m-%d %H:%M:%S')}
"""
        with open(f"{self.ubuntu_home}/cluster-info.txt", 'w') as f: f.write(info)
        
        # Scripts
        scripts = {
            f"{self.ubuntu_home}/start-dashboard.sh": "#!/bin/bash\necho 'Starting Dashboard...'\nminikube dashboard --url\n",
            f"{self.ubuntu_home}/cluster-health-check.sh": """#!/bin/bash
echo "=== Health Check ==="
echo "Date: $(date)"
echo "Minikube Status:"
minikube status
echo "Nodes:"
kubectl get nodes
echo "System Pods:"
kubectl get pods -n kube-system
"""
        }
        
        for script_path, content in scripts.items():
            with open(script_path, 'w') as f: f.write(content)
            self.run_cmd(f"chmod +x {script_path}")
        
        self.run_cmd(f"chown ubuntu:ubuntu {self.ubuntu_home}/cluster-info.txt")
        for script_path in scripts: self.run_cmd(f"chown ubuntu:ubuntu {script_path}")

    def create_service(self):
        service = f"""[Unit]
Description=Minikube Kubernetes Cluster
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
User=ubuntu
Group=ubuntu
ExecStart=/usr/local/bin/minikube start --driver={self.minikube_driver}
RemainAfterExit=yes
Environment=HOME={self.ubuntu_home}
Environment=MINIKUBE_HOME={self.minikube_home}

[Install]
WantedBy=multi-user.target"""
        with open('/etc/systemd/system/minikube.service', 'w') as f: f.write(service)
        self.run_cmd("systemctl enable minikube.service")

    def run(self):
        try:
            logger.info("=" * 50)
            logger.info("Starting Minikube setup")
            logger.info("=" * 50)
            
            self.get_metadata()
            self.update_system()
            self.install_docker()
            self.install_k8s_tools()
            self.configure_system()
            self.start_minikube()
            self.enable_addons()
            self.create_rbac()
            self.create_files()
            self.create_service()
            
            # Final verification
            self.run_cmd("minikube status", user="ubuntu")
            self.run_cmd("kubectl get nodes", user="ubuntu")
            self.run_cmd("kubectl get pods -n kube-system", user="ubuntu")
            
            # Success marker
            with open('/tmp/minikube-ready', 'w') as f: f.write('SUCCESS: Minikube cluster is ready\n')
            self.run_cmd('chown ubuntu:ubuntu /tmp/minikube-ready')
            
            logger.info("✅ Minikube setup completed successfully!")
            logger.info("🎉 Cluster is ready!")
            
        except Exception as e:
            logger.error(f"Setup failed: {e}")
            raise
        finally:
            # Cleanup
            for f in ['/tmp/jenkins-rbac.yaml']: 
                if os.path.exists(f): os.remove(f)

if __name__ == "__main__": MinikubeSetup().run()
EOF

# Make the Python script executable
chmod +x /tmp/minikube_setup.py

# Run the Python script with Terraform variables as arguments
echo "Executing Python setup script..."
python3 /tmp/minikube_setup.py \
    "${cluster_name}" \
    "${environment}" \
    "${minikube_version}" \
    "${kubernetes_version}" \
    "${minikube_driver}" \
    "${minikube_memory}" \
    "${minikube_cpus}"

echo "Python-based setup completed!"

# Cleanup
rm -f /tmp/minikube_setup.py

echo "Setup script completed successfully!"