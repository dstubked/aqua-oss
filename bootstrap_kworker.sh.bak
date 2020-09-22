#!/bin/bash
# * * * * REVIEW THESE VALUES BEFORE YOU START! * * * *
# Change these values to suit your needs
AQUA_REGISTRY_USERNAME="XXXXXXXX"
AQUA_REGISTRY_PASSWORD="XXXXXXXX"
AQUA_DB_PASSWORD="XXXXXXXX"
AQUA_LICENSE_KEY="XXXXXXXX"
ADMIN_USER=administrator
ADMIN_PASSWORD=XXXXXXXX
IMAGE_TAG=4.6.20079

# Uncomment if using official Aqua repo at registry.aquasec.com
#AQUA_DB_IMAGE=registry.aquasec.com/database:$IMAGE_TAG
#AQUA_CONSOLE_IMAGE=registry.aquasec.com/console:$IMAGE_TAG
#AQUA_GATEWAY_IMAGE=registry.aquasec.com/gateway:$IMAGE_TAG
#AQUA_ENFORCER_IMAGE=registry.aquasec.com/enforcer:$IMAGE_TAG
#docker login registry.aquasec.com -u $AQUA_REGISTRY_USERNAME -p $AQUA_REGISTRY_PASSWORD

# Pulls from self hosted image at docker hub. Comment this out if using official Aqua repo at registry.aquasec.com
AQUA_DB_IMAGE=dstubked/da:$IMAGE_TAG
AQUA_CONSOLE_IMAGE=dstubked/co:$IMAGE_TAG
AQUA_GATEWAY_IMAGE=dstubked/ga:$IMAGE_TAG
AQUA_ENFORCER_IMAGE=dstubked/en:$IMAGE_TAG

# * * * * REVIEW ENDS HERE * * * *

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
          value: "$AQUA_LICENSE_KEY"
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

# Deploy Sock Shop Demo

cat > sock-shop.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: carts-db
  labels:
    name: carts-db
  namespace: sock-shop
spec:
  selector:
    matchLabels:
      name: carts-db
  replicas: 1
  template:
    metadata:
      labels:
        name: carts-db
    spec:
      containers:
      - name: carts-db
        image: mongo
        ports:
        - name: mongo
          containerPort: 27017
        securityContext:
          capabilities:
            drop:
              - all
            add:
              - CHOWN
              - SETGID
              - SETUID
          readOnlyRootFilesystem: true
        volumeMounts:
        - mountPath: /tmp
          name: tmp-volume
      volumes:
        - name: tmp-volume
          emptyDir:
            medium: Memory
      nodeSelector:
        beta.kubernetes.io/os: linux
---
apiVersion: v1
kind: Service
metadata:
  name: carts-db
  labels:
    name: carts-db
  namespace: sock-shop
spec:
  ports:
    # the port that this service should serve on
  - port: 27017
    targetPort: 27017
  selector:
    name: carts-db
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: carts
  labels:
    name: carts
  namespace: sock-shop
spec:
  selector:
    matchLabels:
      name: carts
  replicas: 1
  template:
    metadata:
      labels:
        name: carts
    spec:
      containers:
      - name: carts
        image: weaveworksdemos/carts:0.4.8
        ports:
         - containerPort: 80
        env:
         - name: ZIPKIN
           value: zipkin.jaeger.svc.cluster.local
         - name: JAVA_OPTS
           value: -Xms64m -Xmx128m -XX:PermSize=32m -XX:MaxPermSize=64m -XX:+UseG1GC -Djava.security.egd=file:/dev/urandom
        securityContext:
          runAsNonRoot: true
          runAsUser: 10001
          capabilities:
            drop:
              - all
            add:
              - NET_BIND_SERVICE
          readOnlyRootFilesystem: true
        volumeMounts:
        - mountPath: /tmp
          name: tmp-volume
      volumes:
        - name: tmp-volume
          emptyDir:
            medium: Memory
      nodeSelector:
        beta.kubernetes.io/os: linux
---
apiVersion: v1
kind: Service
metadata:
  name: carts
  labels:
    name: carts
  namespace: sock-shop
spec:
  ports:
    # the port that this service should serve on
  - port: 80
    targetPort: 80
  selector:
    name: carts
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: catalogue-db
  labels:
    name: catalogue-db
  namespace: sock-shop
spec:
  selector:
    matchLabels:
      name: catalogue-db
  replicas: 1
  template:
    metadata:
      labels:
        name: catalogue-db
    spec:
      containers:
      - name: catalogue-db
        image: weaveworksdemos/catalogue-db:0.3.0
        env:
          - name: MYSQL_ROOT_PASSWORD
            value: fake_password
          - name: MYSQL_DATABASE
            value: socksdb
        ports:
        - name: mysql
          containerPort: 3306
      nodeSelector:
        beta.kubernetes.io/os: linux
---
apiVersion: v1
kind: Service
metadata:
  name: catalogue-db
  labels:
    name: catalogue-db
  namespace: sock-shop
spec:
  ports:
    # the port that this service should serve on
  - port: 3306
    targetPort: 3306
  selector:
    name: catalogue-db
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: catalogue
  labels:
    name: catalogue
  namespace: sock-shop
spec:
  selector:
    matchLabels:
      name: catalogue
  replicas: 1
  template:
    metadata:
      labels:
        name: catalogue
    spec:
      containers:
      - name: catalogue
        image: weaveworksdemos/catalogue:0.3.5
        ports:
        - containerPort: 80
        securityContext:
          runAsNonRoot: true
          runAsUser: 10001
          capabilities:
            drop:
              - all
            add:
              - NET_BIND_SERVICE
          readOnlyRootFilesystem: true
      nodeSelector:
        beta.kubernetes.io/os: linux
---
apiVersion: v1
kind: Service
metadata:
  name: catalogue
  labels:
    name: catalogue
  namespace: sock-shop
spec:
  ports:
    # the port that this service should serve on
  - port: 80
    targetPort: 80
  selector:
    name: catalogue
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: front-end
  namespace: sock-shop
spec:
  selector:
    matchLabels:
      name: front-end
  replicas: 1
  template:
    metadata:
      labels:
        name: front-end
    spec:
      containers:
      - name: front-end
        image: weaveworksdemos/front-end:0.3.12
        resources:
          requests:
            cpu: 100m
            memory: 100Mi
        ports:
        - containerPort: 8079
        securityContext:
          runAsNonRoot: true
          runAsUser: 10001
          capabilities:
            drop:
              - all
          readOnlyRootFilesystem: true
      nodeSelector:
        beta.kubernetes.io/os: linux
---
apiVersion: v1
kind: Service
metadata:
  name: front-end
  labels:
    name: front-end
  namespace: sock-shop
spec:
  type: NodePort
  ports:
  - port: 80
    targetPort: 8079
    nodePort: 30001
  selector:
    name: front-end
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: orders-db
  labels:
    name: orders-db
  namespace: sock-shop
spec:
  selector:
    matchLabels:
      name: orders-db
  replicas: 1
  template:
    metadata:
      labels:
        name: orders-db
    spec:
      containers:
      - name: orders-db
        image: mongo
        ports:
        - name: mongo
          containerPort: 27017
        securityContext:
          capabilities:
            drop:
              - all
            add:
              - CHOWN
              - SETGID
              - SETUID
          readOnlyRootFilesystem: true
        volumeMounts:
        - mountPath: /tmp
          name: tmp-volume
      volumes:
        - name: tmp-volume
          emptyDir:
            medium: Memory
      nodeSelector:
        beta.kubernetes.io/os: linux
---
apiVersion: v1
kind: Service
metadata:
  name: orders-db
  labels:
    name: orders-db
  namespace: sock-shop
spec:
  ports:
    # the port that this service should serve on
  - port: 27017
    targetPort: 27017
  selector:
    name: orders-db
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: orders
  labels:
    name: orders
  namespace: sock-shop
spec:
  selector:
    matchLabels:
      name: orders
  replicas: 1
  template:
    metadata:
      labels:
        name: orders
    spec:
      containers:
      - name: orders
        image: weaveworksdemos/orders:0.4.7
        env:
         - name: ZIPKIN
           value: zipkin.jaeger.svc.cluster.local
         - name: JAVA_OPTS
           value: -Xms64m -Xmx128m -XX:PermSize=32m -XX:MaxPermSize=64m -XX:+UseG1GC -Djava.security.egd=file:/dev/urandom
        ports:
        - containerPort: 80
        securityContext:
          runAsNonRoot: true
          runAsUser: 10001
          capabilities:
            drop:
              - all
            add:
              - NET_BIND_SERVICE
          readOnlyRootFilesystem: true
        volumeMounts:
        - mountPath: /tmp
          name: tmp-volume
      volumes:
        - name: tmp-volume
          emptyDir:
            medium: Memory
      nodeSelector:
        beta.kubernetes.io/os: linux
---
apiVersion: v1
kind: Service
metadata:
  name: orders
  labels:
    name: orders
  namespace: sock-shop
spec:
  ports:
    # the port that this service should serve on
  - port: 80
    targetPort: 80
  selector:
    name: orders
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment
  labels:
    name: payment
  namespace: sock-shop
spec:
  selector:
    matchLabels:
      name: payment
  replicas: 1
  template:
    metadata:
      labels:
        name: payment
    spec:
      containers:
      - name: payment
        image: weaveworksdemos/payment:0.4.3
        ports:
        - containerPort: 80
        securityContext:
          runAsNonRoot: true
          runAsUser: 10001
          capabilities:
            drop:
              - all
            add:
              - NET_BIND_SERVICE
          readOnlyRootFilesystem: true
      nodeSelector:
        beta.kubernetes.io/os: linux
---
apiVersion: v1
kind: Service
metadata:
  name: payment
  labels:
    name: payment
  namespace: sock-shop
spec:
  ports:
    # the port that this service should serve on
  - port: 80
    targetPort: 80
  selector:
    name: payment
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: queue-master
  labels:
    name: queue-master
  namespace: sock-shop
spec:
  selector:
    matchLabels:
      name: queue-master
  replicas: 1
  template:
    metadata:
      labels:
        name: queue-master
    spec:
      containers:
      - name: queue-master
        image: weaveworksdemos/queue-master:0.3.1
        ports:
        - containerPort: 80
      nodeSelector:
        beta.kubernetes.io/os: linux
---
apiVersion: v1
kind: Service
metadata:
  name: queue-master
  labels:
    name: queue-master
  annotations:
    prometheus.io/path: "/prometheus"
  namespace: sock-shop
spec:
  ports:
    # the port that this service should serve on
  - port: 80
    targetPort: 80
  selector:
    name: queue-master
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rabbitmq
  labels:
    name: rabbitmq
  namespace: sock-shop
spec:
  selector:
    matchLabels:
      name: rabbitmq
  replicas: 1
  template:
    metadata:
      labels:
        name: rabbitmq
    spec:
      containers:
      - name: rabbitmq
        image: rabbitmq:3.6.8
        ports:
        - containerPort: 5672
        securityContext:
          capabilities:
            drop:
              - all
            add:
              - CHOWN
              - SETGID
              - SETUID
              - DAC_OVERRIDE
          readOnlyRootFilesystem: true
      nodeSelector:
        beta.kubernetes.io/os: linux
---
apiVersion: v1
kind: Service
metadata:
  name: rabbitmq
  labels:
    name: rabbitmq
  namespace: sock-shop
spec:
  ports:
    # the port that this service should serve on
  - port: 5672
    targetPort: 5672
  selector:
    name: rabbitmq
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shipping
  labels:
    name: shipping
  namespace: sock-shop
spec:
  selector:
    matchLabels:
      name: shipping
  replicas: 1
  template:
    metadata:
      labels:
        name: shipping
    spec:
      containers:
      - name: shipping
        image: weaveworksdemos/shipping:0.4.8
        env:
         - name: ZIPKIN
           value: zipkin.jaeger.svc.cluster.local
         - name: JAVA_OPTS
           value: -Xms64m -Xmx128m -XX:PermSize=32m -XX:MaxPermSize=64m -XX:+UseG1GC -Djava.security.egd=file:/dev/urandom
        ports:
        - containerPort: 80
        securityContext:
          runAsNonRoot: true
          runAsUser: 10001
          capabilities:
            drop:
              - all
            add:
              - NET_BIND_SERVICE
          readOnlyRootFilesystem: true
        volumeMounts:
        - mountPath: /tmp
          name: tmp-volume
      volumes:
        - name: tmp-volume
          emptyDir:
            medium: Memory
      nodeSelector:
        beta.kubernetes.io/os: linux
---
apiVersion: v1
kind: Service
metadata:
  name: shipping
  labels:
    name: shipping
  namespace: sock-shop
spec:
  ports:
    # the port that this service should serve on
  - port: 80
    targetPort: 80
  selector:
    name: shipping
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: user-db
  labels:
    name: user-db
  namespace: sock-shop
spec:
  selector:
    matchLabels:
      name: user-db
  replicas: 1
  template:
    metadata:
      labels:
        name: user-db
    spec:
      containers:
      - name: user-db
        image: weaveworksdemos/user-db:0.4.0
        ports:
        - name: mongo
          containerPort: 27017
        securityContext:
          capabilities:
            drop:
              - all
            add:
              - CHOWN
              - SETGID
              - SETUID
          readOnlyRootFilesystem: true
        volumeMounts:
        - mountPath: /tmp
          name: tmp-volume
      volumes:
        - name: tmp-volume
          emptyDir:
            medium: Memory
      nodeSelector:
        beta.kubernetes.io/os: linux
---
apiVersion: v1
kind: Service
metadata:
  name: user-db
  labels:
    name: user-db
  namespace: sock-shop
spec:
  ports:
    # the port that this service should serve on
  - port: 27017
    targetPort: 27017
  selector:
    name: user-db
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: user
  labels:
    name: user
  namespace: sock-shop
spec:
  selector:
    matchLabels:
      name: user
  replicas: 1
  template:
    metadata:
      labels:
        name: user
    spec:
      containers:
      - name: user
        image: weaveworksdemos/user:0.4.7
        ports:
        - containerPort: 80
        env:
        - name: MONGO_HOST
          value: user-db:27017
        securityContext:
          runAsNonRoot: true
          runAsUser: 10001
          capabilities:
            drop:
              - all
            add:
              - NET_BIND_SERVICE
          readOnlyRootFilesystem: true
      nodeSelector:
        beta.kubernetes.io/os: linux
---
apiVersion: v1
kind: Service
metadata:
  name: user
  labels:
    name: user
  namespace: sock-shop
spec:
  ports:
    # the port that this service should serve on
  - port: 80
    targetPort: 80
  selector:
    name: user
EOF

kubectl --kubeconfig=/home/vagrant/.kube/config create namespace sock-shop
kubectl --kubeconfig=/home/vagrant/.kube/config apply -f sock-shop.yaml

# Setup Wordpress Demo
# Set a new secret
echo "Setting up Wordpress Demo"
sleep 60
curl "${aqua_console_url}/api/v1/secrets" -u $ADMIN_USER:$ADMIN_PASSWORD -X POST  -H 'Content-Type: application/json;charset=UTF-8' --data-binary '{"key":"mysql.password","source":"aqua","source_type":"aqua","password":"SecretPasswordMYSQL"}' --compressed
sleep 5
echo

cat > blog-wordpress.yaml << EOF
apiVersion: v1
kind: Namespace
metadata:
  name: blog
---
apiVersion: v1
data:
  username: cm9vdA==
kind: Secret
metadata:
  name: mysql-user
  namespace: blog
type: Opaque
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wp-db
  namespace: blog
spec:
  replicas: 1
  selector:
     matchLabels:
       app: wp-db
  template:
    metadata:
      labels:
        app: wp-db
    spec:
      containers:
      - name: wp-db
        image: mysql:8.0.0
        env:
        - name: "MYSQL_ROOT_PASSWORD"
          value: "{aqua.mysql.password}"
        ports:
          - containerPort: 3306
        readinessProbe:
            exec:
              command:
              - stat
              - /var/run/mysqld/mysqld.sock
            initialDelaySeconds: 30
            periodSeconds: 10
            successThreshold: 2
            timeoutSeconds: 2
---
apiVersion: v1
kind: Service
metadata:
  name: wp-db
  namespace: blog
  labels:
    app: wp-db
spec:
  ports:
    - port: 3306
  selector:
    app: wp-db
  type: ClusterIP
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wp-server
  namespace: blog
spec:
  replicas: 1
  selector:
     matchLabels:
       app: wp-server
  template:
    metadata:
      labels:
        app: wp-server
    spec:
      containers:
      - name: wp-server
        image: dstubked/wordpress:plugins
        env:
        - name: "WORDPRESS_DB_HOST"
          value: "wp-db"
        - name: "WORDPRESS_DB_USER"
          valueFrom:
            secretKeyRef:
              name: "mysql-user"
              key: "username"
        - name: "WORDPRESS_DB_PASSWORD"
          value: "{aqua.mysql.password}"
        ports:
          - containerPort: 80
        readinessProbe:
            httpGet:
              path: /wp-admin/
              port: 80
            initialDelaySeconds: 15
            periodSeconds: 10
            successThreshold: 2
            timeoutSeconds: 2
---
apiVersion: v1
kind: Service
metadata:
  name: wp-server
  namespace: blog
spec:
  externalTrafficPolicy: Local
  ports:
  - port: 80
    protocol: TCP
    targetPort: 80
  selector:
    app: wp-server
  type: NodePort
EOF

kubectl --kubeconfig=/home/vagrant/.kube/config apply -f blog-wordpress.yaml

# Deploy Jenkins on Docker
echo "Deploying Jenkins on Docker"
docker run -d --name jenkins-server --restart=always -p 8080:8080 dstubked/jenkins:latest

echo "* * * * Demo Setup Completed! * * * *"
