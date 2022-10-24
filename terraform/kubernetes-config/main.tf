terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = ">= 2.4.0"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
      version = ">= 2.7.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.0.1"
    }
    dotenv = {
      source  = "jrhouston/dotenv"
      version = "~> 1.0"
    }
  }
}

data "digitalocean_kubernetes_cluster" "primary" {
  name = var.cluster_name
}

resource "local_file" "kubeconfig" {
  depends_on = [var.cluster_id]
  count      = var.write_kubeconfig ? 1 : 0
  content    = data.digitalocean_kubernetes_cluster.primary.kube_config[0].raw_config
  filename   = "${path.root}/kubeconfig"
}

provider "kubernetes" {
  host             = data.digitalocean_kubernetes_cluster.primary.endpoint
  token            = data.digitalocean_kubernetes_cluster.primary.kube_config[0].token
  cluster_ca_certificate = base64decode(
    data.digitalocean_kubernetes_cluster.primary.kube_config[0].cluster_ca_certificate
  )
}

provider "helm" {
  kubernetes {
    host  = data.digitalocean_kubernetes_cluster.primary.endpoint
    token = data.digitalocean_kubernetes_cluster.primary.kube_config[0].token
    cluster_ca_certificate = base64decode(
      data.digitalocean_kubernetes_cluster.primary.kube_config[0].cluster_ca_certificate
    )
  }
}

data "dotenv" "backend_secret" {
  # NOTE there must be a file called `dev.env` in the same directory as the .tf config
  filename = "../.env"
}

resource "kubernetes_secret" "backend_secret" {
  metadata {
    name = "backend"
  }

  data = data.dotenv.backend_secret.env
}

resource "kubernetes_namespace" "queplanta" {
  metadata {
    name = "queplanta"
  }
}

resource "helm_release" "postgres" {
  name       = "cloudnative-pg"
  namespace  = kubernetes_namespace.queplanta.metadata.0.name

  repository = "https://cloudnative-pg.github.io/charts"
  chart      = "cnpg-sandbox"

  # set {
  #   name  = "service.type"
  #   value = "LoadBalancer"
  # }
  # set {
  #   name  = "service.annotations.service\\.beta\\.kubernetes\\.io/do-loadbalancer-name"
  #   value = format("%s-nginx-ingress", var.cluster_name)
  # }
}

resource "kubernetes_deployment" "backend" {
  metadata {
    name = "backend"
    namespace= kubernetes_namespace.queplanta.metadata.0.name
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "backend"
      }
    }
    template {
      metadata {
        labels = {
          app  = "backend"
        }
      }
      spec {
        container {
          image = "queplanta/backend"
          name = "backend"
          command  = ["/bin/bash", "/usr/src/app/docker-entrypoint.sh"]
          env_from {
            secret_ref {
              name = kubernetes_secret.backend_secret.metadata.0.name
            }
          }

          resources {
            limits = {
              memory = "512M"
              cpu = "1"
            }
            requests = {
              memory = "256M"
              cpu = "50m"
            }
          }
        }
      }
    }
  }
}

# resource "kubernetes_service" "test" {
#   metadata {
#     name      = "test-service"
#     namespace = kubernetes_namespace.test.metadata.0.name
#   }
#   spec {
#     selector = {
#       app = kubernetes_deployment.test.metadata.0.name
#     }

#     port {
#       port = 5678
#     }
#   }
# }

resource "helm_release" "nginx_ingress" {
  name       = "nginx-ingress-controller"
  namespace  = kubernetes_namespace.queplanta.metadata.0.name

  repository = "https://charts.bitnami.com/bitnami"
  chart      = "nginx-ingress-controller"

  set {
    name  = "service.type"
    value = "LoadBalancer"
  }
  set {
    name  = "service.annotations.service\\.beta\\.kubernetes\\.io/do-loadbalancer-name"
    value = format("%s-nginx-ingress", var.cluster_name)
  }
}

resource "kubernetes_ingress_v1" "grafana_ingress" {
  wait_for_load_balancer = true

  metadata {
    name = "grafana-ingress"
    namespace  = kubernetes_namespace.queplanta.metadata.0.name
    annotations = {
      "kubernetes.io/ingress.class" = "nginx"
      "ingress.kubernetes.io/rewrite-target" = "/"
    }
  }

  spec {
    rule {
      http {
        path {
          backend {
            service {
              name = "cloudnative-pg-grafana"
              port {
                number = 80
              }
            }
          }

          path = "/"
        }
      }
    }
  }
}
