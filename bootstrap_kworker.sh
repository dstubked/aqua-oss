#!/bin/bash


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

./aquactl deploy csp \
    --approve --version 5.0 --platform kubernetes --server-service NodePort --aqua-username demo@aquasec.com --aqua-password 9aV6xpQE --namespace aqua --admin-password Password1 --storage-class local-storage \
    --license cdIdZOB3g8fwprpF3HK6fYwXdXRdu9OwomF-WtPPotJiQ9fRX65bteHIb3pwFm0ciXiiSdgsyXKMChlKpFboIhJjJnEpocTzNHuqAMadGQdOPpsLN0wJOsCL5HuxAFAwXxAT79M3S34FHfEK7i0Hqcr2hNhe5yQV-K91MuDJf9R-OChif3h9R5ZyVl9ZnX47WdvCv9ZRzw0DdrHgNhsV3qzjomtM4t8eY57S-vmmlHWBHH4GfvTNVEZge2nFeNOiplknTpR1sqHCeC5WI2tfy1kfdAuR8SYO79d8Oq8EvY4EeS2OVc3dRbQrAPjfLiCfBWgCTuDFxKWapX6ywIQNSxL0XP8UnDoH6i8y8byRd0FK3CXzLu81TQNVlrbSvAGMf2_AbBkNuZiGU9rXoWbY9D0pxmfRDmqBpSwM46COJXvYE_13tpbu-B2n6Hsxtl4W0U6JuBzLYjWmjRJZnsDD24qnEQegCy-svl3dydkS5-WulUVAqr2E8TX2p_pQVv9WM_TjbO9gDv3yGWqyUeD0KeJspOxisq8RavJI9t7rCRpM8Db2q8fiwYtKrqxKp0ix3J4EuA58X0_TYRdyG6VJ8xkLReP3jUpPOd8m0fDOQEs= \
    --deploy-enforcer --deploy-scanner

#Check Aqua gateway and console status
echo "Get Aqua service status: kubectl --kubeconfig=/home/vagrant/.kube/config get svc -n aqua"
kubectl --kubeconfig=/home/vagrant/.kube/config get svc -n aqua
NodePort=`kubectl --kubeconfig=/home/vagrant/.kube/config describe service aqua-web -n aqua | grep NodePort | grep aqua-web | tail -1 | awk '{print substr($3,1,5)}'`
aqua_console_url="http://172.42.42.101:$NodePort"
echo ""
echo "Kubernetes Assigned Aqua Address is: $aqua_console_url"

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
