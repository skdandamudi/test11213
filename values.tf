locals {
  helm_values = [
    yamlencode({
      global = {
        image = merge(
          var.argocd_image_repository != "" ? { repository = var.argocd_image_repository } : {},
          var.argocd_image_tag != "" ? { tag = var.argocd_image_tag } : {}
        )
      }

      server = {
        replicas = var.argocd_server_replicas

        insecure = true

        pdb = {
          enabled      = true
          minAvailable = 1
        }

        topologySpreadConstraints = [
          {
            maxSkew            = 1
            topologyKey        = "kubernetes.io/hostname"
            whenUnsatisfiable  = "DoNotSchedule"
            labelSelector = {
              matchLabels = {
                "app.kubernetes.io/component" = "server"
              }
            }
          }
        ]

        service = {
          type = "LoadBalancer"
          annotations = {
            "service.beta.kubernetes.io/aws-load-balancer-scheme"    = "internal"
            "service.beta.kubernetes.io/aws-load-balancer-ssl-cert"  = var.acm_certificate_arn
            "service.beta.kubernetes.io/aws-load-balancer-ssl-ports" = "443"
          }
        }
      }

      repoServer = {
        replicas = 2
        pdb = {
          enabled      = true
          minAvailable = 1
        }
      }

      applicationSet = {
        replicas = 2
      }

      configs = {
        params = {
          "server.insecure" = true
        }
        cm = var.oidc_issuer_url != "" ? {
          url             = "https://argocd.${var.domain}"
          "oidc.config"   = yamlencode({
            name            = "SSO"
            issuer          = var.oidc_issuer_url
            clientID        = var.oidc_client_id
            clientSecret    = "$oidc.clientSecret"
            requestedScopes = ["openid", "profile", "email", "groups"]
          })
        } : {}
        secret = var.oidc_issuer_url != "" ? {
          extra = {
            "oidc.clientSecret" = var.oidc_client_secret
          }
        } : {}
        rbac = var.oidc_issuer_url != "" ? {
          "policy.csv" = <<-CSV
            g, devops-admins, role:admin
            g, devops-readonly, role:readonly
            p, role:deployer, applications, sync, */*, allow
            p, role:deployer, applications, get, */*, allow
            g, devops-deployers, role:deployer
          CSV
          "policy.default" = "role:readonly"
          scopes           = "[groups]"
        } : {}
        credentialTemplates = local.git_ssh_private_key != "" ? {
          private-repo = {
            url           = var.git_ssh_url_prefix
            sshPrivateKey = local.git_ssh_private_key
          }
        } : {}
        ssh = local.git_ssh_private_key != "" ? {
          knownHosts = <<-EOF
            github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
            github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
            gitlab.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAfuCHKVTjquxvt6CM6tdG4SLp1Btn/nOeHHE5UOzRdf
            gitlab.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBFSMqzJeV9rUzU4kWitGjeR4PWSa29SPqJ1fVkhtj3Hw9xjLVXVYrU9QlYWrOLXBpQ6KWjbjTDTdDkoohFzgbEY=
            bitbucket.org ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIazEu89wgQZ4bqs3d63QSMzYVa0MuJ2e2gKTKqu+UUO
            bitbucket.org ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBPIQmuzMBM9kzQtKvehupSTBftrMWxV/fLC/+bVqif9RqhJhec9GWmfXinPWKCmIjQVCMDy0HUMMbeezR2u04qc=
          EOF
        } : {}
      }
    })
  ]
}
