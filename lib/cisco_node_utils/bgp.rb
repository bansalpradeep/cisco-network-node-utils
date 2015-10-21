# June 2015, Michael G Wiebe
#
# Copyright (c) 2015 Cisco and/or its affiliates.
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

require File.join(File.dirname(__FILE__), 'node_util')

module Cisco
  # RouterBgp - node utility class for BGP general config management
  class RouterBgp < NodeUtil
    attr_reader :asnum, :vrf

    def initialize(asnum, vrf='default', instantiate=true)
      fail ArgumentError unless vrf.is_a? String
      fail ArgumentError unless vrf.length > 0
      @asnum = RouterBgp.process_asnum(asnum)
      @vrf = vrf
      if @vrf == 'default'
        @get_args = @set_args = { asnum: @asnum }
      else
        @get_args = @set_args = { asnum: @asnum, vrf: @vrf }
      end
      create if instantiate
    end

    def self.process_asnum(asnum)
      err_msg = "BGP asnum must be either a 'String' or an" \
                " 'Integer' object"
      fail ArgumentError, err_msg unless asnum.is_a?(Integer) ||
                                         asnum.is_a?(String)
      if asnum.is_a? String
        # Match ASDOT '1.5' or ASPLAIN '55' strings
        fail ArgumentError unless /^(\d+|\d+\.\d+)$/.match(asnum)
        asnum = RouterBgp.dot_to_big(asnum) if /\d+\.\d+/.match(asnum)
      end
      asnum.to_i
    end

    # Create a hash of all router bgp default and non-default
    # vrf instances
    def self.routers
      bgp_ids = config_get('bgp', 'router')
      return {} if bgp_ids.nil?

      hash_final = {}
      # TODO: Remove loop if only single ASN supported by RFC?
      bgp_ids.each do |asnum|
        asnum = asnum.to_i unless /\d+.\d+/.match(asnum)
        hash_tmp = { asnum =>
          { 'default' => RouterBgp.new(asnum, 'default', false) } }
        vrf_ids = config_get('bgp', 'vrf', asnum: asnum)
        unless vrf_ids.nil?
          vrf_ids.each do |vrf|
            hash_tmp[asnum][vrf] = RouterBgp.new(asnum, vrf, false)
          end
        end
        hash_final.merge!(hash_tmp)
      end
      return hash_final
    rescue Cisco::CliError => e
      # cmd will syntax reject when feature is not enabled
      raise unless e.clierror =~ /Syntax error/
      return {}
    end

    def self.enabled
      feat = config_get('bgp', 'feature')
      return !(feat.nil? || feat.empty?)
    rescue Cisco::CliError => e
      # cmd will syntax reject when feature is not enabled
      raise unless e.clierror =~ /Syntax error/
      return false
    end

    def self.enable(state='')
      config_set('bgp', 'feature', state: state)
    end

    # Convert BGP ASN ASDOT+ to ASPLAIN
    def self.dot_to_big(dot_str)
      fail ArgumentError unless dot_str.is_a? String
      return dot_str unless /\d+\.\d+/.match(dot_str)
      mask = 0b1111111111111111
      high = dot_str.to_i
      low = 0
      low_match = dot_str.match(/\.(\d+)/)
      low = low_match[1].to_i if low_match
      high_bits = (mask & high) << 16
      low_bits = mask & low
      high_bits + low_bits
    end

    def router_bgp(asnum, vrf, state='')
      # Only one bgp autonomous system number is allowed
      # Raise an error if one is already configured that
      # differs from the one being created.
      configured = config_get('bgp', 'router')
      if !configured.nil? && configured.first.to_s != asnum.to_s
        fail %(
          Changing the BGP Autonomous System Number is not allowed.
          Current BGP asn: #{configured.first}
          Attempted change to asn: #{asnum})
      end
      @set_args[:state] = state
      if vrf == 'default'
        config_set('bgp', 'router', @set_args)
      else
        config_set('bgp', 'vrf', @set_args)
      end
      set_args_keys_default
    end

    def enable_create_router_bgp(asnum, vrf)
      RouterBgp.enable
      router_bgp(asnum, vrf)
    end

    # Create one router bgp instance
    def create
      if RouterBgp.enabled
        router_bgp(@asnum, @vrf)
      else
        enable_create_router_bgp(@asnum, @vrf)
      end
    end

    # Destroy router bgp instance
    def destroy
      vrf_ids = config_get('bgp', 'vrf', asnum: @asnum)
      vrf_ids = ['default'] if vrf_ids.nil?
      if vrf_ids.size == 1 || @vrf == 'default'
        RouterBgp.enable('no')
      else
        router_bgp(asnum, @vrf, 'no')
      end
    rescue Cisco::CliError => e
      # cmd will syntax reject when feature is not enabled
      raise unless e.clierror =~ /Syntax error/
    end

    # Helper method to delete @set_args hash keys
    def set_args_keys_default
      if @vrf == 'default'
        @set_args = { asnum: @asnum }
      else
        @set_args = { asnum: @asnum, vrf: @vrf }
      end
    end

    # Attributes:

    # Bestpath Getters
    def bestpath_always_compare_med
      match = config_get('bgp', 'bestpath_always_compare_med', @get_args)
      match.nil? ? default_bestpath_always_compare_med : true
    end

    def bestpath_aspath_multipath_relax
      match = config_get('bgp', 'bestpath_aspath_multipath_relax', @get_args)
      match.nil? ? default_bestpath_aspath_multipath_relax : true
    end

    def bestpath_compare_routerid
      match = config_get('bgp', 'bestpath_compare_routerid', @get_args)
      match.nil? ? default_bestpath_compare_routerid : true
    end

    def bestpath_cost_community_ignore
      match = config_get('bgp', 'bestpath_cost_community_ignore', @get_args)
      match.nil? ? default_bestpath_cost_community_ignore : true
    end

    def bestpath_med_confed
      match = config_get('bgp', 'bestpath_med_confed', @get_args)
      match.nil? ? default_bestpath_med_confed : true
    end

    def bestpath_med_missing_as_worst
      match = config_get('bgp', 'bestpath_med_missing_as_worst', @get_args)
      match.nil? ? default_bestpath_med_missing_as_worst : true
    end

    def bestpath_med_non_deterministic
      match = config_get('bgp', 'bestpath_med_non_deterministic', @get_args)
      match.nil? ? default_bestpath_med_non_deterministic : true
    end

    # Bestpath Setters
    def bestpath_always_compare_med=(enable)
      @set_args[:state] = (enable ? '' : 'no')
      config_set('bgp', 'bestpath_always_compare_med', @set_args)
      set_args_keys_default
    end

    def bestpath_aspath_multipath_relax=(enable)
      @set_args[:state] = (enable ? '' : 'no')
      config_set('bgp', 'bestpath_aspath_multipath_relax', @set_args)
      set_args_keys_default
    end

    def bestpath_compare_routerid=(enable)
      @set_args[:state] = (enable ? '' : 'no')
      config_set('bgp', 'bestpath_compare_routerid', @set_args)
      set_args_keys_default
    end

    def bestpath_cost_community_ignore=(enable)
      @set_args[:state] = (enable ? '' : 'no')
      config_set('bgp', 'bestpath_cost_community_ignore', @set_args)
      set_args_keys_default
    end

    def bestpath_med_confed=(enable)
      @set_args[:state] = (enable ? '' : 'no')
      config_set('bgp', 'bestpath_med_confed', @set_args)
      set_args_keys_default
    end

    def bestpath_med_missing_as_worst=(enable)
      @set_args[:state] = (enable ? '' : 'no')
      config_set('bgp', 'bestpath_med_missing_as_worst', @set_args)
      set_args_keys_default
    end

    def bestpath_med_non_deterministic=(enable)
      @set_args[:state] = (enable ? '' : 'no')
      config_set('bgp', 'bestpath_med_non_deterministic', @set_args)
      set_args_keys_default
    end

    # Bestpath Defaults
    def default_bestpath_always_compare_med
      config_get_default('bgp', 'bestpath_always_compare_med')
    end

    def default_bestpath_aspath_multipath_relax
      config_get_default('bgp', 'bestpath_aspath_multipath_relax')
    end

    def default_bestpath_compare_routerid
      config_get_default('bgp', 'bestpath_compare_routerid')
    end

    def default_bestpath_cost_community_ignore
      config_get_default('bgp', 'bestpath_cost_community_ignore')
    end

    def default_bestpath_med_confed
      config_get_default('bgp', 'bestpath_med_confed')
    end

    def default_bestpath_med_missing_as_worst
      config_get_default('bgp', 'bestpath_med_missing_as_worst')
    end

    def default_bestpath_med_non_deterministic
      config_get_default('bgp', 'bestpath_med_non_deterministic')
    end

    # Cluster Id (Getter/Setter/Default)
    def cluster_id
      match = config_get('bgp', 'cluster_id', @get_args)
      match.nil? ? default_cluster_id : match.first
    end

    def cluster_id=(id)
      # In order to remove a bgp cluster_id you cannot simply issue
      # 'no bgp cluster-id'.  IMO this should be possible because you
      # can only configure a single bgp cluster-id.
      #
      # HACK: specify a dummy id when removing the feature.
      # CSCuu76807
      dummy_id = 1
      if id == default_cluster_id
        @set_args[:state] = 'no'
        @set_args[:id] = dummy_id
      else
        @set_args[:state] = ''
        @set_args[:id] = id
      end
      config_set('bgp', 'cluster_id', @set_args)
      set_args_keys_default
    end

    def default_cluster_id
      config_get_default('bgp', 'cluster_id')
    end

    # Confederation Id (Getter/Setter/Default)
    def confederation_id
      match = config_get('bgp', 'confederation_id', @get_args)
      match.nil? ? default_confederation_id : match.first
    end

    def confederation_id=(id)
      # In order to remove a bgp confed id you cannot simply issue
      # 'no bgp confederation id'.  IMO this should be possible
      # because you can only configure a single bgp confed id.
      #
      # HACK: specify a dummy id when removing the feature.
      # CSCuu76807
      dummy_id = 1
      if id == default_confederation_id
        @set_args[:state] = 'no'
        @set_args[:id] = dummy_id
      else
        @set_args[:state] = ''
        @set_args[:id] = id
      end
      config_set('bgp', 'confederation_id', @set_args)
      set_args_keys_default
    end

    def default_confederation_id
      config_get_default('bgp', 'confederation_id')
    end

    # Enforce First As (Getter/Setter/Default)
    def enforce_first_as
      match = config_get('bgp', 'enforce_first_as', @get_args)
      match.nil? ? false : true
    end

    def enforce_first_as=(enable)
      @set_args[:state] = (enable ? '' : 'no')
      config_set('bgp', 'enforce_first_as', @set_args)
      set_args_keys_default
    end

    def default_enforce_first_as
      config_get_default('bgp', 'enforce_first_as')
    end

    # Confederation Peers (Getter/Setter/Default)
    def confederation_peers
      match = config_get('bgp', 'confederation_peers', @get_args)
      match.nil? ? default_confederation_peers : match.first
    end

    def confederation_peers_set(peers)
      # The confederation peers command is additive so we first need to
      # remove any existing peers.
      unless confederation_peers.empty?
        @set_args[:state] = 'no'
        @set_args[:peer_list] = confederation_peers
        config_set('bgp', 'confederation_peers', @set_args)
      end
      unless peers == default_confederation_peers
        @set_args[:state] = ''
        @set_args[:peer_list] = peers
        config_set('bgp', 'confederation_peers', @set_args)
      end
      set_args_keys_default
    end

    def default_confederation_peers
      config_get_default('bgp', 'confederation_peers')
    end

    # Graceful Restart Getters
    def graceful_restart
      match = config_get('bgp', 'graceful_restart', @get_args)
      match.nil? ? false : true
    end

    def graceful_restart_timers_restart
      match = config_get('bgp', 'graceful_restart_timers_restart', @get_args)
      match.nil? ? default_graceful_restart_timers_restart : match.first.to_i
    end

    def graceful_restart_timers_stalepath_time
      match = config_get('bgp', 'graceful_restart_timers_stalepath_time',
                         @get_args)
      if match.nil?
        default_graceful_restart_timers_stalepath_time
      else
        match.first.to_i
      end
    end

    def graceful_restart_helper
      match = config_get('bgp', 'graceful_restart_helper', @get_args)
      match.nil? ? default_graceful_restart_helper : true
    end

    # Graceful Restart Setters
    def graceful_restart=(enable)
      @set_args[:state] = (enable ? '' : 'no')
      config_set('bgp', 'graceful_restart', @set_args)
      set_args_keys_default
    end

    def graceful_restart_timers_restart=(seconds)
      if seconds == default_graceful_restart_timers_restart
        @set_args[:state] = 'no'
        @set_args[:seconds] = ''
      else
        @set_args[:state] = ''
        @set_args[:seconds] = seconds
      end
      config_set('bgp', 'graceful_restart_timers_restart', @set_args)
      set_args_keys_default
    end

    def graceful_restart_timers_stalepath_time=(seconds)
      if seconds == default_graceful_restart_timers_stalepath_time
        @set_args[:state] = 'no'
        @set_args[:seconds] = ''
      else
        @set_args[:state] = ''
        @set_args[:seconds] = seconds
      end
      config_set('bgp', 'graceful_restart_timers_stalepath_time', @set_args)
      set_args_keys_default
    end

    def graceful_restart_helper=(enable)
      @set_args[:state] = (enable ? '' : 'no')
      config_set('bgp', 'graceful_restart_helper', @set_args)
      set_args_keys_default
    end

    # Graceful Restart Defaults
    def default_graceful_restart
      config_get_default('bgp', 'graceful_restart')
    end

    def default_graceful_restart_timers_restart
      config_get_default('bgp', 'graceful_restart_timers_restart')
    end

    def default_graceful_restart_timers_stalepath_time
      config_get_default('bgp', 'graceful_restart_timers_stalepath_time')
    end

    def default_graceful_restart_helper
      config_get_default('bgp', 'graceful_restart_helper')
    end

    # Log Neighbor Changes (Getter/Setter/Default)
    def log_neighbor_changes
      match = config_get('bgp', 'log_neighbor_changes', @get_args)
      match.nil? ? default_log_neighbor_changes : true
    end

    def log_neighbor_changes=(enable)
      @set_args[:state] = (enable ? '' : 'no')
      config_set('bgp', 'log_neighbor_changes', @set_args)
      set_args_keys_default
    end

    def default_log_neighbor_changes
      config_get_default('bgp', 'log_neighbor_changes')
    end

    # Neighbor fib down accelerate (Getter/Setter/Default)
    def neighbor_fib_down_accelerate
      match = config_get('bgp', 'neighbor_fib_down_accelerate', @get_args)
      match.nil? ? default_neighbor_fib_down_accelerate : true
    end

    def neighbor_fib_down_accelerate=(enable)
      @set_args[:state] = (enable ? '' : 'no')
      config_set('bgp', 'neighbor_fib_down_accelerate', @set_args)
      set_args_keys_default
    end

    def default_neighbor_fib_down_accelerate
      config_get_default('bgp', 'neighbor_fib_down_accelerate')
    end

    # Reconnect Interval (Getter/Setter/Default)
    def reconnect_interval
      match = config_get('bgp', 'reconnect_interval', @get_args)
      match.nil? ? default_reconnect_interval : match.first.to_i
    end

    def reconnect_interval=(seconds)
      if seconds == default_reconnect_interval
        @set_args[:state] = 'no'
        @set_args[:seconds] = ''
      else
        @set_args[:state] = ''
        @set_args[:seconds] = seconds
      end
      config_set('bgp', 'reconnect_interval', @set_args)
      set_args_keys_default
    end

    def default_reconnect_interval
      config_get_default('bgp', 'reconnect_interval')
    end

    # Router ID (Getter/Setter/Default)
    def router_id
      match = config_get('bgp', 'router_id', @get_args)
      match.nil? ? default_router_id : match.first
    end

    def router_id=(id)
      # In order to remove a bgp router-id you cannot simply issue
      # 'no bgp router-id'.  IMO this should be possible because you can only
      # configure a single bgp router-id.  I filed CSCuu76807 to track this
      # issue but it was closed.  Dummy-id specified to work around this.
      dummy_id = '1.2.3.4'
      if id == default_router_id
        @set_args[:state] = 'no'
        @set_args[:id] = dummy_id
      else
        @set_args[:state] = ''
        @set_args[:id] = id
      end
      config_set('bgp', 'router_id', @set_args)
      set_args_keys_default
    end

    def default_router_id
      config_get_default('bgp', 'router_id')
    end

    # Shutdown (Getter/Setter/Default)
    def shutdown
      match = config_get('bgp', 'shutdown', @asnum)
      match.nil? ? default_shutdown : true
    end

    def shutdown=(enable)
      @set_args[:state] = (enable ? '' : 'no')
      config_set('bgp', 'shutdown', @set_args)
      set_args_keys_default
    end

    def default_shutdown
      config_get_default('bgp', 'shutdown')
    end

    # Supress Fib Pending (Getter/Setter/Default)
    def suppress_fib_pending
      match = config_get('bgp', 'suppress_fib_pending', @get_args)
      match.nil? ? default_suppress_fib_pending : true
    end

    def suppress_fib_pending=(enable)
      enable == true ? @set_args[:state] = '' : @set_args[:state] = 'no'
      config_set('bgp', 'suppress_fib_pending', @set_args)
      set_args_keys_default
    end

    def default_suppress_fib_pending
      config_get_default('bgp', 'suppress_fib_pending')
    end

    # BGP Timers Getters
    def timer_bgp_keepalive_hold
      match = config_get('bgp', 'timer_bgp_keepalive_hold', @get_args)
      match.nil? ? default_timer_bgp_keepalive_hold : match.first
    end

    def timer_bgp_keepalive
      keepalive, _hold = timer_bgp_keepalive_hold
      return default_timer_bgp_keepalive if keepalive.nil?
      keepalive.to_i
    end

    def timer_bgp_holdtime
      _keepalive, hold = timer_bgp_keepalive_hold
      return default_timer_bgp_holdtime if hold.nil?
      hold.to_i
    end

    def timer_bestpath_limit
      match = config_get('bgp', 'timer_bestpath_limit', @get_args)
      match.nil? ? default_timer_bestpath_limit : match.first.to_i
    end

    def timer_bestpath_limit_always
      match = config_get('bgp', 'timer_bestpath_limit_always', @get_args)
      match.nil? ? default_timer_bestpath_limit_always : true
    end

    # BGP Timers Setters
    def timer_bgp_keepalive_hold_set(keepalive, hold)
      if keepalive == default_timer_bgp_keepalive &&
         hold == default_timer_bgp_holdtime
        @set_args[:state] = 'no'
        @set_args[:keepalive] = keepalive
        @set_args[:hold] = hold
      else
        @set_args[:state] = ''
        @set_args[:keepalive] = keepalive
        @set_args[:hold] = hold
      end
      config_set('bgp', 'timer_bgp_keepalive_hold', @set_args)
      set_args_keys_default
    end

    def timer_bestpath_limit_set(seconds, always=false)
      if always
        feature = 'timer_bestpath_limit_always'
      else
        feature = 'timer_bestpath_limit'
      end
      if seconds == default_timer_bestpath_limit
        @set_args[:state] = 'no'
        @set_args[:seconds] = ''
      else
        @set_args[:state] = ''
        @set_args[:seconds] = seconds
      end
      config_set('bgp', feature, @set_args)
      set_args_keys_default
    end

    # BGP Timers Defaults
    def default_timer_bgp_keepalive_hold
      ["#{default_timer_bgp_keepalive}", "#{default_timer_bgp_holdtime}"]
    end

    def default_timer_bgp_keepalive
      config_get_default('bgp', 'timer_bgp_keepalive')
    end

    def default_timer_bgp_holdtime
      config_get_default('bgp', 'timer_bgp_hold')
    end

    def default_timer_bestpath_limit
      config_get_default('bgp', 'timer_bestpath_limit')
    end

    def default_timer_bestpath_limit_always
      config_get_default('bgp', 'timer_bestpath_limit_always')
    end
  end
end
