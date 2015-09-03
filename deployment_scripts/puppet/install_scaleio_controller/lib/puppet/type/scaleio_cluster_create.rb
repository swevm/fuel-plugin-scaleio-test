Puppet::Type.newtype(:scaleio_cluster_create) do
	@doc = "Create a new scaleio cluster."
	ensurable
	newparam(:password) do
		desc "The password of a cluster"
	end

	newparam(:protection_domain_name, :namevar => true) do
		desc "ScaleIO protection domain name"
	end

	newparam (:mdm_ip_2) do
		desc "IP address of the second MDM"
	end

	newparam (:tb_ip) do
		desc "IP address of the TB"
	end
end