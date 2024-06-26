# Running RDMA (remote direct memory access) GPU workloads on OKE using GPU Operator

Oracle Cloud Infrastructure Container Engine for Kubernetes (OKE) is a fully-managed, scalable, and highly available service that you can use to deploy your containerized applications to the cloud.

Please visit the [OKE documentation page](https://docs.oracle.com/en-us/iaas/Content/ContEng/Concepts/contengoverview.htm) for more information.

This guide has the instructions for deploying an OKE cluster using H100 & A100 bare metal nodes with RDMA connectivity using the [GPU Operator](https://github.com/NVIDIA/gpu-operator).

### What is NVIDIA GPU Operator?
Kubernetes provides access to special hardware resources such as NVIDIA GPUs, NICs, Infiniband adapters and other devices through the device plugin framework. However, configuring and managing nodes with these hardware resources requires configuration of multiple software components such as drivers, container runtimes or other libraries which are difficult and prone to errors. The NVIDIA GPU Operator uses the operator framework within Kubernetes to automate the management of all NVIDIA software components needed to provision GPU. These components include the NVIDIA drivers (to enable CUDA), Kubernetes device plugin for GPUs, the NVIDIA Container Runtime, automatic node labelling, DCGM based monitoring and others.

### Supported Operating Systems
For the A100 and H100 shapes (BM.GPU.H100.8, BM.GPU.A100-v2.8, BM.GPU4.8), Ubuntu 22.04 is supported.

### Required policies
The Terraform deployment template uses the [Self Managed Nodes](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengworkingwithselfmanagednodes.htm) functionality of OKE.

You must create the necessary OKE policies:

- [Policy Configuration for Cluster Creation and Deployment](https://docs.oracle.com/en-us/iaas/Content/ContEng/Concepts/contengpolicyconfig.htm)
- [Creating a Dynamic Group and a Policy for Self-Managed Nodes](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengdynamicgrouppolicyforselfmanagednodes.htm)

## Instructions for deploying an OKE cluster with GPUs and RDMA connectivity

The nodes pools require you to use an images provided by the Oracle HPC team. This image included the OFED drivers and necessary packages configured for RDMA.

Please reach out to your sales representative to get the images required for deploying this template.

### Deploy the cluster using the OCI Resource Manager stack
You can find the template in the [stack directory](./stack/).

The template will deploy a `bastion` instance and an `operator` instance. The `operator` instance will have access to the OKE cluster. You can connect to the `operator` instance via SSH with `ssh -J opc@<bastion IP> opc@<operator IP>`.

### Wait until you see all nodes in the cluster

```sh
kubectl get nodes

NAME           STATUS     ROLES    AGE     VERSION
10.0.103.73    Ready      <none>   2d23h   v1.25.6
10.0.127.206   Ready      node     2d3h    v1.25.6
10.0.127.32    Ready      node     2d3h    v1.25.6
10.0.83.93     Ready      <none>   2d23h   v1.25.6
10.0.96.81     Ready      node     2d23h   v1.25.6
```

### Get the latest Helm 3 version
```sh
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
```

### Add the Helm repo for GPU Operator
```sh
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update
```

### Deploy GPU Operator
```
helm install --wait \
  -n gpu-operator --create-namespace \
  gpu-operator nvidia/gpu-operator \
  --version v24.3.0 \
  --set driver.enabled=false \
  --set operator.defaultRuntime=crio \
  --set driver.rdma.enabled=true \
  --set driver.rdma.useHostMofed=true
```

Wait until all network operator pods are running with `kubectl get pods -n gpu-operator`.

### Deploy RDMA Shared Device plugin

```
kubectl apply -f https://raw.githubusercontent.com/OguzPastirmaci/oke-hpc-stack/hostnetwork/manifests/rdma-shared-device-configmap.yaml

kubectl apply -f https://raw.githubusercontent.com/Mellanox/k8s-rdma-shared-dev-plugin/master/deployment/k8s/base/daemonset.yaml
```

### Create the topology ConfigMap (this step is not needed when you're using NCCL version 2.20 and above)
This step creates a ConfigMap that can be used as the NCCL topology file when running your jobs that use NCCL as the backend.

You can find the topology files in the [topology directory](https://github.com/oracle-quickstart/oci-hpc-oke/tree/main/manifests/topology) in this repo. Please make sure you use the correct topology file based on your shape when creating the ConfigMap.

```
SHAPE=<your GPU shape>

curl -s -o ./topo.xml https://raw.githubusercontent.com/oracle-quickstart/oci-hpc-oke/main/manifests/topology/$SHAPE.xml

kubectl create configmap nccl-topology --from-file ./topo.xml
```

### Confirm that the GPUs and shared RDMA device is correctly exposed
You should see 8 GPUs and 1 RDMA shared device being reported as an allocatable resource in your GPU nodes.

```
kubectl get nodes -l 'node.kubernetes.io/instance-type in (BM.GPU.H100.8, BM.GPU.A100-v2.8, BM.GPU4.8, BM.GPU.B4.8)' --sort-by=.status.capacity."nvidia\.com/gpu" -o=custom-columns='NODE:metadata.name,GPUs:status.capacity.nvidia\.com/gpu,RDMA-Shared-Device:status.capacity.rdma/roce'

NODE           GPUs   RDMA-Shared-Device
10.140.30.89   8      1
10.140.31.32   8      1
```

### Optional - Deploy Volcano and run the NCCL test
Volcano is needed for running the optional NCCL test. It's not required for the regular operation of the cluster, you can remove it after you finish running the NCCL test.

#### Deploy Volcano
```sh
helm repo add volcano-sh https://volcano-sh.github.io/helm-charts
helm install volcano volcano-sh/volcano -n volcano-system --create-namespace --version 1.8.2

kubectl create serviceaccount -n default mpi-worker-view
kubectl create rolebinding default-view --namespace default --serviceaccount default:mpi-worker-view --clusterrole view
```

#### Run the NCCL test
> [!IMPORTANT]  
> The NCCL parameters are different between the H100 and A100 shapes. Please make sure that you are using the correct manifest.

##### H100
```
kubectl apply -f https://raw.githubusercontent.com/OguzPastirmaci/oke-hpc-stack/main/manifests/h100-nccl-test.yaml
```

##### A100
```
kubectl apply -f https://raw.githubusercontent.com/OguzPastirmaci/oke-hpc-stack/main/manifests/a100-nccl-test.yaml
```

The initial pull of the container will take long. Once the master pod `nccl-allreduce-job0-mpimaster-0` starts running, you can check it logs for the NCCL test result.

```sh
Defaulted container "mpimaster" out of: mpimaster, wait-for-workers (init)
Warning: Permanently added 'nccl-allreduce-job0-mpiworker-0.nccl-allreduce-job0' (ED25519) to the list of known hosts.
Warning: Permanently added 'nccl-allreduce-job0-mpiworker-1.nccl-allreduce-job0' (ED25519) to the list of known hosts.
# nThread 1 nGpus 1 minBytes 8 maxBytes 8589934592 step: 2(factor) warmup iters: 5 iters: 20 agg iters: 1 validation: 1 graph: 0
#
# Using devices
#  Rank  0 Group  0 Pid     43 on nccl-allreduce-job0-mpiworker-0 device  0 [0x0f] NVIDIA A100-SXM4-40GB
#  Rank  1 Group  0 Pid     44 on nccl-allreduce-job0-mpiworker-0 device  1 [0x15] NVIDIA A100-SXM4-40GB
#  Rank  2 Group  0 Pid     45 on nccl-allreduce-job0-mpiworker-0 device  2 [0x51] NVIDIA A100-SXM4-40GB
#  Rank  3 Group  0 Pid     46 on nccl-allreduce-job0-mpiworker-0 device  3 [0x54] NVIDIA A100-SXM4-40GB
#  Rank  4 Group  0 Pid     47 on nccl-allreduce-job0-mpiworker-0 device  4 [0x8d] NVIDIA A100-SXM4-40GB
#  Rank  5 Group  0 Pid     48 on nccl-allreduce-job0-mpiworker-0 device  5 [0x92] NVIDIA A100-SXM4-40GB
#  Rank  6 Group  0 Pid     49 on nccl-allreduce-job0-mpiworker-0 device  6 [0xd6] NVIDIA A100-SXM4-40GB
#  Rank  7 Group  0 Pid     50 on nccl-allreduce-job0-mpiworker-0 device  7 [0xda] NVIDIA A100-SXM4-40GB
#  Rank  8 Group  0 Pid     43 on nccl-allreduce-job0-mpiworker-1 device  0 [0x0f] NVIDIA A100-SXM4-40GB
#  Rank  9 Group  0 Pid     44 on nccl-allreduce-job0-mpiworker-1 device  1 [0x15] NVIDIA A100-SXM4-40GB
#  Rank 10 Group  0 Pid     45 on nccl-allreduce-job0-mpiworker-1 device  2 [0x51] NVIDIA A100-SXM4-40GB
#  Rank 11 Group  0 Pid     46 on nccl-allreduce-job0-mpiworker-1 device  3 [0x54] NVIDIA A100-SXM4-40GB
#  Rank 12 Group  0 Pid     47 on nccl-allreduce-job0-mpiworker-1 device  4 [0x8d] NVIDIA A100-SXM4-40GB
#  Rank 13 Group  0 Pid     48 on nccl-allreduce-job0-mpiworker-1 device  5 [0x92] NVIDIA A100-SXM4-40GB
#  Rank 14 Group  0 Pid     49 on nccl-allreduce-job0-mpiworker-1 device  6 [0xd6] NVIDIA A100-SXM4-40GB
#  Rank 15 Group  0 Pid     50 on nccl-allreduce-job0-mpiworker-1 device  7 [0xda] NVIDIA A100-SXM4-40GB
#
#                                                              out-of-place                       in-place
#       size         count      type   redop    root     time   algbw   busbw #wrong     time   algbw   busbw #wrong
#        (B)    (elements)                               (us)  (GB/s)  (GB/s)            (us)  (GB/s)  (GB/s)
           8             2     float     sum      -1    36.47    0.00    0.00      0    34.74    0.00    0.00      0
          16             4     float     sum      -1    38.86    0.00    0.00      0    35.65    0.00    0.00      0
          32             8     float     sum      -1    38.53    0.00    0.00      0    35.41    0.00    0.00      0
          64            16     float     sum      -1    39.25    0.00    0.00      0    37.05    0.00    0.00      0
         128            32     float     sum      -1    38.85    0.00    0.01      0    37.21    0.00    0.01      0
         256            64     float     sum      -1    40.68    0.01    0.01      0    38.52    0.01    0.01      0
         512           128     float     sum      -1    39.27    0.01    0.02      0    39.35    0.01    0.02      0
        1024           256     float     sum      -1    41.97    0.02    0.05      0    40.56    0.03    0.05      0
        2048           512     float     sum      -1    43.36    0.05    0.09      0    41.29    0.05    0.09      0
        4096          1024     float     sum      -1    44.54    0.09    0.17      0    43.36    0.09    0.18      0
        8192          2048     float     sum      -1    48.16    0.17    0.32      0    46.51    0.18    0.33      0
       16384          4096     float     sum      -1    49.40    0.33    0.62      0    48.00    0.34    0.64      0
       32768          8192     float     sum      -1    49.66    0.66    1.24      0    49.17    0.67    1.25      0
       65536         16384     float     sum      -1    51.69    1.27    2.38      0    50.09    1.31    2.45      0
      131072         32768     float     sum      -1    54.86    2.39    4.48      0    53.31    2.46    4.61      0
      262144         65536     float     sum      -1    67.95    3.86    7.23      0    65.81    3.98    7.47      0
      524288        131072     float     sum      -1    73.94    7.09   13.29      0    72.87    7.20   13.49      0
     1048576        262144     float     sum      -1    85.58   12.25   22.97      0    84.50   12.41   23.27      0
     2097152        524288     float     sum      -1    99.19   21.14   39.64      0    100.1   20.94   39.27      0
     4194304       1048576     float     sum      -1    127.0   33.03   61.93      0    127.8   32.81   61.52      0
     8388608       2097152     float     sum      -1    174.3   48.13   90.25      0    168.4   49.80   93.38      0
    16777216       4194304     float     sum      -1    282.7   59.35  111.29      0    265.9   63.11  118.32      0
    33554432       8388608     float     sum      -1    452.3   74.18  139.08      0    452.0   74.24  139.19      0
    67108864      16777216     float     sum      -1    821.7   81.67  153.13      0    812.7   82.57  154.83      0
   134217728      33554432     float     sum      -1   1542.0   87.04  163.20      0   1546.1   86.81  162.76      0
   268435456      67108864     float     sum      -1   3042.7   88.22  165.42      0   3065.9   87.55  164.16      0
   536870912     134217728     float     sum      -1   6436.0   83.42  156.41      0   6070.5   88.44  165.82      0
  1073741824     268435456     float     sum      -1   9187.8  116.87  219.12      0   9073.4  118.34  221.89      0
  2147483648     536870912     float     sum      -1    18289  117.42  220.16      0    17557  122.31  229.34      0
  4294967296    1073741824     float     sum      -1    34176  125.67  235.63      0    34417  124.79  233.98      0
  8589934592    2147483648     float     sum      -1    67689  126.90  237.94      0    67811  126.68  237.52      0
# Out of bounds values : 0 OK
# Avg bus bandwidth    : 66.4834
#
```

## FAQ
#### Are there any features that are not supported when using self-managed nodes?
Yes, some features and capabilities are not available, or not yet available, when using self-managed nodes. Please see [this link](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengworkingwithselfmanagednodes.htm) for a list of features and capabilities that are not available for self-managed nodes.

#### I don't see my GPU nodes in the OKE page in the console under worker pools
This is expected. Currently, only the worker pools with the `node-pool` mode are listed. Self-managed nodes (`cluster-network` and `instance-pool` modes in worker pools) are created by you and joined to the OKe cluster, rather than OKE has created for you.

#### Can I use Multi-Instance GPU (MIG)?
Yes, you can configure GPU Operator with MIG. Please see the instructions [here](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/gpu-operator-mig.html).

 #### I'm getting the "400-InvalidParameter, Shape <GPU BM shape> is incompatible with image" error
Please follow the instructions [here](https://docs.oracle.com/en-us/iaas/Content/Compute/Tasks/configuringimagecapabilities.htm#configuringimagecapabilities_topic-using_the_console) to add the capability of the shape that you are getting the error to your imported image.
