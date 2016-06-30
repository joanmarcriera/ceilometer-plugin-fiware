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

The installation and configuration procedure involves both the central nodes (i.e. controllers) and the compute nodes.

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

3. Edit entry points file of your installed version of Ceilometer (i.e., for version 2015.1.2 should be located at path
   `/usr/lib/python2.7/dist-packages/ceilometer-2015.1.2.egg-info/entry_points.txt`) and please add the new pollster at
   the `[ceilometer.poll.central]` section:

   ```
   region = ceilometer.region.region:RegionPollster
   ```

4. Restart Ceilometer Central Agent:

   If using Fuel HA:
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

4. Please check the polling frequency defined by `interval` parameter at `/etc/ceilometer/pipeline.yaml`. Its default
   value is 60 seconds: you may consider lowering the polling rate.

5. Restart both Nova Compute and Ceilometer Compute Agent, and check if you are able to retrieve the host information
   from Ceilometer (pay attention to the __compute.node.cpu.percent__, which is linked to the Nova configuration, and
   please note that the resource_id is the concatenation \<_host_\>\_\<_nodename_\>, values which are usually the same)

   ```
   # service nova-compute restart
   # service ceilometer-agent-compute restart
   ```

   ```
   # ceilometer meter-list | grep compute.node
   +--------------------------+-------+------+---------------------------+---------+------------+
   | Name                     | Type  | Unit | Resource ID               | User ID | Project ID |
   +--------------------------+-------+------+---------------------------+---------+------------+
   | compute.node.cpu.percent | gauge | %    | node-2.aa.bb_node-2.aa.bb | None    | None       |
   | compute.node.cpu.max     | gauge | cpu  | node-2.aa.bb_node-2.aa.bb | None    | None       |
   | compute.node.cpu.now     | gauge | cpu  | node-2.aa.bb_node-2.aa.bb | None    | None       |
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

#### Monasca Ceilometer plugin

Please follow these steps to install in __all controller nodes__ the Python plugin and storage driver for Ceilometer to
send samples to Monasca:

1. Install python-monascaclient:

   ```
   # pip install python-monascaclient==1.0.27
   ```

2. Copy the following files from *Ceilosca* component (included in the [latest release][monasca_ceilometer_releases]
   of [Monasca-Ceilometer][monasca_ceilometer]) into the Ceilometer package at your Python installation directory
   (usually `/usr/lib/python2.7/dist-packages/ceilometer`):

   ```
   monasca-ceilometer/ceilosca/ceilometer/monasca_client.py
   monasca-ceilometer/ceilosca/ceilometer/storage/impl_monasca.py
   monasca-ceilometer/ceilosca/ceilometer/storage/impl_monasca_filtered.py
   monasca-ceilometer/ceilosca/ceilometer/publisher/monasca_data_filter.py
   monasca-ceilometer/ceilosca/ceilometer/publisher/monasca_metric_filter.py
   monasca-ceilometer/ceilosca/ceilometer/publisher/monclient.py
   ```

   Additionally, please create a text file at `/usr/lib/python2.7/dist-packages/ceilometer-2015.1.*.egg-info` to record
   the exact version of Ceilosca being manually installed. For instance, when installing version "2015.1-FIWARE-5.3.3":

   ```
   # VERSION=2015.1-FIWARE-5.3.3
   # echo version=$VERSION > /usr/lib/python2.7/dist-packages/ceilometer-2015.1.*.egg-info/ceilosca.txt
   ```

3. Edit `/usr/lib/python2.7/dist-packages/ceilometer-2015.1.*.egg-info/entry_points.txt` to add the following entries:

   At `[ceilometer.publisher]` section:
   ```
   monasca = ceilometer.publisher.monclient:MonascaPublisher
   ```

   At `[ceilometer.metering.storage]` section:
   ```
   monasca = ceilometer.storage.impl_monasca_filtered:Connection
   ```

4. Copy (or merge) the following configuration files from Monasca-Ceilometer repository into `/etc/ceilometer`:

   ```
   monasca-ceilometer/etc/ceilometer/pipeline.yaml
   monasca-ceilometer/etc/ceilometer/monasca_field_definitions.yaml
   ```

   Please ensure elements in __meter_source__ include the subset of Ceilometer metrics required by FIWARE Monitoring
   (this should be the case without any modifications) and don't forget to set *Monasca endpoint at Master Node* in
   the publishers of __meter_sink__:
   ```
   sinks:
       - name: meter_sink
         transformers:
         publishers:
             - notifier://
             - monasca://http://MONASCA_API:8070/v2.0
   ```

5. Modify `/etc/ceilometer/ceilometer.conf` to configure a new meter storage driver for Ceilometer (*substitute with the
   endpoint of Master Node*):

   ```
   metering_connection = monasca://http://MONASCA_API:8070/v2.0
   ```

   Please make sure the user specified under `[service_credentials]` section of the same file has __monasca_user__
   role added.

7. Restart all Ceilometer services:

   If using Fuel HA:
   ```
   # crm resource restart p_ceilometer-agent-central
   # crm resource restart p_ceilometer-alarm-evaluator
   # service ceilometer-agent-notification restart
   # service ceilometer-collector restart
   # service ceilometer-api restart
   # service ceilometer-alarm-notifier restart
   ```
   Otherwise:
   ```
   # CEILOMETER_SERVICES=$(cd /etc/init.d; ls -1 ceilometer*)
   # for NAME in $CEILOMETER_SERVICES; do service $NAME restart; done
   ```

#### Monasca Agent

In order to monitor the OpenStack services (i.e. __host services__), [monasca-agent][monasca_agent_doc] should be
installed in all the controllers:

1. Create a Python virtualenv located at `/opt/monasca`:

   ```
   # cd /opt
   # virtualenv monasca
   # source monasca/bin/activate
   ```

2. Please install `pbr` after upgrading your versions of `setuptools` and `pip`:

   ```
   (monasca)# pip install --upgrade setuptools
   (monasca)# pip install --upgrade pip
   (monasca)# pip install pbr==1.10.0
   ```

3. Locate the [latest release][monasca_agent_releases] of Monasca Agent component and use `pip` tool to install it. For
   instance, to install version "1.1.21-FIWARE", please run:

   ```
   (monasca)# VERSION=1.1.21-FIWARE
   (monasca)# PBR_VERSION=$VERSION pip install git+https://github.com/telefonicaid/monasca-agent.git@$VERSION
   ```

4. Configure the component using `monasca-setup` (as described in the [documentation][monasca_agent_configuration]).
   Note that you will have to provide:

   * Your region name
   * The address or domain name of Monasca API
   * Valid Keystone credentials, usually those of the Ceilometer service (which should have previously been assigned
     the *monasca_user* role)

   ```
   (monasca)# monasca-setup \
     --username=YOUR_CEILOMETER_USER \
     --password=THE_PASSWORD \
     --project_name=service \
     --keystone_url=http://cloud.lab.fiware.org:4731/v3 \
     --monasca_url=http://MONASCA_API:8070/v2.0 \
     --dimensions=region:YOUR_REGION
   ```

5. Only the file `process.yaml` used by [Process Checks plugin][monasca_agent_plugin_process_checks] is required at
   `/etc/monasca/agent/conf.d/`. Please ensure it is configured to monitor all Openstack services (this should be the
   case without any modifications, but it is appropriate to check that all of your services are monitored). The example
   below shows configuration information for one service (nova-scheduler):

   ```
   - built_by: Nova
     detailed: false
     dimensions:
       component: nova-scheduler
       service: compute
     exact_match: false
     name: nova-scheduler
     search_string:
     - nova-scheduler
   ```

6. Please verify the configuration is correct:

   ```
   # service monasca-agent configtest
   ```

7. Finally, restart the agent:

   ```
   # service monasca-agent restart
   ```


## Verification

In order to verify whether the installation and configuration of FIWARE Monitoring have been successful, we provide the
[fiware-check-monitoring.sh](/tools/fiware-check-monitoring.sh) script available at [tools](/tools) folder. It performs
a set of checks, not only in the controller itself but also in the compute nodes, and shows results in a human-readable
manner.

Running the script with no additional parameters may suffice in most of the cases, but some adjustments could be done
with command line options. It only requires defining the standard OpenStack environment variables with the credentials
needed to run `nova` and other commands.

For full information about the usage and options, please type:

   ```
   # fiware-check-monitoring.sh --help
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

[monasca_agent_doc]:
https://github.com/telefonicaid/monasca-agent/blob/fiware/README.md
"Monasca Agent"

[monasca_agent_configuration]:
https://github.com/telefonicaid/monasca-agent/blob/fiware/docs/Agent.md#configuring
"Monasca Agent Configuration"

[monasca_agent_plugin_process_checks]:
https://github.com/telefonicaid/monasca-agent/blob/fiware/docs/Plugins.md#process-checks
"Monasca Agent Standard Plugins - Process Checks"

[monasca_agent_releases]:
https://github.com/telefonicaid/monasca-agent/releases
"Monasca Agent Releases"

[monasca_ceilometer]:
https://github.com/telefonicaid/monasca-ceilometer/tree/fiware
"Python plugin and storage driver for Ceilometer to send samples to Monasca"

[monasca_ceilometer_releases]:
https://github.com/telefonicaid/monasca-ceilometer/releases
"Releases of Python plugin and storage driver for Ceilometer to send samples to Monasca"

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
