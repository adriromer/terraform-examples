locals {
  name            = "eks-${var.enterprise}-${var.environment}"
  cluster_version = "1.27"
  instance_type   = "t3.large"
}

module "eks_dev" {
  source  = "terraform-aws-modules/eks/aws"
  version = "19.21.0"

  cluster_name                    = local.name
  cluster_version                 = local.cluster_version
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true
  cluster_ip_family               = "ipv4"
  # create_kms_key                   = false
  # attach_cluster_encryption_policy = false
  # cluster_encryption_config        = ""

  cluster_addons = {
    coredns = {
      preserve    = true
      most_recent = true

      timeouts = {
        create = "25m"
        delete = "10m"
      }

    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent   = true
      service_account_role_arn = "arn:aws:iam::238714979506:role/AmazonEKS_EBS_CSI_DriverRole"
      # service_account_role_arn = data.tfe_outputs.security_dev.values.ebs_csi_driver_role
    }
  }

  vpc_id                   = data.tfe_outputs.networking_dev.values.vpc_dev_info.vpc_id
  subnet_ids               = data.tfe_outputs.networking_dev.values.vpc_dev_info.private_subnets
  control_plane_subnet_ids = data.tfe_outputs.networking_dev.values.vpc_dev_info.private_subnets

  cluster_security_group_additional_rules = {
    ingress-directo-vpn = {
      description = "vpn"
      protocol    = "tcp"
      from_port   = 443
      to_port     = 443
      type        = "ingress"
      cidr_blocks = [data.tfe_outputs.networking_dev.values.vpc_dev_info.vpc_cidr_block]
    }
  }

  eks_managed_node_groups = {
    bottlerocket-amd64 = {
      name            = "bottlerocket-amd64"
      use_name_prefix = true
      subnet_ids      = data.tfe_outputs.networking_dev.values.vpc_dev_info.private_subnets
      min_size        = 1
      max_size        = 10
      desired_size    = 2

      use_custom_launch_template = false

      ami_type = "BOTTLEROCKET_x86_64"
      platform = "bottlerocket"
      ami_tid  = data.aws_ami.bottlerocket_ami.id

      instance_types = [local.instance_type]
      capacity_type  = "SPOT"

      enable_bootstrap_user_data = true

      labels = {
        environment = var.environment
      }

      update_config = {
        max_unavailable = 1
      }

      description             = "Bottlerocket ${local.name} node group"
      enable_monitoring       = false
      disable_api_termination = false

      disk_size = 150

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 100
            volume_type           = "gp3"
            iops                  = 3000
            throughput            = 150
            delete_on_termination = true
          }
        }
        xvdb = {
          device_name = "/dev/xvdb"
          ebs = {
            volume_size           = 200
            volume_type           = "gp3"
            iops                  = 3000
            throughput            = 150
            delete_on_termination = true
          }
        }
      }

      tags = {
        "Name" = "bottlerocket-${local.name}",
        "Arch" = "amd64"
      }
    }
  }


  manage_aws_auth_configmap = true

  #   aws_auth_roles = [
  #     {
  #       rolearn  = "arn:aws:iam::66666666666:role/role1"
  #       username = "role1"
  #       groups   = ["system:masters"]
  #     },
  #   ]

  aws_auth_users = [
    {
      userarn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/agustinl"
      username = "agustinl"
      groups   = ["system:masters"]
    },
  ]

  tags = merge(var.tags, {
    Name                                      = local.name
    "kubernetes.io/cluster/${local.name}"     = local.name
    "k8s.io/cluster-autoscaler/${local.name}" = "owned"
    "k8s.io/cluster-autoscaler/enabled"       = "true"
  })
}
