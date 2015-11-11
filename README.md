# The new FIWARE monitoring system

## Description

This repository contains all the pollsters and the additional customization that IOs have to perform. IOs have to customize the standard [ceilometer](https://wiki.openstack.org/wiki/Ceilometer) installation, by adding some pollsters or by editing the configuration file.

Some additional information about ceilometer: _it is a tool created in order to handle the Telemetry requirements of an OpenStack environment (this includes use cases such as metering, monitoring, and alarming to name a few)_

<img src="http://docs.openstack.org/developer/ceilometer/_images/ceilo-arch.png">

After the installation/configuration, IOs should be able to obtain information about his Openstack installation directly from his ceilometer:
- __region__
- __host__
- __vm__
- __image__
- __host service__ (nova, glance, cinder)

The installation/configuration is split in two parts, the central node, and the compute node. On the first side only the main pollsters will be installed, in the second one only the compute agent pollsters will be installed


## Installation

### Central agent pollsters

#### region
