# FIWARE Lab monitoring system (based on Ceilometer and Monasca)

## Description

The following figure describes the high level architecture of the monitoring system.

![FIWARE Monitoring Architecture][fiware_monitoring_architecture_pict]

Data is collected through [Ceilometer][ceilometer] (where customized pollsters have been developed) from each node.
Relevant metrics are sent to [Monasca][monasca] on master node using [Monasca-Ceilometer][monasca_ceilometer] plugin.
[Sanity Check tool][fihealth_sanity_checks] also publishes the sanity status of the nodes directly to Monasca. Data
is stored and eventually passed to the [FIWARE Big Data GE (Cosmos)][cosmos] for aggregation and analysis. Finally,
[Infographics][fiware_lab_infographics] (but also other clients) retrieve the data from Monasca API.

This repository contains all the pollsters and the additional customization that Infrastructure Owners (IOs) have to
perform. IOs should customize the standard Ceilometer installation by adding some pollsters and by editing several
configuration files.

Some additional information about Ceilometer: _it is a tool created in order to handle the [Telemetry][telemetry]
requirements of an OpenStack environment (this includes use cases such as metering, monitoring, and alarming to
name a few)_.

![Ceilometer Architecture][ceilometer_architecture_pict]
_Figure taken from [Ceilometer documentation][ceilometer_architecture_doc]_

After installation and configuration, IOs should be able to obtain monitoring information about the following resources
of their Openstack environments at Infographics page or by querying Federation Monitoring API:
- __region__
- __hosts__
- __images__
- __host services__ _(OpenStack services: nova, glance, cinder, ... )_
- __vm__ (i.e. instances)


## Installation

The installation and configuration procedure involves both the central node (i.e. Controller) and the compute nodes.

### Central agent pollsters

#### Pollster for region

Please follow these steps:

1. Open the file `/etc/ceilometer/ceilometer.conf` and add these entries (_with your region values_) at the end:

   ```
   [region]
   latitude=1.1
   longitude=12.2
   location=IT
   netlist=net04_ext,net05_ext
   ram_allocation_ratio=1.5
   cpu_allocation_ratio=16
   ```

   Pay attention to the `netlist` attribute: the names of external networks in your OpenStack installation.

2. Copy the folder [region](/region) from this repository into Ceilometer package (typically located at the folder
   `/usr/lib/python2.7/dist-packages/ceilometer`).

   After that, `RegionPollster` class should be available:

   ```
   # python -c 'from ceilometer.region import region; print region.RegionPollster().__class__'
   <class 'ceilometer.region.region.RegionPollster'>
   ```

3. Edit Ceilometer entry points file (`/usr/lib/python2.7/dist-packages/ceilometer-2015.1.2.egg-info/entry_points.txt`)
   to add the new pollster at the `[ceilometer.poll.central]` section:

   ```
   region = ceilometer.region.region:RegionPollster
   ```

4. Restart Ceilometer Central Agent:

   If using HA:
   ```
   # crm resource restart p_ceilometer-agent-central
   ```
   Otherwise:
   ```
   # service ceilometer-agent-central restart
   ```

5. Check if Ceilometer is able to retrieve information about the region (remember to replace _RegionOne_ with the name
   of your region):

   ```
   # ceilometer resource-list -q resource_id=RegionOne
   +-------------+-----------+---------+------------+
   | Resource ID | Source    | User ID | Project ID |
   +-------------+-----------+---------+------------+
   | RegionOne   | openstack | None    | None       |
   +-------------+-----------+---------+------------+
   ```
   ```
   # ceilometer resource-show RegionOne
   +-------------+------------------------------------------+
   | Property    | Value                                    |
   +-------------+------------------------------------------+
   | metadata    | {'name': 'RegionOne', 'longitude': ....} |
   | project_id  | None                                     |
   | resource_id | RegionOne                                |
   | source      | openstack                                |
   | user_id     | None                                     |
   +-------------+------------------------------------------+
   ```

#### Pollster for image

__NOT NEEDED IF YOU HAVE A CEILOMETER FOR OPENSTACK KILO__

The pollster for the images is already provided by a standard installation of Ceilometer. Check if it is enabled at the
entry points:

1. Open the file: `/usr/lib/python2.7/dist-packages/ceilometer-2015.1.2.egg-info/entry_points.txt` and look for this
   entry at the `[ceilometer.notification]` section:

   ```
   image = ceilometer.image.notifications:Image
   ```

2. Check if one of your images is available and provided with all the needed information

   ```
   # ceilometer meter-list | grep image
   +-------+-------+-------+----------------+---------+------------+
   | Name  | Type  | Unit  | Resource ID    | User ID | Project ID |
   +-------+-------+-------+----------------+---------+------------+
   | image | gauge | image | aa-bb-cc-dd-ee | None    | 0000000000 |
   +-------+-------+-------+----------------+---------+------------+
   ```


### Compute agent pollsters

#### Pollster for hosts

1. Add these entries to the file `/etc/nova/nova.conf` at section `[DEFAULT]` and restart the __nova-compute__ service:

   ```
   compute_monitors = ComputeDriverCPUMonitor
   notification_driver = messagingv2
   ```

2. Copy [host.py](/compute_pollster/host.py) file from the [compute_pollster](/compute_pollster) folder into the compute
   pollsters folder of the Ceilometer package at `/usr/lib/python2.7/dist-packages/ceilometer/compute/pollsters`

   After that, `HostPollster` class should be available:

   ```
   # python -c 'from ceilometer.compute.pollsters import host; print host.HostPollster().__class__'
   <class 'ceilometer.compute.pollsters.host.HostPollster'>
   ```

3. Edit Ceilometer entry points file (`/usr/lib/python2.7/dist-packages/ceilometer-2015.1.2.egg-info/entry_points.txt`)
   to add the new pollster at the `[ceilometer.poll.compute]` section:

   ```
   compute.info = ceilometer.compute.pollsters.host:HostPollster
   ```

4. Restart Ceilometer Compute Agent and check if you are able to retrieve the host information from Ceilometer (pay
   attention to the __compute.node.cpu.percent__, which is linked to the Nova configuration, and please note that the
   resource_id is the concatenation \<_host_\>\_\<_nodename_\>, values which are usually the same)

   ```
   # service nova-compute restart
   # service ceilometer-agent-compute restart
   ```

   ```
   # ceilometer meter-list | grep compute.node
   +--------------------------+-------+------+---------------------------+---------+------------+
   | Name                     | Type  | Unit | Resource ID               | User ID | Project ID |
   +--------------------------+-------+------+---------------------------+---------+------------+
   | compute.node.cpu.max     | gauge | cpu  | node-2.aa.bb_node-2.aa.bb | None    | None       |
   | compute.node.cpu.now     | gauge | cpu  | node-2.aa.bb_node-2.aa.bb | None    | None       |
   | compute.node.cpu.percent | gauge | %    | node-2.aa.bb_node-2.aa.bb | None    | None       |
   | compute.node.cpu.tot     | gauge | cpu  | node-2.aa.bb_node-2.aa.bb | None    | None       |
   | compute.node.disk.max    | gauge | GB   | node-2.aa.bb_node-2.aa.bb | None    | None       |
   | compute.node.disk.now    | gauge | GB   | node-2.aa.bb_node-2.aa.bb | None    | None       |
   | compute.node.disk.tot    | gauge | GB   | node-2.aa.bb_node-2.aa.bb | None    | None       |
   | compute.node.ram.max     | gauge | MB   | node-2.aa.bb_node-2.aa.bb | None    | None       |
   | compute.node.ram.now     | gauge | MB   | node-2.aa.bb_node-2.aa.bb | None    | None       |
   | compute.node.ram.tot     | gauge | MB   | node-2.aa.bb_node-2.aa.bb | None    | None       |
   +--------------------------+-------+------+---------------------------+---------+------------+
   ```


#### Pollster for vm

__NOT NEEDED IF YOU HAVE A CEILOMETER FOR OPENSTACK KILO__

1. Replace file `/usr/lib/python2.7/dist-packages/ceilometer/compute/virt/inspector.py` with that at location
   [virt/inspector.py](/virt/inspector.py) in this repository

2. Replace file `/usr/lib/python2.7/dist-packages/ceilometer/compute/virt/libvirt/inspector.py` with that at location
   [virt/libvirt/inspector.py](/virt/libvirt/inspector.py) in this repository

3. Replace file `/usr/lib/python2.7/dist-packages/ceilometer/compute/pollsters/memory.py` with that at location
   [compute_pollster/memory.py](/compute_pollster/memory.py) in this repository

4. Replace file `/usr/lib/python2.7/dist-packages/ceilometer/compute/pollsters/disk.py` with that at location
   [compute_pollster/disk.py](/compute_pollster/disk.py) in this repository

5. Edit Ceilometer entry points file (`/usr/lib/python2.7/dist-packages/ceilometer-2015.1.2.egg-info/entry_points.txt`)
   to add the new pollsters at the `[ceilometer.poll.compute]` section:

   ```
   memory.usage = ceilometer.compute.pollsters.memory:MemoryUsagePollster
   memory.resident = ceilometer.compute.pollsters.memory:MemoryResidentPollster
   disk.capacity = ceilometer.compute.pollsters.disk:CapacityPollster
   ```

6. Restart Compute Agent and check if you are able to retrieve information about one of your VMs (disk and memory):

   ```
   # ceilometer meter-list | grep 'disk.capacity'
   +--------------------------+-------+------+---------------------------+---------+------------+
   | Name                     | Type  | Unit | Resource ID               | User ID | Project ID |
   +--------------------------+-------+------+---------------------------+---------+------------+
   | disk.capacity            | gauge | B    | aa-bb-cc-dd-ee            | user1   |  project1  |
   +--------------------------+-------+------+---------------------------+---------+------------+
   ```
   ```
   # ceilometer sample-list -m disk.capacity -q"resource_id=aa-bb-cc-dd-ee"
   +----------------+---------------+-------+--------------+------+---------------------+
   | Resource ID    | Name          | Type  | Volume       | Unit | Timestamp           |
   +----------------+---------------+-------+--------------+------+---------------------+
   | aa-bb-cc-dd-ee | disk.capacity | gauge | 3221225472.0 | B    | 2015-11-11T15:38:43 |
   +----------------+---------------+-------+--------------+------+---------------------+
   ```
   ```
   # ceilometer meter-list | grep 'memory.'
   +-----------------+-------+------+-----------------+---------+------------+
   | Name            | Type  | Unit | Resource ID     | User ID | Project ID |
   +-----------------+-------+------+-----------------+---------+------------+
   | memory          | gauge | MB    | aa-bb-cc-dd-ee | user1   |  project1  |
   | memory.resident | gauge | MB    | aa-bb-cc-dd-ee | user1   |  project1  |
   | memory.usage    | gauge | MB    | aa-bb-cc-dd-ee | user1   |  project1  |
   +-----------------+-------+------+-----------------+---------+------------+
   ```
   ```
   # ceilometer sample-list -m memory.usage -q"resource_id=aa-bb-cc-dd-ee"
   +----------------+---------------+-------+------------+------+---------------------+
   | Resource ID    | Name          | Type  | Volume     | Unit | Timestamp           |
   +----------------+---------------+-------+------------+------+---------------------+
   | aa-bb-cc-dd-ee | memory.usage  | gauge | 101.0      | MB   | 2015-11-11T15:38:43 |
   +----------------+---------------+-------+------------+------+---------------------+
   ```


### Monasca

#### Monasca Agent

In order to monitor the OpenStack services (i.e. __host services__), [monasca-agent][monasca_agent] should be installed
in the Controller:

1. Download sources from [GitHub repository][monasca_agent] and install the package:

   ```
   # python setup.py install
   ```

2. Edit configuration file `/etc/monasca/agent/agent.yaml` to add the URL of Monasca API:

   ```
   Api:
      ...
      monasca_url: http://127.0.0.1:8070/v2.0
      ...
   ```

3. Please check Keystone URL and credentials in the configuration file (Ceilometer user could be used here):

   ```
   Api:
      ...
      keystone_url: http://127.0.0.1:35357/v3
      username: myuser
      password: mypass
      ...
   ```

   Make sure the specified user has the __monasca_user__ role added.

4. Check that all OpenStack services (nova, cinder, etc.) to be monitored are included in the configuration file
   `/etc/monasca/agent/conf.d/process.yaml` used by [Process Checks plugin][monasca_agent_plugin_process_checks]

5. Restart monasca-agent service:

   ```
   # service monasca-agent restart
   ```

#### Monasca Ceilometer plugin

Please follow these steps to install the Python plugin and storage driver for Ceilometer to send samples to Monasca at
the OpenStack controller:

1. Install python-monascaclient:

   ```
   # pip install python-monascaclient==1.0.27
   ```

2. Copy the following files from [Ceilosca package of Monasca-Ceilometer][monasca_ceilometer] into the Ceilometer
   package at `/usr/lib/python2.7/dist-packages/ceilometer`:

   ```
   monasca-ceilometer/ceilosca/ceilometer/monasca_client.py
   monasca-ceilometer/ceilosca/ceilometer/storage/impl_monasca.py
   monasca-ceilometer/ceilosca/ceilometer/storage/impl_monasca_filtered.py
   monasca-ceilometer/ceilosca/ceilometer/publisher/monasca_data_filter.py
   monasca-ceilometer/ceilosca/ceilometer/publisher/monasca_metric_filter.py
   monasca-ceilometer/ceilosca/ceilometer/publisher/monclient.py
   ```

3. Edit `/usr/lib/python2.7/dist-packages/ceilometer-2015.1.2.egg-info/entry_points.txt` to add the following entries:

   At `[ceilometer.publisher]` section:
   ```
   monasca = ceilometer.publisher.monclient:MonascaPublisher
   ```

   At `[ceilometer.metering.storage]` section:
   ```
   monasca = ceilometer.storage.impl_monasca_filtered:Connection
   ```

4. Edit configuration file `/etc/ceilometer/pipeline.yaml` to include the definitions of elements __meter_source__ and
   __meter_sink__ needed to send to Monasca a subset of metrics gathered by Ceilometer. Please refer to sample file at
   `monasca-ceilometer/etc/ceilometer/pipeline.yaml` from [Monasca-Ceilometer][monasca_ceilometer]

5. Modify `/etc/ceilometer/ceilometer.conf` to configure a new meter storage driver for Ceilometer:

   ```
   metering_connection = monasca://http://127.0.0.1:8070/v2.0
   ```

   Please make sure the user specified under `[service_credentials]` section of the same file has __monasca_user__
   role added.

6. Copy `monasca-ceilometer/etc/ceilometer/monasca_field_definitions.yaml` from [Monasca-Ceilometer][monasca_ceilometer]
   into `/etc/ceilometer` folder

7. Restart all Ceilometer services:

   ```
   # CEILOMETER_SERVICES=$(cd /etc/init.d; ls -1 ceilometer*)
   # for NAME in $CEILOMETER_SERVICES; do service $NAME restart; done
   ```


[ceilometer]:
http://docs.openstack.org/developer/ceilometer/
"Ceilometer Developer Documentation"

[ceilometer_architecture_doc]:
http://docs.openstack.org/developer/ceilometer/architecture.html
"Ceilometer System Architecture"

[ceilometer_architecture_pict]:
http://docs.openstack.org/developer/ceilometer/_images/ceilo-arch.png
"Ceilometer System Architecture"

[telemetry]:
https://wiki.openstack.org/wiki/Telemetry
"OpenStack Telemetry"

[monasca]:
https://wiki.openstack.org/wiki/Monasca
"Monasca Documentation"

[monasca_agent]:
https://github.com/telefonicaid/monasca-agent/tree/fiware
"Monasca Agent"

[monasca_agent_plugin_process_checks]:
https://github.com/telefonicaid/monasca-agent/blob/fiware/docs/Plugins.md#process-checks
"Monasca Agent Standard Plugins - Process Checks"

[monasca_ceilometer]:
https://github.com/telefonicaid/monasca-ceilometer/tree/fiware
"Python plugin and storage driver for Ceilometer to send samples to Monasca"

[cosmos]:
https://github.com/Fiware/context.Cosmos/blob/master/README.md
"FIWARE Big Data GE (Cosmos)"

[fihealth_sanity_checks]:
https://github.com/Fiware/ops.Health/tree/master/fiware-region-sanity-tests
"FIWARE Health - Sanity Checks"

[fiware_lab_infographics]:
https://github.com/Fiware/ops.Fi-lab-infographics/blob/master/README.md
"FIWARE Lab Infographics"

[fiware_monitoring_architecture_pict]:
/img/FIWARE_Monitoring_Arch.png
"FIWARE Monitoring Architecture"
