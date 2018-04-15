#!/bin/bash
set -e

if [ "$SCALEWAY_TOKEN" == "" ]; then
	>&2 echo "The environment variable SCALEWAY_TOKEN is required"
	exit 1
fi

if [ "$SCALEWAY_ORGANIZATION" == "" ]; then
	>&2 echo "The environment variable SCALEWAY_ORGANIZATION is required"
	exit 1
fi

SCALEWAY_REGIONS=${SCALEWAY_REGIONS:-par1 ams1}
SOURCE_DIR=$PWD
TMP_DIR=$TMPDIR/image-alpine

apply_terraform () {
	export SCALEWAY_REGION=$1

	rm -Rf $TMP_DIR
	mkdir -p $TMP_DIR
	cd $SOURCE_DIR
	tar -zcf $TMP_DIR/source.tar.gz ./
	cd $TMP_DIR

	cat <<-EOF >> ./task.tf
		# Generated by ./provision.sh
		terraform {
			required_version = ">= 0.11.0"
		}

		resource "tls_private_key" "ssh" {algorithm   = "RSA"}

		locals {
			ssh_key_tmp = "\${replace(tls_private_key.ssh.public_key_openssh, "\n", " ")} terraform"
			ssh_key = "\${replace(local.ssh_key_tmp, " ", "_")}"
			public_key = "\${tls_private_key.ssh.public_key_pem}"
			private_key = "\${tls_private_key.ssh.private_key_pem}"
		}

		data "scaleway_image" "builder" {
			architecture = "x86_64"
			name         = "Image Builder"
		}

		resource "scaleway_server" "server" {
			name  = "image-alpine-builder"
			image = "\${data.scaleway_image.builder.id}"
			type  = "VC1S"
			dynamic_ip_required = true
			tags  = ["AUTHORIZED_KEY=\${local.ssh_key}"]

			connection {
				type = "ssh"
				user = "root"
				port = "22"
				private_key = "\${local.private_key}"
			}

			provisioner "file" {
				source      = "./source.tar.gz"
				destination = "/image-alpine.tar.gz"
			}

			provisioner "remote-exec" {
				inline = ["mkdir /image-alpine && tar xzf /image-alpine.tar.gz -C /image-alpine"]
			}

			provisioner "file" {
				content      = "\${local.private_key}"
				destination = "/root/.ssh/id_rsa"
			}

			provisioner "file" {
				content      = "\${local.public_key}"
				destination = "/root/.ssh/id_rsa.pub"
			}

			provisioner "remote-exec" {
				inline = [
					"apt-get update",
					"DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::='--force-confnew' install -y docker-engine jq",
					"wget 'https://github.com/scaleway/scaleway-cli/releases/download/v1.14/scw-linux-amd64' -O /usr/bin/scw && chmod +x /usr/bin/scw",
					"scw login --token $SCALEWAY_TOKEN --organization $SCALEWAY_ORGANIZATION --skip-ssh-key",
					"git clone https://github.com/scaleway/image-tools && cd image-tools && git checkout a707ed70599803563d4bf984d4e8a70297ce3737",
					"make IMAGE_DIR=/image-alpine REGION=$SCALEWAY_REGION scaleway_image"
				]
			}
		}
	EOF

	terraform init > /dev/null
	terraform apply -auto-approve
	terraform destroy -force
}

for region in $SCALEWAY_REGIONS; do
	echo
	echo deploy $region
	echo ----------------
	apply_terraform $region
done
