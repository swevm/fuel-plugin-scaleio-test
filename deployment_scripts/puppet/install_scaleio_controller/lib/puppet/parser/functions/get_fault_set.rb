require 'uri'
require 'net/http'
require 'rubygems'
require 'json'
require 'yaml'

module Puppet::Parser::Functions
  newfunction(:get_fault_set, :type => :rvalue, :doc => <<-EOS
    this function returns list of pars <sds_name>_<fault_set>
  EOS
  ) do |argv|
    sds_names = argv[0]
    
    thing = YAML.load_file('/etc/astute.yaml')
    master_ip = thing['master_ip']
    
    res = {}
    sds_names.each do |name|

      node_id = name.split('-')[1]

      #Getting auth token
      http = Net::HTTP.new(master_ip,'35357')
      headers = { "Content-type" => "application/json"}
      data = '{"auth": {"tenantName": "admin", "passwordCredentials": {"username": "admin", "password": "admin"}}}'
      resp = http.post('/v2.0/tokens', data, headers)
      response = JSON.parse(resp.body)
      token = response["access"]["token"]["id"]

      #Getting node name
      uri = '/api/nodes/'+node_id
      http_name = Net::HTTP.new(master_ip,'8000')
      req_name = Net::HTTP::Get.new(uri)
      req_name.add_field("X-Auth-Token", token)
      resp_name = http_name.start do |hresp|
        hresp.request(req_name)
      end
      fs = JSON.parse(resp_name.body)["name"].split('-')[2]
      res[name] = fs
      
    end
    return res
  end
end
