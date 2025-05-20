#!/bin/bash

# -- ------------------------------------------------------------------------------------------------
# Author: alexolinux
# This script to install and configure a Kubernetes cluster with control-plane and nodes.
# -- ------------------------------------------------------------------------------------------------
# https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/
# https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/
# -- ------------------------------------------------------------------------------------------------

# Usage: ./kubernetes-install.sh (control-plane || node)

# If option is "control-plane": IFACE is required
# Define according to the Interface Name (i.e.: eth0, wlan0, etc).
IFACE=""
POD_CIDR="10.244.0.0/16"

# If option is "node": The following variables are required.
# PORT (usually the default is 6443).
# CONTROL_PLANE should have the Control Plane IP Address
# Both "TOKEN" and "HASH" values are provided after completed the Control Plane installation process (control-plane installation output).
PORT=6443
CONTROL_PLANE=""
TOKEN=""
HASH=""

# Kubernetes packages installation 
# (PLEASE, CHECK THE REPO RELEASE VERSION!) <<<<<<<<<
# https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/
# https://kubernetes.io/releases/download/

# Change the Kubernetes Version if needed.
KUBE_VERSION="1.32.0"
KUBE_PKG_VER="v1.32"

# Calico Releases
# https://github.com/projectcalico/calico/releases
CALICO_VERSION="v3.30.0"
# Flannel Releases
# https://github.com/flannel-io/flannel/releases
FLANNEL_VERSION="v0.26.7"

# docker-compose release version
# https://github.com/docker/compose/releases
DC_VER="v2.36.0"

# ShellScript Functions

# K8s Type: control-plane|node
usage() {
	echo "Usage: $0 <control-plane|node>"
	exit 1
}

# Input User for Control Plane
get_interface_name() {
  while true; do
    read -p "Enter the Interface Name (i.e.: eth0): " IFACE
    if [ -n "$IFACE" ]; then
      if ip link show "$IFACE" > /dev/null 2>&1; then
        echo "Using interface: $IFACE"
        break
      else
        echo "Error: Interface '$IFACE' does not exist or is not recognized. Please try again."
      fi
    else
      echo "Error: Interface Name cannot be empty. Please try again."
    fi
  done
}

get_pod_cidr() {
  read -p "Enter the PODs CIDR (Default: $POD_CIDR): " USER_CIDR
  if [ -z "$USER_CIDR" ]; then
    echo "Using default POD CIDR: $POD_CIDR"
  else
    POD_CIDR="$USER_CIDR"
    echo "Using user-provided POD CIDR: $POD_CIDR"
  fi
}

# Input User for Worker Node
get_port() {
  read -p "Enter the PORT (Default: $PORT): " USER_PORT
  if [ -z "$USER_PORT" ]; then
    echo "Using default PORT: $PORT"
  else
    PORT="$USER_PORT"
    echo "Using user-provided PORT: $PORT"
  fi
}

get_control_plane_ip() {
  while true; do
    read -p "Enter the Control Plane IP Address: " CONTROL_PLANE
    if [[ -n "$CONTROL_PLANE" && "$CONTROL_PLANE" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
      # Validate if the IP address is reachable
      if ping -c 1 -W 1 "$CONTROL_PLANE" > /dev/null 2>&1; then
        echo "Using Control Plane IP Address: $CONTROL_PLANE"
        break
      else
        echo "Error: IP address '$CONTROL_PLANE' is not reachable. Please try again."
      fi
    else
      echo "Error: Invalid or empty IP address. Please enter a valid IP address."
    fi
  done
}

get_control_plane_token() {
  while true; do
    read -p "Enter the Control-Plane TOKEN: " TOKEN
    if [ -z "$TOKEN" ]; then
      echo "Error: TOKEN cannot be empty. Please try again."
    else
      echo "Using Control-Plane TOKEN: $TOKEN"
      break
    fi
  done
}

get_control_plane_hash() {
  while true; do
    read -p "Enter the Control-Plane HASH: " HASH
    if [ -z "$HASH" ]; then
      echo "Error: HASH cannot be empty. Please try again."
    else
      echo "Using Control-Plane HASH: $HASH"
      break
    fi
  done
}

# Function to prompt and validate Kubernetes version
get_kube_version() {
	read -p "Enter Kubernetes version (Default: $KUBE_VERSION): " USER_KUBE_VERSION
	if [[ -z "$USER_KUBE_VERSION" ]]; then
		echo "Using default Kubernetes version: $KUBE_VERSION"
	elif [[ "$USER_KUBE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		KUBE_VERSION="$USER_KUBE_VERSION"
		KUBE_PKG_VER="v${USER_KUBE_VERSION%.*}"  # Automatically set KUBE_PKG_VER based on KUBE_VERSION
		echo "Using user-provided Kubernetes version: $KUBE_VERSION"
		echo "Derived Kubernetes package version: $KUBE_PKG_VER"
	else
		echo "Invalid Kubernetes version format. Using default: $KUBE_VERSION"
	fi
}

# Function to prompt and validate Calico version
get_calico_version() {
	read -p "Enter Calico release version (Default: $CALICO_VERSION): " USER_CALICO_VERSION
	if [[ -z "$USER_CALICO_VERSION" ]]; then
		echo "Using default Calico version: $CALICO_VERSION"
	elif [[ "$USER_CALICO_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		CALICO_VERSION="$USER_CALICO_VERSION"
		echo "Using user-provided Calico version: $CALICO_VERSION"
	else
		echo "Invalid Calico version format. Using default: $CALICO_VERSION"
	fi
}

# Function to prompt and validate Flannel version
get_flannel_version() {
  read -p "Enter Flannel release version (Default: $FLANNEL_VERSION): " USER_FLANNEL_VERSION
  if [[ -z "$USER_FLANNEL_VERSION" ]]; then
    echo "Using default Flannel version: $FLANNEL_VERSION"
  elif [[ "$USER_FLANNEL_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    FLANNEL_VERSION="$USER_FLANNEL_VERSION"
    echo "Using user-provided Flannel version: $FLANNEL_VERSION"
  else
    echo "Invalid Flannel version format. Using default: $FLANNEL_VERSION"
  fi
}

# Function to prompt and validate Docker Compose version
get_docker_compose_version() {
	read -p "Enter Docker Compose release version (Default: $DC_VER): " USER_DC_VER
	if [[ -z "$USER_DC_VER" ]]; then
			echo "Using default Docker Compose version: $DC_VER"
	elif [[ "$USER_DC_VER" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
			DC_VER="$USER_DC_VER"
			echo "Using user-provided Docker Compose version: $DC_VER"
	else
			echo "Invalid Docker Compose version format. Using default: $DC_VER"
	fi
}

# Optional/Additional Tools Inputs
ask_install_docker() {
  while true; do
    read -p "Do you want to install Docker? (y/n): " install_docker
    if [[ "$install_docker" =~ ^[Yy]$ ]]; then
      if [ $distro_type -eq 0 ]; then
        echo "Installing Docker on RHEL-based system..."
        rhel_docker_install
      else
        echo "Installing Docker on Debian/Ubuntu-based system..."
        deb_docker_install
      fi
      break
    elif [[ "$install_docker" =~ ^[Nn]$ ]]; then
      echo "Docker installation skipped."
      break
    else
      echo "Invalid input. Please enter 'y' or 'n'."
    fi
  done
}

ask_install_compose() {
  while true; do
    read -p "Do you want to install Docker Compose? (y/n): " install_compose
    if [[ "$install_compose" =~ ^[Yy]$ ]]; then
      if [ $distro_type -eq 0 ]; then
        echo "Installing Docker Compose on RHEL-based system..."
        rhel_compose_install
      else
        echo "Installing Docker Compose on Debian/Ubuntu-based system..."
        deb_compose_install
      fi
      break
    elif [[ "$install_compose" =~ ^[Nn]$ ]]; then
      echo "Docker Compose installation skipped."
      break
    else
      echo "Invalid input. Please enter 'y' or 'n'."
    fi
  done
}

#-- ------------------------ --
#-- Prereqs for installation --
#-- ------------------------ --

prereq_kernel() {
	echo "Disabling SWAP..."
	sudo sed -i '/\/swapfile/s/^/#/' /etc/fstab
	sudo swapoff -a
	echo "Loading required kernel modules"
	cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

	sudo modprobe overlay
	sudo modprobe br_netfilter
}

prereq_params() {
	echo "Parameter Settings..."
	cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

	sudo sysctl --system
}

# Environment PATH
environment() {
  echo "Checking PATH..."
  LOCAL_BIN="/usr/local/bin"
  PROFILE_D_SCRIPT="/etc/profile.d/add_usr_local_bin.sh"

  # Add /usr/local/bin to the PATH for the current session if not already present
  if [[ ":$PATH:" != *":$LOCAL_BIN:"* ]]; then
    export PATH=$PATH:$LOCAL_BIN

    # Create the script in /etc/profile.d if it doesn't exist
    if [ ! -f "$PROFILE_D_SCRIPT" ]; then
      echo -e "#!/bin/bash\nexport PATH=\$PATH:$LOCAL_BIN" | sudo tee "$PROFILE_D_SCRIPT" > /dev/null
      sudo chmod +x "$PROFILE_D_SCRIPT"
      echo "Script added to $PROFILE_D_SCRIPT to persist across sessions."
    fi
  else
    echo "$LOCAL_BIN is already in the PATH for the current session."
  fi
}

#-- --------------------------------------------------- --
#-- Function to detect LINUX Base Distro  ------------- --
#-- --------------------------------------------------- --

# Function to detect the type of the distribution (RHEL-based or Debian/Ubuntu-based)
detect_distro_type() {
	# Read the /etc/os-release file to identify the distribution
	DISTRO_ID=$(grep '^ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
	DISTRO_ID_LIKE=$(grep '^ID_LIKE=' /etc/os-release | cut -d'=' -f2 | tr -d '"')

	# Detect if the distribution is RHEL-based
	if [[ "$DISTRO_ID" == "rhel" ]] || [[ "$DISTRO_ID_LIKE" == *"rhel"* ]]; then
		echo "RHEL-based distribution detected: $DISTRO_ID"
		return 0  # RHEL-based

	# Detect if the distribution is Debian/Ubuntu-based
	elif [[ "$DISTRO_ID" == "ubuntu" ]] || [[ "$DISTRO_ID" == "debian" ]] || [[ "$DISTRO_ID_LIKE" == *"debian"* ]] || [[ "$DISTRO_ID_LIKE" == *"ubuntu"* ]]; then
		echo "Debian/Ubuntu-based distribution detected: $DISTRO_ID"
		return 1  # Debian/Ubuntu-based

	# Handle unsupported distros
	else
		echo "Unsupported distribution: $DISTRO_ID"
		return 2  # Unsupported
	fi
}

#-- ----------------------------------------- --
#-- BASED RHEL ------------------------------ --
#-- ----------------------------------------- --

k8s_rhel_req() {
	echo "Installing required Kubernetes packages..."
	sudo tee /etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl="https://pkgs.k8s.io/core:/stable:/${KUBE_PKG_VER}/rpm"
enabled=1
gpgcheck=1
gpgkey="https://pkgs.k8s.io/core:/stable:/${KUBE_PKG_VER}/rpm/repodata/repomd.xml.key"
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF
	sudo dnf install -y net-tools iproute-tc kubelet-${KUBE_VERSION} kubeadm-${KUBE_VERSION} kubectl-${KUBE_VERSION} --disableexcludes=kubernetes
	if [ $? -ne 0 ]; then
		echo "Error: Unable to install Kubernetes packages on RHEL Based Distro."
		exit 1
	fi
	sudo systemctl enable --now kubelet
	if [ $? -ne 0 ]; then
		echo "Error: Unable to start kubelet service."
		exit 1
	fi
}

# container runtime RHEL
rhel_container_runtime() {
	echo "Configuring container runtime (containerd)..."
	sudo dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
	sudo dnf install -y containerd.io
	sudo containerd config default | sudo tee /etc/containerd/config.toml
	sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
	sudo systemctl enable --now containerd

	if [ $? -ne 0 ]; then
		echo "Error: Unable to start containerd service."
		exit 1
	fi
}

# docker service
rhel_docker_install() {
	echo "Installing docker CE on Based RHEL Distro..."
	
	# Check if docker repo
	if [ ! sudo dnf repolist | grep -q "docker-ce" ]; then
		echo "Adding Docker repository..."
		sudo dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
	else
		echo "Docker repository already added."
	fi

	sudo dnf install -y docker-ce
	sudo usermod -aG docker $USER

	sudo systemctl enable --now docker

	if [ $? -ne 0 ]; then
		echo "Error: Unable to start docker service."
		exit 1
	fi
}

# docker-compose
rhel_compose_install() {
	echo "Installing docker-compose..."
	curl -fsSL https://github.com/docker/compose/releases/download/${DC_VER}/docker-compose-linux-x86_64 -o docker-compose && \
	chmod 750 docker-compose && \
	sudo mv docker-compose /usr/local/bin/

	if [ -z "$(command -v docker-compose)" ]; then
		echo "Error: Failure to install docker-compose."
		exit 1
	else
		echo "docker-compose installed!"
	fi
}

#-- ----------------------------------------- --
#-- DEBIAN/UBUNTU --------------------------- --
#-- ----------------------------------------- --

k8s_deb_req() {
	echo "Installing required Kubernetes packages..."

	# https://kubernetes.io/blog/2023/08/15/pkgs-k8s-io-introduction/
	echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${KUBE_PKG_VER}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
	curl -fsSL "https://pkgs.k8s.io/core:/stable:/${KUBE_PKG_VER}/deb/Release.key" | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
	

	if [ $? -ne 0 ]; then
		echo "Error: There was an issue configuring the k8s repository."
		exit 1
	fi

	sudo apt-get -y update
	sudo apt-get install -y kubelet kubeadm kubectl
	# Use this one for specific version:
	#sudo apt-get install -y kubelet=${KUBE_VERSION} kubeadm=${KUBE_VERSION} kubectl=${KUBE_VERSION}

	if [ $? -ne 0 ]; then
		echo "Error: Unable to install Kubernetes packages on Debian/Ubuntu."
		exit 1
	fi

	sudo systemctl enable --now kubelet
	if [ $? -ne 0 ]; then
		echo "Error: Unable to start kubelet service."
		exit 1
	fi
}

# container runtime DEBIAN
deb_container_runtime() {
	echo "Configuring container runtime (containerd)..."
	sudo apt-get install -y containerd
	sudo mkdir /etc/containerd/ && sudo touch /etc/containerd/config.toml
	sudo containerd config default | sudo tee /etc/containerd/config.toml
	sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
	sudo systemctl enable --now containerd

	if [ $? -ne 0 ]; then
		echo "Error: Unable to start containerd service."
		exit 1
	fi
}

# docker service
deb_docker_install() {
	echo "Installing docker CE on Debian/Ubuntu..."
	
	# Check if docker is already installed
	if [ -z "$(command -v docker)" ]; then
			
		echo "Add Docker's official GPG key:"
		sudo apt-get update -y
		sudo apt-get install ca-certificates curl gnupg
		sudo install -m 0755 -d /etc/apt/keyrings
		curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
		sudo chmod a+r /etc/apt/keyrings/docker.gpg

		echo "Add the repository to Apt sources:"
		echo \
		"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
		$(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
		sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
		sudo apt-get update -y

		echo "Install the Docker depended packages:"
		sudo apt-get install -y \
			docker-ce \
			docker-ce-cli \
			containerd.io \
			docker-buildx-plugin \
			docker-compose-plugin

		echo "Fixing User permissions..."
		sudo usermod -aG docker $USER
	
	else
		echo "Docker already installed."
	fi

	echo "Preparing Docker Daemon..."

	sudo systemctl enable docker
	sudo systemctl start docker


	if [ $? -ne 0 ]; then
		echo "Error: docker service is failing to start. Check docker service logs."
		exit 1
	else
		echo "Docker service is running..."
	fi
}

# docker-compose
deb_compose_install() {
	echo "Installing docker-compose..."

	curl -fsSL https://github.com/docker/compose/releases/download/${DC_VER}/docker-compose-linux-x86_64 -o docker-compose && \
	chmod 750 docker-compose && \
	sudo mv docker-compose /usr/local/bin/

	if [ -z "$(command -v docker-compose)" ]; then
		echo "Error: Failure to install docker-compose."
		exit 1
	else
		echo "docker-compose installed!"
	fi
}

#-- -------------------  --
#-- Distro Function Call --
#-- -------------------  --

deb_call() {
	k8s_deb_req
	deb_container_runtime
}

rhel_call() {
	k8s_rhel_req
	rhel_container_runtime
}

#-- ----------------------- --
#-- K8s Network ----------- --
#-- ----------------------- --

initialize_control_plane() {
	echo "Initializing Kubernetes control plane..."
	
	if [ -z "$IFACE" ]; then
		echo "IFACE value is empty. Check it out."
		exit 1
	fi

	IP=$(ip addr show $IFACE | grep -oP 'inet \K[\d.]+')
	#sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=${IP}
	sudo kubeadm init \
		--pod-network-cidr="${POD_CIDR}" \
		--apiserver-advertise-address="${IP}"

	if [ $? -ne 0 ]; then
		echo "Error: Unable to initialize Kubernetes control plane."
		exit 1
	fi
}

kube_user_config() {
	echo "Applying regular user permissions..."
	mkdir -p "${HOME}/.kube"
	sudo cp -i /etc/kubernetes/admin.conf "${HOME}/.kube/config"
	sudo chown $(id -u):$(id -g) "${HOME}/.kube/config"
	echo 'export KUBECONFIG="${HOME}/.kube/config"'|tee -a $HOME/.profile
	source "${HOME}/.profile"
}

install_network_plugin() {
  echo "Installing K8s network plugin..."

  # Prompt the user to choose a network plugin
  echo "Choose a network plugin to install:"
  echo "1) Calico"
  echo "2) Flannel"
  read -p "Enter your choice (1 or 2): " NETWORK_CHOICE

  case $NETWORK_CHOICE in
    1)
      # Prompt for Calico version
      get_calico_version
      echo "Installing Calico plugin (version: $CALICO_VERSION)..."

			CALICO_MANIFEST="calico.yaml"

      kubectl apply -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/${CALICO_MANIFEST}"
			
      if [ $? -ne 0 ]; then
        echo "Error: Unable to install Calico network plugin."
        exit 1
      fi
      ;;
    2)
      # Prompt for Flannel version
      get_flannel_version
      echo "Installing Flannel plugin (version: $FLANNEL_VERSION)..."

			FLANNEL_MANIFEST="kube-flannel.yml"
			curl -LO "https://github.com/flannel-io/flannel/releases/download/${FLANNEL_VERSION}/${FLANNEL_MANIFEST}"

			# Adjust Flannel's Network to match custom Pod CIDR if needed
			if [[ "$POD_CIDR" != "10.244.0.0/16" ]]; then
				echo "Patching Flannel manifest to use custom Pod CIDR: $POD_CIDR"
				sed -i "s|\"Network\": \"10.244.0.0/16\"|\"Network\": \"$POD_CIDR\"|" "$FLANNEL_MANIFEST"
			fi

			kubectl apply -f "$FLANNEL_MANIFEST"

			if [ $? -ne 0 ]; then
				echo "Error: Unable to install Flannel network plugin."
				exit 1
			fi
      ;;
    *)
      echo "Invalid choice. Please run the script again and choose a valid option."
      exit 1
      ;;
  esac

  echo "Network plugin installation completed successfully."
}

# Join node(s) function -- Worker Nodes
join_node() {
	echo "Joining Kubernetes node to the cluster..."
	sudo kubeadm join $CONTROL_PLANE:$PORT --token $TOKEN \
	--discovery-token-ca-cert-hash $HASH

	if [ $? -ne 0 ]; then
		echo "Error: Unable to join Kubernetes node to the cluster."
		exit 1
	fi
}

#-- ------------------------------- --
#-- Main Shell Script ------------- --
#-- ------------------------------- --

# Check if the correct number of arguments is provided
if [ "$#" -ne 1 ]; then
	usage
fi

# Determine the type of installation based on the argument
detect_distro_type
distro_type=$?

if [ $distro_type -eq 0 ]; then
	echo "RHEL-based system detected."
	rhel_call

elif [ $distro_type -eq 1 ]; then
	echo "Debian/Ubuntu-based system detected."    
	deb_call

else
	echo "Unsupported Linux Distribution."
	exit 1
fi

case $1 in
	control-plane)
		get_interface_name
		get_pod_cidr
		prereq_kernel
		prereq_params
		environment
		initialize_control_plane
		kube_user_config
		install_network_plugin
		ask_install_docker
		ask_install_compose
		;;
	node)
		get_port
		get_control_plane_ip
		get_control_plane_token
		get_control_plane_hash
		prereq_kernel
		prereq_params
		environment
		join_node
		ask_install_docker
		ask_install_compose
		;;
	*)
		echo "Invalid option. Use 'control-plane' or 'node'."
		usage
		;;
esac

echo "Kubernetes installation and configuration completed."
