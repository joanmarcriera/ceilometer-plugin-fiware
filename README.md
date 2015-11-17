# The new FIWARE monitoring system

## Description

This repository contains all the pollsters and the additional customization that IOs have to perform. IOs have to customize the standard [ceilometer](https://wiki.openstack.org/wiki/Ceilometer) installation, by adding some pollsters or by editing the configuration file.

Some additional information about ceilometer: _it is a tool created in order to handle the Telemetry requirements of an OpenStack environment (this includes use cases such as metering, monitoring, and alarming to name a few)_

<img src="http://docs.openstack.org/developer/ceilometer/_images/ceilo-arch.png">

After the installation/configuration, IOs should be able to obtain information about their Openstack installation directly from ceilometer:
- __region__
- __image__
- __host service__ _(nova, glance, cinder, ... )_
- __host__
- __vm__

The installation/configuration is divided into two main parts
- the installation procedure in the central node
- the installation procedure on the compute nodes

On the first side only the main pollsters will be installed, in the second one only the compute agent pollsters will be installed

## Installation

### Central agent pollsters

#### Pollster for region
Please follow these steps:
1. Open the file ``/etc/ceilometer/ceilometer.conf``, at the end of it add these rows (_with your region values_):
```
[region]
latitude=1.1
longitude=12.2
location=IT
netlist=net04_ext,net05_ext
ram_allocation_ratio=1.5
cpu_allocation_ratio=16
```
Replace the values with your Openstack installation information.

2. Open this folder and copy the __region__ folder from the github repository
```
cd /usr/lib/python2.7/dist-packages/ceilometer
```
After that, you have to see the region folder and its content:
```
ls /usr/lib/python2.7/dist-packages/ceilometer/region
__init__.py
region.py
```
3. Edit the ceilometer configuration file ``/usr/lib/python2.7/dist-packages/ceilometer-2014.2.2.egg-info/entry_points.txt``  find the ``[ceilometer.poll.central]`` section and add this row:
```
region = ceilometer.region.region:RegionPollster
```
4. Restart the central pollster agent
5. Check if ceilometer is able to see the information about the region
```
#ceilometer resource-list
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
The pollster for the images entity is already provided by a standard installation of ceilometer. Check if it is enabled in the configuration file:
1. open the file: ``/usr/lib/python2.7/dist-packages/ceilometer-2014.2.2.egg-info/entry_points.txt`` check under ``[ceilometer.notification]``
```
image = ceilometer.image.notifications:Image
```
2. Check if one of your images is available and provided with all the needed information
```
#ceilometer meter-list | grep image
+-------+-------+-------+----------------+---------+------------+
| Name  | Type  | Unit  | Resource ID    | User ID | Project ID |
+-------+-------+-------+----------------+---------+------------+
| image | gauge | image | aa-bb-cc-dd-ee | None    | 0000000000 |
+-------+-------+-------+----------------+---------+------------+
```

#### Pollster for host_service
__TO DO__ -we have to understand how monasca already manage this checks!-

### Compute agent pollsters

#### Pollster for host
1. Add this row to the file ``/etc/nova/nova.conf`` in the section ``[DEFAULT]`` and restart the nova-compute service
```
compute_monitors=ComputeDriverCPUMonitor
```
2. Copy the __host.py__ file from the compute_pollster folder into this folder ``/usr/lib/python2.7/dist-packages/ceilometer/compute/pollsters``
3. enable the pollster by adding the following row inside the file ``/usr/lib/python2.7/dist-packages/ceilometer-2014.2.2.egg-info/entry_points.txt
`` and under the section ``[ceilometer.poll.compute]`` :
```
compute.info = ceilometer.compute.pollsters.host:HostPollster
```

4. Restart the compute agent and check if you are able to see the host information inside your ceilometer (pay attention to the __compute.node.cpu.percent__, this is linked to the nova configuration)
```
#ceilometer meter-list | grep compute.node
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
1. Replace the __inspector.py__ in the folder ``/usr/lib/python2.7/dist-packages/ceilometer/compute/virt`` with the one in the reposirtory at __compute_pollster/virt/inspector.py__
2. Replace the __inspector.py__ in the folder ``/usr/lib/python2.7/dist-packages/ceilometer/compute/virt/libvirt`` with the one in the reposirtory at __compute_pollster/virt/libvirt/inspector.py__
3. Replace the __memory.py__ file from the compute_pollster inside the folder ``/usr/lib/python2.7/dist-packages/ceilometer/compute/pollsters``
4. Replace the __disk.py__ file from the compute pollster inside the same folder ``/usr/lib/python2.7/dist-packages/ceilometer/compute/pollsters``
5. enable the pollsters by adding the following rows inside the file ``/usr/lib/python2.7/dist-packages/ceilometer-2014.2.2.egg-info/entry_points.txt
`` and under the section ``[ceilometer.poll.compute]``
```
memory.usage = ceilometer.compute.pollsters.memory:MemoryUsagePollster
memory.resident = ceilometer.compute.pollsters.memory:MemoryResidentPollster
disk.capacity = ceilometer.compute.pollsters.disk:CapacityPollster
```
6. Restart the compute agent and check if you are able to see the info about one of your VMs (disk and memory):
```
#ceilometer meter-list | grep 'disk.capacity'
+--------------------------+-------+------+---------------------------+---------+------------+
| Name                     | Type  | Unit | Resource ID               | User ID | Project ID |
+--------------------------+-------+------+---------------------------+---------+------------+
| disk.capacity            | gauge | B    | aa-bb-cc-dd-ee            | user1   |  project1  |
+--------------------------+-------+------+---------------------------+---------+------------+
```
```
#ceilometer sample-list -m disk.capacity -q"resource_id=aa-bb-cc-dd-ee"
+----------------+---------------+-------+--------------+------+---------------------+
| Resource ID    | Name          | Type  | Volume       | Unit | Timestamp           |
+----------------+---------------+-------+--------------+------+---------------------+
| aa-bb-cc-dd-ee | disk.capacity | gauge | 3221225472.0 | B    | 2015-11-11T15:38:43 |
+----------------+---------------+-------+--------------+------+---------------------+
```
```
#ceilometer meter-list | grep 'memory.'
+-----------------+-------+------+-----------------+---------+------------+
| Name            | Type  | Unit | Resource ID     | User ID | Project ID |
+-----------------+-------+------+-----------------+---------+------------+
| memory          | gauge | MB    | aa-bb-cc-dd-ee | user1   |  project1  |
| memory.resident | gauge | MB    | aa-bb-cc-dd-ee | user1   |  project1  |
| memory.usage    | gauge | MB    | aa-bb-cc-dd-ee | user1   |  project1  |
+-----------------+-------+------+-----------------+---------+------------+
```
```
#ceilometer sample-list -m memory.usage -q"resource_id=aa-bb-cc-dd-ee"
+----------------+---------------+-------+------------+------+---------------------+
| Resource ID    | Name          | Type  | Volume     | Unit | Timestamp           |
+----------------+---------------+-------+------------+------+---------------------+
| aa-bb-cc-dd-ee | memory.usage  | gauge | 101.0      | MB   | 2015-11-11T15:38:43 |
+----------------+---------------+-------+------------+------+---------------------+
```
