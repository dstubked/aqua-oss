# Aqua Opensource
A hands on guided lesson walking through how to use the Aqua open source tools Trivy, Kube-Bench and Kube-hunter.

<img src="https://github.com/aquasecurity/trivy/blob/master/imgs/logo.png" height="150" align="left">
<img src="https://github.com/aquasecurity/kube-bench/raw/master/images/kube-bench.png" height="150" align="left">
<img src="https://github.com/aquasecurity/kube-hunter/blob/master/kube-hunter.png" height="150">


## Part 0
### Prerequisites
Have a simple kubernetes cluster up and running using Vagrant by following the instructions below.
Ensure there is internet connectivity from the lab Kubernetes environment.

### Prep the environment.
Install Vagrant 2.2.7 with the relevant packages for your supported OS: https://www.vagrantup.com/downloads.html

### Install lab environment
```
git clone https://github.com/dstubked/aqua-oss.git
cd aqua-oss
vagrant up
```

### Check VMs are up
```
vagrant status
Current machine states:

kmaster                   running (virtualbox)
kworker1                  running (virtualbox)
```

#### Check docker is installed and make sure there is internet connectivity
```
On master:
vagrant ssh kmaster
docker -v (should return docker version)
curl ifconfig.co (should return your public IP)

On worker:
vagrant ssh kworker1
docker -v (should return docker version)
curl ifconfig.co (should return your public IP)
```
## Part 1 - Trivy (https://github.com/aquasecurity/trivy)
<img src="https://github.com/aquasecurity/trivy/blob/master/imgs/logo.png" height="150">

### Installing Trivy
```
sudo apt-get -y install wget apt-transport-https gnupg lsb-release
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -
echo deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main | sudo tee -a /etc/apt/sources.list.d/trivy.list
sudo apt-get update
sudo apt-get -y install trivy
```
### NOTE: You might need to run the above twice if one of the apt-get does something unexpected.

### Using Trivy
##### Example.
```
trivy -h
```

#### Note some key paramters are -s to filter on severity and --ignore-unfixed to eliminate reporting any vulnerabilities that do not currently have fixes available

### Let's play with Trivy.   As an experiment let's take the advice of a recent 2019 article about choosing the best base image for a python application.  
https://pythonspeed.com/articles/base-image-python-docker-images/
### It recommends NOT using alpine but instead using ubuntu:18.04 or centos:7.6.1810 or debian:10 but let's try debian:10.2-slim to reduce result.  Which is the most secure?

#### First let's get a summary
```
trivy ubuntu:18.04 | grep Total
```
#### Let's look at the total list now 
```
trivy ubuntu:18.04 
```
#### Now let's try filtering on just CRITICAL vulnerabilities using the -s option total
```
trivy -s CRITICAL --ignore-unfixed ubuntu:18.04
```
### Try these steps quickly again using the centos:7.6.1810 or debian:10.2-slim in place of ubuntu:18.04.  I'll past the commands below to help
```
trivy centos:7.6.1810 | grep Total
```
```
trivy debian:10.2-slim | grep Total
```

### Which base image would you choose at a glance?

### Let's take a quick look at the latest alpine base image to compare
```
trivy alpine:3.11
```
### or perhaps a dedicate python image based on alpine made by João Ferreira Loff (https://github.com/jfloff/alpine-python)

```
trivy jfloff/alpine-python:3.8-slim
```

##### Notes:
Be specific on tags!!!   
Using the latest tag or non-specific tags can mean trivy could produce misleading results based on local caching of the image.

## Part 2 Kube-bench (remote) (https://github.com/aquasecurity/kube-bench)

<img src="https://github.com/aquasecurity/kube-bench/raw/master/images/kube-bench.png" height="150">

### Install kube-bench by cloning the git repo
```
git clone https://github.com/aquasecurity/kube-bench.git
```

#### Lets run kube-bench now directly as a pod in the cluster
```
cd kube-bench
kubectl apply -f job.yaml
```

#### View the kube-bench results
```
kubectl get pods
Look for kube-bench job name..
kubectl logs pod_name
```

## Part 3 Kube-hunter (remote) (https://github.com/aquasecurity/kube-hunter)

<img src="https://github.com/aquasecurity/kube-hunter/blob/master/kube-hunter.png" height="150">

### Install kube-hunter by cloning the git repo
```
git clone https://github.com/aquasecurity/kube-hunter.git
```

##### CHANGE the job’s metadata: name: from “kube-hunter” to something unique to you “$USER-kube-hunter” to avoid collisions
```
cd kube-hunter
vim job.yaml
```
### Also in the job.yaml we will file make a few changes
```
metadata:
  name: sg-1971-kube-hunter
# ADD a new parameter by CHANGING
        args: ["--pod"]
# to
        args: ["--pod”,”--quick”]
```

### You can do all this quickly via running a short command
```
cat job.yaml | sed 's/\["--pod"\]/\["--pod","--quick"\]/' | sed "s/name: kube-hunter/name: $USER-kubehunter/" > job2.yaml
```

#### NOTE: the --quick argument limits the network interface scanning.   It can turn a 45 min scan into seconds. Better for demos but not for security.
```
kubectl create -f ./job2.yaml
kubectl describe job “your-job-name”
kubectl logs “pod name” > myresultspassive.txt

cat myresultspassive.txt
```

## Part 3b
### First delete the old job
```
kubectl delete -f job2.yaml
```
### In the job.yaml file we will make one more change
```
# ADD a new parameter by CHANGING
        args: ["--pod"]
# to
        args: ["--pod”,”--quick”, “--active”]
```
### You can do all this quickly via running a short command
```
cat job.yaml | sed 's/\["--pod"\]/\["--pod","--quick","--active"\]/' | sed "s/name: kube-hunter/name: $USER-3-kubehunter/" > job3.yaml
```

#### NOTE: the --active argument extends the test to use finding to test for specific exploits. Better for security. Most effective run within the cluster.
### Let's try it again
```
kubectl create -f ./job3.yaml
kubectl describe job “your-job-name”
kubectl logs “pod name” > myresultsactive.txt

cat myresultsactive.txt

diff myresultsactive.txt myresultspassive.txt
```

#### Check the differences between the two results
