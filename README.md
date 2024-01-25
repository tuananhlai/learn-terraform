# Learn Terraform

This repository contains a collection of Terraform templates and configurations for deploying various AWS resources and services. Each subdirectory corresponds to a specific use case or AWS service. Below is an overview of each module:

## Module Descriptions:

- [elastic-wordpress](./elastic-wordpress): A highly-available WordPress application using Auto Scaling Group, EFS and AWS RDS.
- [multi-tiered-vpc](./multi-tiered-vpc): A simple VPC with multiple tiers of subnet.
- [private-s3-buckets](./private-s3-buckets): Multiple S3 buckets that can only be accessed within a VPC via a VPC gateway endpoint.
- [simple-alb](./simple-alb): A simple Application Load Balancer with 2 backing instances.
- [simple-asg](./simple-asg): A simple Auto Scaling Group.
- [simple-ec2](./simple-ec2): A simple EC2 instance.
- [simple-ec2-in-vpc](./simple-ec2-in-vpc): A simple EC2 instance deployed within a multi-tiered VPC. It uses the `multi-tiered-vpc` module from this repository.
- [simple-ec2-in-vpc-2](./simple-ec2-in-vpc-2): A simple EC2 instance deployed within a multi-tiered VPC. It uses `terraform-aws-module/vpc` to deploy the VPC resources.
- [simple-ec2-remote-state](./simple-ec2-remote-state): A simple EC2 instance, but the Terraform state is saved in S3 instead of the local filesystem.
- [simple-ec2-with-ebs-and-more](./simple-ec2-with-ebs-and-more): A simple EC2 instance with extra resources like EBS and IAM Instance Profile.
- [simple-ec2-with-efs](./simple-ec2-with-efs): A simple EC2 instance with a mounted EFS.
- [simple-s3-remote-state](./simple-s3-remote-state): A S3 bucket used to store Terraform remote state.
- [simple-transit-gw](./simple-transit-gw): Multiple VPCs connected via a Transit Gateway.
- [simple-vpc](./simple-vpc): A simple VPC.
- [simple-vpc-peering](./simple-vpc-peering): Multiple VPCs connected using VPC Peering.
- [simple-waf](./simple-waf): A simple Web Application Firewall attached to an Application Load Balancer with multiple rulesets.
- [strongswan-site2site-vpn](./strongswan-site2site-vpn): A site-to-site VPN between AWS and (simulated) On Premise network. The VPN connection is setup between a Transit Gateway and a Customer Gateway using strongSwan.
