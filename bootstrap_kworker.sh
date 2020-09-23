#!/bin/bash
AQUA_REGISTRY_USERNAME="XXXXXXXX"
AQUA_REGISTRY_PASSWORD="XXXXXXXX"
ADMIN_USER=administrator
ADMIN_PASSWORD=XXXXXXXX
AQUA_LICENSE_KEY="XXXXXXXX"
IMAGE_TAG=5.3.20261

# Join worker nodes to the Kubernetes cluster
echo "[TASK 1] Join node to Kubernetes Cluster"
apt-get  install -y sshpass >/dev/null 2>&1
#sshpass -p "kubeadmin" scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no kmaster.example.com:/joincluster.sh /joincluster.sh 2>/dev/null
sshpass -p "kubeadmin" scp -o StrictHostKeyChecking=no kmaster.example.com:/joincluster.sh /joincluster.sh
bash /joincluster.sh >/dev/null 2>&1
# Copy kubecfg file into worker
mkdir /home/vagrant/.kube
sshpass -p "kubeadmin" scp -o StrictHostKeyChecking=no kmaster.example.com:/home/vagrant/.kube/config /home/vagrant/.kube/config
chown -R vagrant:vagrant .kube

echo "[TASK 2] Auto Installing Aqua $IMAGE_TAG"

sleep 20

KUBECONFIG=/home/vagrant/.kube/config

sudo ln -s /usr/bin/kubectl /usr/bin/k

# on the node, where the POD will be located (node1 in our case):
DIRNAME="vol1"
sudo mkdir -p /mnt/disk/$DIRNAME 
sudo chcon -Rt svirt_sandbox_file_t /mnt/disk/$DIRNAME
sudo chmod 777 /mnt/disk/$DIRNAME

# on the node, where the POD will be located (node1 in our case):
DIRNAME="vol2"
sudo mkdir -p /mnt/disk/$DIRNAME 
sudo chcon -Rt svirt_sandbox_file_t /mnt/disk/$DIRNAME
sudo chmod 777 /mnt/disk/$DIRNAME

# on master:

cat > storageClass.yaml << EOF
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: local-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
EOF

kubectl --kubeconfig=/home/vagrant/.kube/config create -f storageClass.yaml


cat > persistentVolume1.yaml << EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: aqua1-local-pv
spec:
  capacity:
    storage: 50Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  local:
    path: /mnt/disk/vol1
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - kworker1
EOF

kubectl --kubeconfig=/home/vagrant/.kube/config create -f persistentVolume1.yaml

cat > persistentVolume2.yaml << EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: aqua2-local-pv
spec:
  capacity:
    storage: 50Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  local:
    path: /mnt/disk/vol2
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - kworker1
EOF

kubectl --kubeconfig=/home/vagrant/.kube/config create -f persistentVolume2.yaml

wget https://get.aquasec.com/aquactl/stable/aquactl

chmod +x aquactl

export KUBECONFIG=/home/vagrant/.kube/config

./aquactl deploy csp \
    --approve --version $IMAGE_TAG --platform kubernetes --server-service NodePort --aqua-username $AQUA_REGISTRY_USERNAME --aqua-password $AQUA_REGISTRY_PASSWORD --namespace aqua --admin-password $ADMIN_PASSWORD --storage-class local-storage \
    --license $AQUA_LICENSE_KEY \
    --deploy-enforcer --deploy-scanner --no-spinner

#Check Aqua gateway and console status
echo "Get Aqua service status: kubectl --kubeconfig=/home/vagrant/.kube/config get svc -n aqua"
kubectl --kubeconfig=/home/vagrant/.kube/config get svc -n aqua
NodePort=`kubectl --kubeconfig=/home/vagrant/.kube/config describe service aqua-web -n aqua | grep NodePort | grep aqua-web | tail -1 | awk '{print substr($3,1,5)}'`
aqua_console_url="http://172.42.42.101:$NodePort"
echo ""

printf "\nChecking if Aqua Server is up\n"
i=1
until $(curl -m 5 --output /dev/null --silent --fail "$aqua_console_url/#!/login"); do
    if [ ${i} -eq 300 ]; then
       echo "Time out waiting for Aqua Server. Deployment must be finished manually."
       break
    fi
    printf '.\n'
    sleep 5
    i=$((i+1))
done
printf '\n'
echo "Success!"
echo "Get Aqua status: kubectl --kubeconfig=/home/vagrant/.kube/config get pods -n aqua"
kubectl --kubeconfig=/home/vagrant/.kube/config get pods -n aqua

# Set enforcer to enforce
curl -H 'Content-Type: application/json' -X GET -u $ADMIN_USER:$ADMIN_PASSWORD $aqua_console_url/api/v1/hostsbatch/aquactl-default > enforce.json
sed -i 's/\"enforce\":false/\"enforce\":true/g' enforce.json
curl -H 'Content-Type: application/json' -X PUT -u $ADMIN_USER:$ADMIN_PASSWORD -d @enforce.json $aqua_console_url/api/v1/hostsbatch?update_enforcers=true

echo "[TASK 3] Deploy Sock Shop"

kubectl --kubeconfig=/home/vagrant/.kube/config create namespace sock-shop
kubectl --kubeconfig=/home/vagrant/.kube/config apply -f https://raw.githubusercontent.com/dstubked/aqua-oss/master/sock-shop.yaml

# Setup Wordpress Demo
# Set a new secret
echo "[TASK 4] Deploy Sock Shop"
sleep 60
curl "${aqua_console_url}/api/v1/secrets" -u $ADMIN_USER:$ADMIN_PASSWORD -X POST  -H 'Content-Type: application/json;charset=UTF-8' --data-binary '{"key":"mysql.password","source":"aqua","source_type":"aqua","password":"SecretPasswordMYSQL"}' --compressed
sleep 5
echo

kubectl --kubeconfig=/home/vagrant/.kube/config apply -f https://raw.githubusercontent.com/dstubked/aqua-oss/master/blog-wordpress.yaml

# Deploy Jenkins on Docker
[TASK 4] Deploy Sock Shop
docker run -d --name jenkins-server --restart=always -p 8080:8080 dstubked/jenkins:latest

echo "* * * * Demo Setup Completed! * * * *"
echo "Kubernetes Assigned Aqua Address is: $aqua_console_url."
echo "Aqua admin user name is $ADMIN_USER
echo "Aqua admin password is $ADMIN_PASSWORD
echo "Jenkins assigned Address is: http://172.42.42.101:8080"
echo "Jenkins user name is administrator"
echo "Jenkins user password is Password1"

