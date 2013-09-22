# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  config.vm.box = "quantal64"
  config.vm.box_url = "https://github.com/downloads/roderik/VagrantQuantal64Box/quantal64.box"

  # Forward jmeter's command port for shutdown.
  config.vm.network :forwarded_port, guest: 4445, host: 4445

  # Create a private network, which allows host-only access to the machine
  # using a specific IP.
  # config.vm.network :private_network, ip: "192.168.33.10"

  # Create a public network, which generally matched to bridged network.
  # Bridged networks make the machine appear as another physical device on
  # your network.
  # config.vm.network :public_network

  # jmeter-ec2.sh requires java installed when using REMTOE_HOSTS
  config.vm.provision :shell do |shell|
    shell.inline = "sudo apt-get update"
    shell.inline = "sudo apt-get -y install default-jre"
  end
end
