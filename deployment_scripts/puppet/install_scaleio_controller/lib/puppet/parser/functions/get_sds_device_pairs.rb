module Puppet::Parser::Functions
  newfunction(:get_sds_device_pairs, :type => :rvalue, :doc => <<-EOS
    this finction return list of pars <sds_ip>_<device>
  EOS
  ) do |argv|
    sds_ips = argv[0]
    devices = argv[1].split(',')
    res = []
    sds_ips.each do |ip|
      devices.each do |device|
        res << "#{ip}_#{device}"
      end
    end
    return res
  end
end
