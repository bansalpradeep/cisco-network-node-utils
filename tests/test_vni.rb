# Copyright (c) 2013-2015 Cisco and/or its affiliates.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require_relative 'ciscotest'
require_relative '../lib/cisco_node_utils/feature'
require_relative '../lib/cisco_node_utils/vni'
require_relative '../lib/cisco_node_utils/vdc'

include Cisco

# TestVni - Minitest for Vni node utility
class TestVni < CiscoTestCase
  def setup
    super
    skip('Platform does not support MT-full or MT-lite') unless
      Vni.mt_full_support || Vni.mt_lite_support
    skip('Platform does not support nv overlay feature') unless
      Feature.nv_overlay_supported?
  end

  def teardown
    return unless Vdc.vdc_support
    # Reset the vdc module type back to default
    v = Vdc.new('default')
    v.limit_resource_module_type = '' if v.limit_resource_module_type == 'f3'
  end

  def compatible_interface?
    # This test requires specific linecards; find a compatible linecard
    # and create an appropriate interface name from it.
    # Example 'show mod' output to match against:
    # '9    12     10/40 Gbps Ethernet Module          N7K-F312FQ-25      ok'
    sh_mod = @device.cmd("sh mod | i '^[0-9]+.*N7K-F3'")[/^(\d+)\s.*N7K-F3/]
    slot = sh_mod.nil? ? nil : Regexp.last_match[1]
    skip('Unable to find compatible interface in chassis') if slot.nil?

    "ethernet#{slot}/1"
  end

  def mt_full_env_setup
    skip('Platform does not support MT-full') unless Vni.mt_full_support
    compatible_interface?
    v = Vdc.new('default')
    v.limit_resource_module_type = 'f3' unless
      v.limit_resource_module_type == 'f3'
    config('no feature vni')
    config('no feature nv overlay')
  end

  def mt_lite_env_setup
    skip('Platform does not support MT-lite') unless Vni.mt_lite_support
    config('no feature vn-segment-vlan-based')
    config('no feature nv overlay')
  end

  def test_mt_full_vni_create_destroy
    mt_full_env_setup

    v1 = Vni.new(10_001)
    v2 = Vni.new(10_002)
    v3 = Vni.new(10_003)
    assert_equal(3, Vni.vnis.keys.count)

    v2.destroy
    assert_equal(2, Vni.vnis.keys.count)

    v1.destroy
    v3.destroy
    assert_equal(0, Vni.vnis.keys.count)
  end

  # def test_mt_full_encapsulation_dot1q
  # TBD
  #  mt_full_env_setup
  # end

  # def test_mt_full_mapped_bd
  # TBD
  #  mt_full_env_setup
  # end

  def test_mt_full_shutdown
    mt_full_env_setup
    vni = Vni.new(10_000)
    vni.shutdown = true
    assert(vni.shutdown)

    vni.shutdown = false
    refute(vni.shutdown)

    vni.shutdown = !vni.default_shutdown
    assert_equal(!vni.default_shutdown, vni.shutdown)

    vni.shutdown = vni.default_shutdown
    assert_equal(vni.default_shutdown, vni.shutdown)
  end

  def test_mt_lite_mapped_vlan
    mt_lite_env_setup
    # Set the vni vlan mapping
    v = Vni.new(10_000)
    v.mapped_vlan = 100
    assert_equal(100, v.mapped_vlan,
                 'Error: mapped-vlan mismatch')
    # Now clear the vni vlan mapping
    v.mapped_vlan = v.default_mapped_vlan
    assert_nil(v.mapped_vlan, 'Error: cannot clear vni vlan mapping')
    v.destroy

    # Multiples: Set vni to vlan mappings
    vni_to_vlan_map = { 10_000 => 100, 20_000 => 200, 30_000 => 300 }
    vni_to_vlan_map.each do |vni, vlan|
      v = Vni.new(vni)
      v.mapped_vlan = vlan
      assert_equal(vlan, v.mapped_vlan, 'Error: mapped-vlan mismatch')
    end
    # Clear all mappings
    vni_to_vlan_map.each do |vni, _|
      v = Vni.new(vni)
      v.mapped_vlan = v.default_mapped_vlan
      assert_nil(v.mapped_vlan, 'Error: cannot clear vni vlan mapping')
    end
  end
end
