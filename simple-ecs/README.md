# Simple ECS

A minimal ECS cluster using Terraform. It uses an EC2 auto scaling group on which to run the containers.

Main components of this Terraform file:

- VPC (including common resources like igw, subnets, ...): the VPC to deploy the EC2 instances and containers on.
- Application Load Balancer: The load balancer to allow public access to the containerized applications.
- Auto Scaling Group: The auto scaling group for provisioning the EC2 instances on which to run the containers.
- ECS Task Definition: The task definition for the sample containerized applications. Equivalent to Kubernetes Pod.
- ECS Cluster: Equivalent to Kubernetes Cluster.
- ECS Service: Equivalent to Kubernetes Deployment.
