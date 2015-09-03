class install_scaleio_sds
{

  $sds_package = 'EMC-ScaleIO-sds'

  $nodes_hash = $fuel_settings['nodes']
  $primary_controller_nodes = filter_nodes($nodes_hash,'role','primary-controller')
  $controllers = concat($primary_controller_nodes, filter_nodes($nodes_hash,'role','controller'))
  $roles = node_roles($nodes_hash, $::fuel_settings['uid'])
  $controller_internal_addresses = nodes_to_hash($controllers,'name','internal_address')
  $controller_nodes = ipsort(values($controller_internal_addresses))
  $devices = concat(split( $::fuel_settings['scaleio']['drive_list_1'], ','), split( $::fuel_settings['scaleio']['drive_list_2'], ','))

  $mdm_ip_1 = $controller_nodes[0]
  $mdm_ip_2 = $controller_nodes[1]

  #Create ScaleIO repo
  #$scaleio_repo_content = "[scaleio]
#name=Getty Images ScaleIO Packages
#baseurl=${::fuel_settings['scaleio']['scaleio_repo']}
#enabled=1
#gpgcheck=0
#priority=1
#    "

  # file { '/etc/yum.repos.d/scaleio.repo':
  #   content => "$scaleio_repo_content",
  #   mode  => '644',
  #   owner => 'root',
  #   group => 'root',
  #   before => Exec['install_sdc'],
  #  }

  define clean_gpt {
    exec { $name:
      command => "/sbin/parted -s ${name} mklabel msdos",
      path => '/usr/bin:/usr/sbin:/bin:/usr/local/bin',
      subscribe => Package['parted'],
      refreshonly => true,
    }
  }

  package { 'parted':
    ensure => installed,
  } 

  clean_gpt { $devices:
    before => Package[$sds_package],
  }

  package { $sds_package:
    ensure => installed,
  }
}
