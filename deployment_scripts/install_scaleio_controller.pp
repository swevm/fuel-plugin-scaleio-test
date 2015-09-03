$fuel_settings = parseyaml($astute_settings_yaml)
$nodes_hash = $::fuel_settings['nodes']
$node = filter_nodes($nodes_hash,'name',$::hostname)
$internal_address = $node[0]['internal_address']
class {'install_scaleio_controller': }
