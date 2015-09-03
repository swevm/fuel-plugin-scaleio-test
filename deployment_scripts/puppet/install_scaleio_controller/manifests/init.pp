class install_scaleio_controller
{
  $mdm_package = 'EMC-ScaleIO-mdm'
  $sdc_package = 'EMC-ScaleIO-sdc'
  $tb_package = 'EMC-ScaleIO-tb'

  class { 'cluster::haproxy_ocf':
    primary_controller => $primary_controller
  }


  Haproxy::Service        { use_include => true }
  Haproxy::Balancermember { use_include => true }

  Openstack::Ha::Haproxy_service {
    server_names        => filter_hash($::controllers, 'name'),
    ipaddresses         => filter_hash($::controllers, 'internal_address'),
    public_virtual_ip   => $::fuel_settings['public_vip'],
    internal_virtual_ip => $::fuel_settings['management_vip'],
  }

  openstack::ha::haproxy_service { 'scaleio-gateway':
    order                  => 201,
    listen_port            => 443,
    balancermember_port    => 443,
    define_backups         => true,
    before_start           => true,
    public                 => true,
    haproxy_config_options => {
      'balance'        => 'roundrobin',
      'option'         => ['httplog'],
    },
    balancermember_options => 'check',
  }

  # 1. Create ScaleIO repo
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
  #   before => File['cinder_scaleio.config'],
  # }

  # 2. Check and install MDM if needed
  $nodes_hash = $fuel_settings['nodes']
  $controllers = concat(filter_nodes($nodes_hash,'role','primary-controller'), filter_nodes($nodes_hash,'role','controller'))
  $roles = node_roles($nodes_hash, $::fuel_settings['uid'])
  $controller_internal_addresses = nodes_to_hash($controllers,'name','internal_address')
  $controller_nodes = ipsort(values($controller_internal_addresses))
  $storage_pools = ["${::fuel_settings['scaleio']['storage_pool_1']}","${::fuel_settings['scaleio']['storage_pool_2']}"]
  $scaleio_nodes = filter_nodes($nodes_hash,'role','scaleio')
  $scaleio_ips = nodes_to_hash($scaleio_nodes,'name','internal_address')
  $sclaeio_ips_values = values($scaleio_ips)
  $scaleio_ips_keys = keys($scaleio_ips)
  $sds_ip_devices = get_sds_device_pairs($sclaeio_ips_values,$::fuel_settings['scaleio']['drive_list_2'])
  $sds_name_fs = get_fault_set($scaleio_ips_keys)
  $services = [ 'openstack-cinder-volume', 'openstack-cinder-api', 'openstack-cinder-scheduler', 'openstack-nova-scheduler']
  $fault_sets = split("${::fuel_settings['scaleio']['fault_sets']}",',')

  $mdm_ip_1 = $controller_nodes[0]
  $mdm_ip_2 = $controller_nodes[1]
  $tb_ip = $controller_nodes[2]

  define create_fault_sets {
    exec { $title:
      command => "/bin/bash -c \" /bin/scli --login --username admin --password Scaleio123 >> /root/scaleio.log;\
        /bin/scli --add_fault_set --protection_domain_name ${::fuel_settings['scaleio']['protection_domain']} --fault_set_name ${name} >> /root/scaleio.log\"",
      path => '/usr/bin:/usr/sbin:/bin:/usr/local/bin',
      unless => "/bin/scli --query_all_fault_sets --protection_domain_name ${::fuel_settings['scaleio']['protection_domain']} | grep -c ${name}", 
    }
  }

  define modify_spare_policy {
    exec { $title:
      command => "/bin/bash -c \"/bin/scli --login --username admin --password Scaleio123 >> /root/scaleio.log;\
        /bin/scli --add_storage_pool --protection_domain_name ${::fuel_settings['scaleio']['protection_domain']} --storage_pool_name ${name} >> /root/scaleio.log;\
        /bin/scli --modify_spare_policy --protection_domain_name ${::fuel_settings['scaleio']['protection_domain']} --storage_pool_name ${name} --spare_percentage 10 --i_am_sure >> /root/scaleio.log\"",
      path => '/usr/bin:/usr/sbin:/bin:/usr/local/bin',
    }
  }

  define add_sds ( $scaleio_ips, $mdm_ip, $fs_name ) {
    $ip = $scaleio_ips[$name]
    $fs = $fs_name[$name]
    exec { "${name}_add_sds":
      command => "/bin/bash -c \"/bin/scli --login --username admin --password Scaleio123 >> /root/scaleio.log;\
        /bin/scli --add_sds --sds_ip $ip --protection_domain_name ${::fuel_settings['scaleio']['protection_domain']} --storage_pool_name ${::fuel_settings['scaleio']['storage_pool_1']} --sds_name $name --fault_set_name $fs --device_path ${::fuel_settings['scaleio']['drive_list_1']} --mdm_ip $mdm_ip >> /root/scaleio.log\"",
      path => '/usr/bin:/usr/sbin:/bin:/usr/local/bin',
      unless => "/bin/scli --query_all_sds | grep -c -e '${name}\\s'", 
    }
  }

  define add_drive_to_pool ( 
    $pool,
  ) {
    $ip_device = split($name,'_')
    exec { "add_${name}":
      command => "/bin/bash -c \"/bin/scli --login --username admin --password Scaleio123 >> /root/scaleio.log;\
        /bin/scli --add_sds_device --sds_ip ${ip_device[0]} --device_path ${ip_device[1]} --protection_domain_name ${::fuel_settings['scaleio']['protection_domain']} --storage_pool_name ${pool}  >> /root/scaleio.log\"",
      unless => "/bin/scli --query_sds --sds_ip ${ip_device[0]} |grep -c \"${ip_device[1]}\"",
      path => '/usr/bin:/usr/sbin:/bin:/usr/local/bin',
    }
  }

  define install_gateway {

    file { '/etc/yum.repos.d/CentOS-Base.repo':
      ensure => present,
      content => template('install_scaleio_controller/CentOS-Base.repo'),
    } ->

    file { '/etc/yum.repos.d/epel.repo':
      ensure => present,
      content => template('install_scaleio_controller/epel.repo'),
    } ->

    package {'java-1.7.0-openjdk-devel.x86_64':
      ensure => present,
    } ->

    exec { 'install_gateway':
      command      => "/bin/bash -c \"GATEWAY_ADMIN_PASSWORD=Scaleio123 yum install -y EMC-ScaleIO-gateway\"",
      path        => '/usr/bin:/usr/sbin:/bin:/usr/local/bin',
    } ->

    file { 'gatewayUser.properties':
      path => '/opt/emc/scaleio/gateway/webapps/ROOT/WEB-INF/classes/gatewayUser.properties',
      ensure => file,
      content => template('install_scaleio_controller/gatewayUser.properties.erb'),
    } ~>

    service { 'scaleio-gateway':
      enable      => true,
      ensure      => running,
    }
  }

  if 'primary-controller' in $roles{

     package { $mdm_package:
      ensure => installed,
      before => Install_gateway['installing_gateway'],
    } 

    install_gateway { 'installing_gateway':
      before => Exec['init_primary_mdm'],
    } 

    exec { 'init_primary_mdm':
      command => "/bin/bash -c \"/bin/scli --add_primary_mdm --primary_mdm_ip $mdm_ip_1 --accept_license >> /root/scaleio.log;\"",
      path => '/usr/bin:/usr/sbin:/bin:/usr/local/bin',
      unless => ["/bin/scli --login --username admin --password Scaleio123 > /dev/null", "/bin/scli --query_protection_domain --protection_domain_name ${::fuel_settings['scaleio']['protection_domain']} | grep -c ${::fuel_settings['scaleio']['protection_domain']}"],
      tries => 10,
      try_sleep => 1,
    } ->

    exec { 'create_cluster':
      command => "/bin/bash -c \"/bin/scli --login --username admin --password admin >> /root/scaleio.log;\
        /bin/sleep 1;\
        /bin/scli --set_password --old_password admin --new_password Scaleio123 >> /root/scaleio.log;\
        /bin/sleep 1;\
        /bin/scli --login --username admin --password Scaleio123 >> /root/scaleio.log;\
        /bin/sleep 1;\
        /bin/scli --add_secondary_mdm --secondary_mdm_ip $mdm_ip_2 >> /root/scaleio.log;\
        /bin/sleep 1;\
        /bin/scli --add_tb --tb_ip $tb_ip >> /root/scaleio.log;\
        /bin/sleep 1;\
        /bin/scli --switch_to_cluster_mode >> /root/scaleio.log;\
        /bin/sleep 1;\
        /bin/scli --add_protection_domain --protection_domain_name ${::fuel_settings['scaleio']['protection_domain']} >> /root/scaleio.log\"",
      path => '/usr/bin:/usr/sbin:/bin:/usr/local/bin',
      unless => ["/bin/scli --login --username admin --password Scaleio123 > /dev/null", "/bin/scli --query_protection_domain --protection_domain_name ${::fuel_settings['scaleio']['protection_domain']} | grep -c ${::fuel_settings['scaleio']['protection_domain']}"],
      before => Create_fault_sets[$fault_sets],
    }

    create_fault_sets { $fault_sets:
      before => Modify_spare_policy[$storage_pools],
    }
    modify_spare_policy { $storage_pools:
      before => Add_sds[$scaleio_ips_keys],
    }
    add_sds { $scaleio_ips_keys:
      scaleio_ips => $scaleio_ips,
      mdm_ip => $mdm_ip_1,
      fs_name => $sds_name_fs,
    } ->
    add_drive_to_pool { $sds_ip_devices:
      pool => $::fuel_settings['scaleio']['storage_pool_2'],
    }
  } else {
    if $::internal_address == $tb_ip {
      package { $tb_package:
        ensure => installed,
      }
    } else {
      package { $mdm_package:
        ensure => installed,
      }
    }
  }

  file { 'scaleio.py':
    path => '/usr/lib/python2.6/site-packages/cinder/volume/drivers/emc/scaleio.py',
    source => 'puppet:///modules/install_scaleio_controller/scaleio.py',
    mode  => '644',
    owner => 'root',
    group => 'root',
  } ->

  file { 'scaleio.filters':
    path => '/usr/share/cinder/rootwrap/scaleio.filters',
    source => 'puppet:///modules/install_scaleio_controller/scaleio.filters',
    mode  => '644',
    owner => 'root',
    group => 'root',
    before => File['cinder_scaleio.config'], 
  }

  # 3. Create config for ScaleIO
  $cinder_scaleio_config = "[scaleio]
rest_server_ip=$mdm_ip_1
rest_server_username=admin
rest_server_password=Scaleio123
protection_domain_name=${::fuel_settings['scaleio']['protection_domain']}
storage_pools=${::fuel_settings['scaleio']['protection_domain']}:${::fuel_settings['scaleio']['storage_pool_1']},${::fuel_settings['scaleio']['protection_domain']}:${::fuel_settings['scaleio']['storage_pool_2']}
storage_pool_name=${::fuel_settings['scaleio']['storage_pool_1']}
round_volume_capacity=True
force_delete=True
verify_server_certificate=False
"

  file { 'cinder_scaleio.config':
    ensure  => present,
    path  => '/etc/cinder/cinder_scaleio.config',
    content => $cinder_scaleio_config,
    mode  => 0644,
    owner => root,
    group => root,
    before => Ini_setting['cinder_conf_volume_driver'],
  } ->

  # 4. To /etc/cinder/cinder.conf add
  ini_setting { 'cinder_conf_volume_driver':
    ensure  => present,
    path    => '/etc/cinder/cinder.conf',
    section => 'DEFAULT',
    setting => 'volume_driver',
    value => 'cinder.volume.drivers.emc.scaleio.ScaleIODriver',
    before => Ini_setting['cinder_conf_scio_config'],
  } ->

  ini_setting { 'cinder_conf_scio_config':
    ensure  => present,
    path    => '/etc/cinder/cinder.conf',
    section => 'DEFAULT',
    setting => 'cinder_scaleio_config_file',
    value => '/etc/cinder/cinder_scaleio.config',
  } ->

  install_gateway { 'installing_gateway': } ->

  exec { "install_sdc":    
    command => "/bin/bash -c \"MDM_IP=${mdm_ip_1},${mdm_ip_2} yum install -y EMC-ScaleIO-sdc\"",        
    path => "/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/root/bin",
  } ~>

  service { $services:
    ensure => running,
  }
}
