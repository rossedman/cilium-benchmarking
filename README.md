# Benchmarks

This document aims to benchmark the different configuration options with Cilium as well as how they were created. 

---

# 1. Setup

## 1.1 Policy Creation

I first installed a `CiliumeOperatorAccess` policy to be used in the account. This then is mapped to a role when using `eksctl`. Later, when installing Cilium, this role ARN is passed to the operator.

```
aws iam create-policy \
    --policy-name CiliumOperatorAccess \
    --policy-document file://config/cilium-policy.json
```

## 1.2 Cluster Creation

Next I created a cluster

```
eksctl create -f cluster.yaml
```

## 1.3 kubenetbench Install

I then installed `kubenetbench`

```
git clone git@github.com:cilium/kubenetbench.git
cd kubenetbench && make install
```

This was installed in repo to make it easier to use because some of the scripts and conventions are strange from the upstream code used

```
cp $(which kubenetbench) kubenetbench
```

---

# 2. Tests

Each test runs a single `stream` or `rr` set for a specific scenario. I have chosen `m5n.8xlarge` instances because they do not have burstable networking and have a steady 25gb assigned to them. I have also set the scripts to use 32 size bursts to match the vCPUs that AWS provides for these instances. Testing against a 100gb card was 1) really expensive and 2) isn't the type of instance we would normally use. 

These are the test cases I'm currently trying to cover:

- [ ] Test host to host in a cluster
- [ ] Test VPC CNI in a cluster
- [ ] Test VPC CNI + Cilium CNI Chaining
- [ ] Test Cilium with ENI defaults
- [ ] Test Cilium with ENI and kube-proxyless
- [ ] Test Cilium with ENI, kube-proxyless and no conntrack
- [ ] Test Cilium with overlay networking
- [ ] Test Cilium with overlay networking and kube-proxyless
- [ ] Test Cilium with overlay networking, kube-proxyless and no conntrack 

## 2.1 Test 01: Host To Host

This uses host level networking to bypass the extra container networking overhead. This should give us results about how the host performs as a baseline:

```
./knb-run.sh --tcp_rr_host --nloops 5 host_tcp_rr
./knb-run.sh --tcp_stream_host --nloops 5 host_tcp_stream
```

## VPC CNI

```
./knb-run.sh --tcp_rr --nloops 5 vpc_cni_tcp_rr
./knb-run.sh --tcp_stream --nloops 5 vpc_cni_tcp_stream
```

## Cilium (CNI Chaining)

Ensure that you have `aws-vpc-cni` running and `kube-proxy` 

```
eksctl create addon --name kube-proxy --cluster eksctl-sandbox-1 --force
eksctl create addon --name vpc-cni --cluster eksctl-sandbox-1 --force
```

Then install Cilium 

```
helm install cilium cilium/cilium \
    --version 1.10.5 \
    --namespace kube-system \
    -f config/cilium-chaining.yaml
```

Once deployed, restart all pods

```
kubectl delete pods --all --namespace kube-system
```

Then run tests

```
./knb-run.sh --tcp_rr --nloops 5 cilium_chain_tcp_rr
./knb-run.sh --tcp_stream --nloops 5 cilium_chain_tcp_stream
```

## Cilium (ENI)

First remove `aws-vpc-cni` and setup `cilium`.

```sh
kubectl delete -n kube-system ds aws-node
helm install cilium cilium/cilium \
    --version 1.10.5 \
    --namespace kube-system \
    -f config/cilium-eni.yaml
```

Validate the installation

```sh
cilium status
cilium connectivity test
```

Then run tests

```sh
./knb-run.sh --tcp_rr --nloops 5 cilium_eni_tcp_rr
./knb-run.sh --tcp_stream --nloops 5 cilium_eni_tcp_stream
```

## Cilium (ENI) Kube Proxyless

First, remove `kube-proxy` and setup `cilium` without `kube-proxy`

```sh
kubectl delete -n kube-system ds kube-proxy
helm upgrade cilium cilium/cilium \
    --version 1.10.5 \
    --namespace kube-system \
    -f config/cilium-eni-kube-proxyless.yaml \
    --set k8sServiceHost=$(kubectl get ep kubernetes -o jsonpath='{$.subsets[0].addresses[0].ip}')
```

Validate the installation

```sh
cilium status
cilium connectivity test
```

Then run tests

```sh
./knb-run.sh --tcp_rr --nloops 5 cilium_eni_kp_tcp_rr
./knb-run.sh --tcp_stream --nloops 5 cilium_eni_kp_tcp_stream
```

## Cilium (ENI) Tuned 

```sh
helm upgrade cilium cilium/cilium \
    --version 1.10.5 \
    --namespace kube-system \
    -f config/cilium-eni-tuned.yaml \
    --set k8sServiceHost=$(kubectl get ep kubernetes -o jsonpath='{$.subsets[0].addresses[0].ip}')
```

Validate the installation

```sh
cilium status
cilium connectivity test
```

Then run tests

```sh
./knb-run.sh --tcp_rr --nloops 5 cilium_eni_tuned_tcp_rr
./knb-run.sh --tcp_stream --nloops 5 cilium_eni_tuned_tcp_stream
```

## Cilium (Overlay)

```sh
helm delete cilium -n kube-system
helm install cilium cilium/cilium \
    --version 1.10.5 \
    --namespace kube-system \
    -f config/cilium-overlay.yaml
```

Validate the installation

```sh
cilium status
cilium connectivity test
```

Then run tests

```sh
./knb-run.sh --tcp_rr --nloops 5 cilium_overlay_tcp_rr
./knb-run.sh --tcp_stream --nloops 5 cilium_overlay_tcp_stream
```

---

# 3. Reference

## 3.1 Resetting A Cluster

This resets an EKS cluster back to its original configuration

```
helm delete cilium -n kube-sytem
eksctl create addon --name kube-proxy --cluster eksctl-sandbox-1 --force
eksctl create addon --name vpc-cni --cluster eksctl-sandbox-1 --force
```

## 3.2 Articles

Here are tools and reference articles I found helpful when researching this:

**Tools**

- [kubestone](https://kubestone.io/en/latest/) - benchmarking tool for Kubernetes
- [k8s-bench-suite](https://github.com/InfraBuilder/k8s-bench-suite) - Simple script based benchmarking tool
- [cni-benchmarks](https://github.com/jessfraz/cni-benchmarks) - Simple benchmarking program from jessfraz.
- [cilium-perf-networking](https://github.com/cilium/cilium-perf-networking) - Performance benchmark playbooks from cilium.
- [kubenetbench](https://github.com/cilium/kubenetbench) - Tool provided by cilium for benchmarking
- [PerfKitBenchmarker](https://github.com/GoogleCloudPlatform/PerfKitBenchmarker) - A google project for benchmarking

**Articles**

- [CNI Benchmark: Understanding Cilium Network Performance](https://cilium.io/blog/2021/05/11/cni-benchmark)
- [Benchmark results of Kubernetes network plugins](https://itnext.io/benchmark-results-of-kubernetes-network-plugins-cni-over-10gbit-s-network-updated-august-2020-6e1b757b9e49)
- [Performance Benchmark Analysis Of Istio And Linkerd](https://kinvolk.io/blog/2019/05/performance-benchmark-analysis-of-istio-and-linkerd/)
- [Benchmarking Linkerd And Istio](https://linkerd.io/2021/05/27/linkerd-vs-istio-benchmarks/)
- [Using Netperf And Ping To Measure Network Latency](https://cloud.google.com/blog/products/networking/using-netperf-and-ping-to-measure-network-latency)
