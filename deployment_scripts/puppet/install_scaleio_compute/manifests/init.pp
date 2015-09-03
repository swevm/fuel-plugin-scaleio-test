# ScaleIO Puppet Manifest for Compute Nodes

class install_scaleio_compute
{
  $nova_service = 'openstack-nova-compute'
  $sdc_package = 'EMC-ScaleIO-sdc'

  $nodes_hash = $fuel_settings['nodes']
  $primary_controller_nodes = filter_nodes($nodes_hash,'role','primary-controller')
  $controllers = concat($primary_controller_nodes, filter_nodes($nodes_hash,'role','controller'))
  $roles = node_roles($nodes_hash, $::fuel_settings['uid'])
  $controller_internal_addresses = nodes_to_hash($controllers,'name','internal_address')
  $controller_nodes = ipsort(values($controller_internal_addresses))

  $mdm_ip_1 = $controller_nodes[0]
  $mdm_ip_2 = $controller_nodes[1]

  #Create ScaleIO repo
  $scaleio_repo_content = "[scaleio]
name=Getty Images ScaleIO Packages
baseurl=${::fuel_settings['scaleio']['scaleio_repo']}
enabled=1
gpgcheck=0
priority=1
    "

  # file { '/etc/yum.repos.d/scaleio.repo':
  #   content => "$scaleio_repo_content",
  #   mode  => '644',
  #   owner => 'root',
  #   group => 'root',
  #   before => Exec['install_sdc'],
  #  }

  #Install ScaleIO SDC package  
  
  exec { "install_sdc":    
    command => "/bin/bash -c \"MDM_IP=${mdm_ip_1},${mdm_ip_2} yum install -y EMC-ScaleIO-sdc\"",        
    path => "/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/root/bin",
  }

  #Configure nova-compute
  ini_subsetting { 'nova-volume_driver':
    ensure  => present,
    path    => '/etc/nova/nova.conf',
    subsetting_separator => ',',
    section => 'libvirt',
    setting => 'volume_drivers',
    subsetting => 'scaleio=nova.virt.libvirt.scaleiolibvirtdriver.LibvirtScaleIOVolumeDriver',
    notify => Service[$nova_service],
  }

  file { 'scaleiolibvirtdriver.py':
    path  => '/usr/lib/python2.6/site-packages/nova/virt/libvirt/scaleiolibvirtdriver.py',
    source => 'puppet:///modules/install_scaleio_compute/scaleiolibvirtdriver.py',
    mode  => '644',
    owner => 'root',
    group => 'root',
    notify => Service[$nova_service],  
  }

  file { 'scaleio.filters':
    path  => '/usr/share/nova/rootwrap/scaleio.filters',
    source => 'puppet:///modules/install_scaleio_compute/scaleio.filters',
    mode  => '644',
    owner => 'root',
    group => 'root',
    notify => Service[$nova_service],
  }

  service { $nova_service:
    ensure => 'running',
  }
}

