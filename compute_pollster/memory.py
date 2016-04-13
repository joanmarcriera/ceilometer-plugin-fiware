#
# Copyright 2015 CREATE-NET <abroglio AT create-net DOT org>
#
# Author: Attilio Broglio <abroglio AT create-net DOT org>
#
# Version: 1.1.0
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.
import ceilometer
from ceilometer.compute import plugin
from ceilometer.compute.pollsters import util
from ceilometer.compute.virt import inspector as virt_inspector
from ceilometer.openstack.common.gettextutils import _
from ceilometer.openstack.common import log
from ceilometer import sample

LOG = log.getLogger(__name__)

class MemoryUsagePollster(plugin.ComputePollster):

    def get_samples(self, manager, cache, resources):
        self._inspection_duration = self._record_poll_time()
        for instance in resources:
            LOG.debug(_('Checking memory usage for instance %s'), instance.id)
            try:
                instance_name = util.instance_name(instance)
                memory_info = manager.inspector.inspect_memory_usage( instance_name, self._inspection_duration)
                if (memory_info):
                    usg=memory_info.usage
                else:
                    usg=0;
                # Workaround https://bugs.launchpad.net/fuel/+bug/1379794
                LOG.debug(_("MEMORY USAGE: %(instance)s %(usage)f"),
                          ({'instance': getattr(instance, 'id'),
                            'usage': usg}))
                yield util.make_sample_from_instance(
                    instance,
                    name='memory.usage',
                    type=sample.TYPE_GAUGE,
                    unit='MB',
                    volume=usg,
                )
            except virt_inspector.InstanceNotFoundException as err:
                # Instance was deleted while getting samples. Ignore it.
                LOG.debug(_('Exception while getting samples %s'), err)
            except ceilometer.NotImplementedError:
                # Selected inspector does not implement this pollster.
                LOG.debug(_('Obtaining Memory Usage is not implemented for %s'
                            ), manager.inspector.__class__.__name__)
            except Exception as err:
                LOG.exception(_('Could not get Memory Usage for '
                                '%(id)s: %(e)s'), {'id': instance.id,
                                                   'e': err})

class MemoryResidentPollster(plugin.ComputePollster):
    def get_samples(self, manager, cache, resources):
        self._inspection_duration = self._record_poll_time()
        for instance in resources:
            LOG.debug('Checking resident memory for instance %s',
                      instance.id)
            instance_name = util.instance_name(instance)
            try:
                memory_info = manager.inspector.inspect_memory_resident(
                    instance_name, self._inspection_duration)
                LOG.debug("RESIDENT MEMORY: %(instance)s %(resident)f",
                          {'instance': instance,
                           'resident': memory_info.resident})
                yield util.make_sample_from_instance(
                    instance,
                    name='memory.resident',
                    type=sample.TYPE_GAUGE,
                    unit='MB',
                    volume=memory_info.resident,
                )
            except virt_inspector.InstanceNotFoundException as err:
                # Instance was deleted while getting samples. Ignore it.
                LOG.debug('Exception while getting samples %s', err)
            except ceilometer.NotImplementedError:
                # Selected inspector does not implement this pollster.
                LOG.debug('Obtaining Resident Memory is not implemented'
                          ' for %s', self.inspector.__class__.__name__)
            except Exception as err:
                LOG.exception(_('Could not get Resident Memory Usage for '
                                  '%(id)s: %(e)s'), {'id': instance.id,
                                                     'e': err})
