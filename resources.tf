# ========================================== #
# Images
# ========================================== #

resource "docker_image" "db" {
  name         = "chukmunnlee/bgg-database:${var.database_version}"
  keep_locally = false
}

resource "docker_image" "app" {
  name         = "chukmunnlee/bgg-backend:${var.backend_instance_version}"
  keep_locally = false
}

# ========================================== #
# Network
# ========================================== #

resource "docker_network" "net" {
    name = "${var.namespace}-net"
}

# ========================================== #
# Volumes
# ========================================== #

resource "docker_volume" "db" {
  name = "${var.namespace}-database"
}

# ========================================== #
# Docker Containers
# ========================================== #

resource "docker_container" "db" {
    image = docker_image.db.image_id
    name  = "${var.namespace}-database"

    volumes {
        container_path  = "/var/lib/mysql"
        read_only       = false
        volume_name     = docker_volume.db.name
    }

    networks_advanced {
        name = docker_network.net.id
    }

    ports {
        internal = 3306
    }
}

resource "docker_container" "app" {
    count = var.backend_instance_count
    image = docker_image.app.image_id
    name  = "${var.namespace}-backend-${count.index}"
    env   = [
        "${upper(var.namespace)}_DB_USER=root",
        "${upper(var.namespace)}_DB_PASSWORD=changeit",
        "${upper(var.namespace)}_DB_HOST=${docker_container.app[*].name}"
    ]

    networks_advanced {
        name = docker_network.net.id
    }

    ports {
        internal = 3000
    }
}

# ========================================== #
# Digital Ocean
# ========================================== #

resource "local_file" "nginx-conf" {
    filename    = "nginx.conf"
    content     = templatefile("sample.nginx.conf.tfpl", {
        docker_host = var.docker_host,
        ports       = docker_container.app[*].ports[0].external
    })
}

data "digitalocean_ssh_key" "web" {
    name = var.do_ssh_key
}

resource "digitalocean_droplet" "web" {
    image  = var.do_image
    name   = "${var.namespace}-web"
    region = var.do_region
    size   = var.do_size
    ssh_keys = [
        data.digitalocean_ssh_key.web.id
    ]

    connection {
        type = "ssh"
        user = "root"
        private_key = file(var.ssh_private_key)
        host = self.ipv4_address
    }

    provisioner "remote-exec" {
        inline  = [
            "apt update -y",
            "apt upgrade -y",
            "apt install nginx -y",
        ]
    }

    provisioner "file" {
        source      = local_file.nginx-conf.filename
        destination = "/etc/nginx/nginx.conf"
    }

    provisioner "remote-exec" {
        inline  = [
            "systemctl restart nginx",
            "systemctl enable nginx",
        ]
    }
}

resource "local_file" "root_at_web" {
    filename        = "root@${digitalocean_droplet.web.ipv4_address}"
    content         = ""
    file_permission = "0444"
}

output web_ip {
    value = digitalocean_droplet.web.ipv4_address
}


output app_ports {
    value = docker_container.app[*].ports[0].external
}
