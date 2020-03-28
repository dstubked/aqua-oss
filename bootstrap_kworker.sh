#!/bin/bash
#Change these values to suit your needs
AQUA_REGISTRY_USERNAME="XXXXXXXX"
AQUA_REGISTRY_PASSWORD="XXXXXXXX"
AQUA_DB_PASSWORD="XXXXXXXX"
ADMIN_USER=administrator
ADMIN_PASSWORD=XXXXXXXX
IMAGE_TAG=4.6.20079

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
#Other vars
AQUA_DB_IMAGE=registry.aquasec.com/database:$IMAGE_TAG
AQUA_CONSOLE_IMAGE=registry.aquasec.com/console:$IMAGE_TAG
AQUA_GATEWAY_IMAGE=registry.aquasec.com/gateway:$IMAGE_TAG
AQUA_ENFORCER_IMAGE=registry.aquasec.com/enforcer:$IMAGE_TAG

docker login registry.aquasec.com -u $AQUA_REGISTRY_USERNAME -p $AQUA_REGISTRY_PASSWORD
sleep 20
docker pull $AQUA_DB_IMAGE
docker pull $AQUA_CONSOLE_IMAGE
docker pull $AQUA_GATEWAY_IMAGE
docker pull $AQUA_ENFORCER_IMAGE

KUBECONFIG=/home/vagrant/.kube/config

kubectl --kubeconfig=/home/vagrant/.kube/config create namespace aqua

kubectl --kubeconfig=/home/vagrant/.kube/config create secret docker-registry aqua-registry \
        --docker-server=registry.aquasec.com \
        --docker-username=$AQUA_REGISTRY_USERNAME \
        --docker-password=$AQUA_REGISTRY_PASSWORD \
        --docker-email=no@email.com -n aqua


kubectl --kubeconfig=/home/vagrant/.kube/config create secret generic aqua-db \
        --from-literal=password=$AQUA_DB_PASSWORD -n aqua

kubectl --kubeconfig=/home/vagrant/.kube/config create -n aqua -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: aqua-sa
imagePullSecrets:
- name: aqua-registry
EOF

cat > deploycsp.yaml << EOF
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: aqua-discovery-cr
rules:
- apiGroups: [""]
  resources: ["nodes", "services", "endpoints", "pods", "deployments", "namespaces","componentstatuses"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["rbac.authorization.k8s.io"]
  resources: ["*"]
  verbs: ["get", "list", "watch"]
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: aqua-discovery-crb
roleRef:
  name: aqua-discovery-cr
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
subjects:
  - kind: ServiceAccount
    name: aqua-sa
    namespace: aqua
---
apiVersion: v1
kind: Service
metadata:
  name: aqua-db
  labels:
    app: aqua-db
spec:
  type: ClusterIP
  selector:
    app: aqua-db
  ports:
    - port: 5432
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: aqua-db
  labels:
    app: aqua-db
spec:
  replicas: 1
  selector:
    matchLabels:
      app: aqua-db
  template:
    metadata:
      labels:
        app: aqua-db
      name: aqua-db
    spec:
      serviceAccount: aqua-sa
      restartPolicy: Always
      containers:
      - name: aqua-db
        image: $AQUA_DB_IMAGE
        imagePullPolicy: IfNotPresent
        env:
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              key: password
              name: aqua-db
        volumeMounts:
        - mountPath: /var/lib/postgresql/data
          name: postgres-db
        ports:
        - containerPort: 5432
          protocol: TCP
      volumes:
      - name: postgres-db
        hostPath:
          path: /var/lib/aqua/db
---
apiVersion: v1
kind: Service
metadata:
  name: aqua-web
  labels:
    app: aqua-web
spec:      
  ports:
    - port: 443
      protocol: TCP
      targetPort: 8443
      name: aqua-web-ssl
    - port: 8080
      protocol: TCP
      targetPort: 8080
      name: aqua-web
  selector:
    app: aqua-web
  type: NodePort
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: aqua-web
  name: aqua-web
spec:
  replicas: 1
  selector:
    matchLabels:
      app: aqua-web
  template:
    metadata:
      labels:
        app: aqua-web
      name: aqua-web
    spec:
      # To run Aqua components as a non-privileged account 
      # (part 1 of 2 for aqua-web deployment).
      # Note: Update 5 (4.6.20072) or higher is required.
      # Uncomment the next 4 lines:
      #securityContext:
      #  runAsUser: 11431
      #  runAsGroup: 11433
      #  fsGroup: 11433
      serviceAccount: aqua-sa
      restartPolicy: Always
      containers:
      - env:
        - name: SCALOCK_DBUSER
          value: postgres
        - name: SCALOCK_DBPASSWORD
          valueFrom:
            secretKeyRef:
              key: password
              name: aqua-db
        - name: SCALOCK_DBNAME
          value: scalock
        - name: SCALOCK_DBHOST
          value: aqua-db
        - name: SCALOCK_DBPORT
          value: "5432"
        - name: SCALOCK_AUDIT_DBUSER
          value: postgres
        - name: SCALOCK_AUDIT_DBPASSWORD
          valueFrom:
            secretKeyRef:
              key: password
              name: aqua-db
        - name: SCALOCK_AUDIT_DBNAME
          value: slk_audit
        - name: SCALOCK_AUDIT_DBHOST
          value: aqua-db
        - name: SCALOCK_AUDIT_DBPORT
          value: "5432"
        - name: AQUA_CONSOLE_RAW_SCAN_RESULTS_STORAGE_SIZE
          value: "4"
        - name: ADMIN_PASSWORD
          value: "$ADMIN_PASSWORD"
        - name: LICENSE_TOKEN
          value: "uL0LQlYKvHL2WJC3bNQ7B-tl_dY-3djBzmpFQ6meg6UMFA815a59jEM0QIiq-LTVauUSeWcU9b-fzubjrtDsC769gdsbxXLjNRmIBiRFizM5Pm-L6anin5Bg_fb7pIPQCJkO1qXfagfe4pzuSuDNdAsjWM4y7Fn0yawbdRSuUYt3-4JMdiaqE51pAhH2xul-Ho6kVQrXOlXnrunA4bZU-zh9oAmmrbIqr30KmKFuSq2NP2gRvzuWkw6V3j_ajR1bspJ-M4BHjIKQDVK_B3NAxY4QlbiG18gv7CIp3iAkMpWty6H1AeMy8GD72n0Bqr9-R0uaHN_xI2GqCMqdSktWUFBUfJV-jkGrsQuOynMiUtpBJwQ7sNdzvlQMihxdRPJYYUVU4SI5aSPwnSoWQdmtxr6_nvXwySwhZLswx2epdbWSBpJZ8G-uX-cuoisV3-qFTVTKrr5ZqSx2quISs69-JAcUYXT-13pcRyvbPlr2XxiuW8JeedczhZWJPy0s7l6YLUYm7wc7yhbetNyMohN_QCF_lQ7dnCK6_pF8pMrOKaFvQR1OqQFLjlOnPSIAYa_3liFKzqIFCHLGgiDNuE9ku9my20tTdcq-QJYC4A0Z6lY="
        image: $AQUA_CONSOLE_IMAGE
        imagePullPolicy: IfNotPresent
        # To run Aqua components as a non-privileged account
        # (part 2 of 2 for aqua-web deployment)
        # Note: Update 5 (4.6.20072) or higher is required.
        # Comment out the next 2 lines:
        securityContext:
          privileged: true
        name: aqua-web
        ports:
        - containerPort: 8080
          protocol: TCP
        - containerPort: 8443
          protocol: TCP
        volumeMounts:
        - mountPath: /opt/aquasec/raw-scan-results
          name: aqua-raw-scan-results
        - mountPath: /var/run/docker.sock
          name: docker-socket-mount
      volumes:
      - name: docker-socket-mount
        hostPath:
          path: /var/run/docker.sock
      - name: aqua-raw-scan-results
        hostPath:
          path: /var/lib/aqua/raw-scan-results
---
apiVersion: v1
kind: Service
metadata:
  name: aqua-gateway
  labels:
    app: aqua-gateway
spec:
  type: ClusterIP
  ports:
    - port: 8443
      protocol: TCP
      targetPort: 8443
      name: aqua-gateway-ssl
    - port: 3622
      protocol: TCP
      targetPort: 3622
      name: aqua-gateway
  selector:
    app: aqua-gateway
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: aqua-gateway
  name: aqua-gateway
spec:
  replicas: 1
  selector:
    matchLabels:
      app: aqua-gateway
  template:
    metadata:
      labels:
        app: aqua-gateway
      name: aqua-gateway
    spec:
      # To run Aqua components as a non-privileged account 
      # (part 1 of 2 for aqua-gateway deployment)
      # Note: Update 5 (4.6.20072) or higher is required.
      # Uncomment the next 4 lines:
      #securityContext:
      #  runAsUser: 11431
      #  runAsGroup: 11433
      #  fsGroup: 11433
      serviceAccount: aqua-sa
      restartPolicy: Always
      containers:
      - name: aqua-gateway
        image: $AQUA_GATEWAY_IMAGE
        imagePullPolicy: IfNotPresent
        # To run Aqua components as a non-privileged account
        # (part 2 of 2 for aqua-gateway deployment)
        # Note: Update 5 (4.6.20072) or higher is required.
        # Comment out the next 2 lines:
        securityContext:
          privileged: true
        env:
        - name: AQUA_CONSOLE_SECURE_ADDRESS
          value: aqua-web:443
        - name: SCALOCK_GATEWAY_PUBLIC_IP
          value: aqua-gateway
        - name: SCALOCK_DBUSER
          value: postgres
        - name: SCALOCK_DBPASSWORD
          valueFrom:
            secretKeyRef:
              key: password
              name: aqua-db
        - name: SCALOCK_DBNAME
          value: scalock
        - name: SCALOCK_DBHOST
          value: aqua-db
        - name: SCALOCK_DBPORT
          value: "5432"
        - name: SCALOCK_AUDIT_DBUSER
          value: postgres
        - name: SCALOCK_AUDIT_DBPASSWORD
          valueFrom:
            secretKeyRef:
              key: password
              name: aqua-db
        - name: SCALOCK_AUDIT_DBNAME
          value: slk_audit
        - name: SCALOCK_AUDIT_DBHOST
          value: aqua-db
        - name: SCALOCK_AUDIT_DBPORT
          value: "5432"
        ports:
        - containerPort: 3622
          protocol: TCP
        - containerPort: 8443
          protocol: TCP
EOF

kubectl --kubeconfig=/home/vagrant/.kube/config create -f deploycsp.yaml -n aqua

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

# Start Enforcer install
# Install JQ
sudo apt-get install -y jq

cat > enforcer-group-sample.json << EOF
{
    "gateways": ["AQUA_GATEWAY_NAME_gateway"],
    "description": "Aqua Group",
    "enforce": true,
    "logicalname": "",
    "host_os": "Linux",
    "id": "Prod",
    "orchestrator": {
        "type": "kubernetes",
        "service_account": "aqua-sa",
        "namespace": "aqua"
    },
    "audit_success_login": true,
    "audit_failed_login": true,

    "image_assurance": true,
    "host_protection": true,
    "runtime_type": "docker",
    "syscall_enabled": true,
    "network_protection": true,
    "user_access_control": true,

    "container_activity_protection": true,
    "host_network_protection": true,
    "sync_host_images": true
}
EOF

# Get Aqua deployment environment details
#NodePort=`kubectl describe service aqua-web -n aqua | grep NodePort | grep aqua-web | tail -1 | awk '{print substr($3,1,5)}'`
#aqua_console_url="http://172.42.42.101:$NodePort"
gateway_podname=`kubectl --kubeconfig=/home/vagrant/.kube/config get pod -n aqua | grep gateway | awk '{print $1}'`
gateway_settings=enforcer-group.json

# Update with your bearer token 
#Get auth token

access_token=$(curl -X POST \
  $aqua_console_url/api/v1/login \
  -H 'Content-Type: application/json' \
  -H 'cache-control: no-cache' \
  -d '{ "id": "'$ADMIN_USER'", "password": "'$ADMIN_PASSWORD'" }' \
  | jq -r '.token')

# ************************************************************************************************************************************************************************

#Print values for sanity checks
echo "Aqua console user is $ADMIN_USER"
echo "Aqua console password is $ADMIN_PASSWORD"
echo "Aqua console URL is $aqua_console_url"
echo "Aqua gateway pod name is $gateway_podname"
echo "Aqua access token is $access_token"


# Update enforcer-group.json with gateway pod name
cat enforcer-group-sample.json | sed "s/AQUA_GATEWAY_NAME/$gateway_podname/g" > $gateway_settings

enforcer_group=$(cat $gateway_settings | jq  '.id' | sed 's/"//g' | sed 's/ /-/g')


echo "Enforcer group name is $enforcer_group"

# Create enforcer group. Extract the kubernetes command section and perform string manipulation on the yaml to k8s format.
curl --location --request POST "${aqua_console_url}/api/v1/hostsbatch" \
--header 'Content-Type: application/json' \
--header "Authorization: Bearer ${access_token}" \
-d @enforcer-group.json | jq '.command.kubernetes' | sed 's/^.\(.*\).$/\1/' | sed 's/\\n/\n/g' | sed 's/\\//g'  > $enforcer_group.yaml

#orig=`cat Prod.yaml | grep image | awk '{print $2}'`
#echo $orig
#cat $enforcer_group.yaml | sed "s/\$orig/\$new_version/g" > deploy_enforcers.yaml

# Apply the enforcer daemonset yaml
kubectl --kubeconfig=/home/vagrant/.kube/config apply -f $enforcer_group.yaml -n aqua
sleep 20
kubectl --kubeconfig=/home/vagrant/.kube/config get pods -n aqua
echo""
echo "Installation Done!"
echo "Login to Aqua here: $aqua_console_url"
