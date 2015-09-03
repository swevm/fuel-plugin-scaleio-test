Puppet::Type.type(:scaleio_cluster_create).provide(:init_cluster) do
	def create
		system ('/bin/scli --login --username admin --password admin')
	end
end