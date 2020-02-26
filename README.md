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
